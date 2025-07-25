using Microsoft.AspNetCore.SignalR;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using WebApi.Hubs;

namespace WebApi.Services;

public class MqttSubscriberBackgroundService : BackgroundService
{
    private readonly ILogger<MqttSubscriberBackgroundService> _logger;
    private readonly IMqttSubscriberService _mqttSubscriber;
    private readonly ITelemetryDataService _dataService;
    private readonly IMetricsService _metricsService;
    private readonly IHubContext<TelemetryHub> _hubContext;
    private readonly TimeSpan _reconnectInterval = TimeSpan.FromSeconds(30);

    public MqttSubscriberBackgroundService(
        ILogger<MqttSubscriberBackgroundService> logger,
        IMqttSubscriberService mqttSubscriber,
        ITelemetryDataService dataService,
        IMetricsService metricsService,
        IHubContext<TelemetryHub> hubContext)
    {
        _logger = logger;
        _mqttSubscriber = mqttSubscriber;
        _dataService = dataService;
        _metricsService = metricsService;
        _hubContext = hubContext;

        // Subscribe to MQTT events
        _mqttSubscriber.TelemetryReceived += OnTelemetryReceived;
        _mqttSubscriber.StatusReceived += OnStatusReceived;
        _mqttSubscriber.AlertReceived += OnAlertReceived;
        _mqttSubscriber.ConnectionStatusChanged += OnConnectionStatusChanged;
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        _logger.LogInformation("MQTT Subscriber Background Service starting...");

        // Wait for certificates to be available
        await WaitForCertificatesAsync(stoppingToken);

        // Main connection loop
        while (!stoppingToken.IsCancellationRequested)
        {
            try
            {
                if (!_mqttSubscriber.IsConnected)
                {
                    _logger.LogInformation("Attempting to connect to MQTT broker...");
                    _metricsService.IncrementMqttConnectionAttempts();

                    var connected = await _mqttSubscriber.ConnectAsync();
                    if (connected)
                    {
                        _logger.LogInformation("Successfully connected to MQTT broker");
                        _metricsService.SetMqttConnectionStatus(true);
                    }
                    else
                    {
                        _logger.LogWarning("Failed to connect to MQTT broker, will retry in {Interval}", _reconnectInterval);
                        _metricsService.IncrementMqttConnectionFailures();
                        _metricsService.SetMqttConnectionStatus(false);
                        await Task.Delay(_reconnectInterval, stoppingToken);
                    }
                }
                else
                {
                    // Connection is healthy, wait a bit before checking again
                    await Task.Delay(TimeSpan.FromSeconds(10), stoppingToken);
                }
            }
            catch (OperationCanceledException)
            {
                _logger.LogInformation("MQTT Subscriber Background Service stopping due to cancellation");
                break;
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error in MQTT Subscriber Background Service");
                _metricsService.IncrementMqttConnectionFailures();
                await Task.Delay(_reconnectInterval, stoppingToken);
            }
        }

        // Cleanup
        await _mqttSubscriber.DisconnectAsync();
        _logger.LogInformation("MQTT Subscriber Background Service stopped");
    }

    private async Task WaitForCertificatesAsync(CancellationToken cancellationToken)
    {
        _logger.LogInformation("Waiting for certificates to become available...");

        // In a real implementation, you'd check certificate availability
        // For now, we'll just wait a bit for the certbot containers to provision certificates
        await Task.Delay(TimeSpan.FromSeconds(30), cancellationToken);
        
        _logger.LogInformation("Certificate wait period completed, proceeding with MQTT connection");
    }

    private async void OnTelemetryReceived(object? sender, TelemetryReceivedEventArgs e)
    {
        var stopwatch = System.Diagnostics.Stopwatch.StartNew();
        
        try
        {
            // Store in data service
            _dataService.StoreTelemetry(e.Telemetry);
            _metricsService.IncrementTelemetryMessagesReceived();

            // Broadcast to SignalR clients
            var broadcastStopwatch = System.Diagnostics.Stopwatch.StartNew();
            
            // Send to specific device group
            await _hubContext.Clients.Group($"device-{e.Telemetry.DeviceId}")
                .SendAsync("TelemetryUpdate", e.Telemetry);
            
            // Send to all devices group
            await _hubContext.Clients.Group("all-devices")
                .SendAsync("TelemetryUpdate", e.Telemetry);

            broadcastStopwatch.Stop();
            _metricsService.RecordSignalRBroadcastTime(broadcastStopwatch.ElapsedMilliseconds);

            _logger.LogDebug("Processed telemetry from {DeviceId}: Status={Status}, RPM={Rpm}", 
                e.Telemetry.DeviceId, e.Telemetry.Status, e.Telemetry.Rpm);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to process telemetry from {DeviceId}", e.Telemetry.DeviceId);
        }
        finally
        {
            stopwatch.Stop();
            _metricsService.RecordMessageProcessingTime(stopwatch.ElapsedMilliseconds);
        }
    }

    private async void OnStatusReceived(object? sender, StatusReceivedEventArgs e)
    {
        var stopwatch = System.Diagnostics.Stopwatch.StartNew();
        
        try
        {
            // Store in data service
            _dataService.StoreStatus(e.Status);
            _metricsService.IncrementStatusMessagesReceived();

            // Broadcast to SignalR clients
            var broadcastStopwatch = System.Diagnostics.Stopwatch.StartNew();
            
            // Send to specific device group
            await _hubContext.Clients.Group($"device-{e.Status.DeviceId}")
                .SendAsync("StatusUpdate", e.Status);
            
            // Send to all devices group
            await _hubContext.Clients.Group("all-devices")
                .SendAsync("StatusUpdate", e.Status);

            broadcastStopwatch.Stop();
            _metricsService.RecordSignalRBroadcastTime(broadcastStopwatch.ElapsedMilliseconds);

            _logger.LogDebug("Processed status from {DeviceId}: Status={Status}, Uptime={Uptime}h", 
                e.Status.DeviceId, e.Status.Status, e.Status.UptimeHours);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to process status from {DeviceId}", e.Status.DeviceId);
        }
        finally
        {
            stopwatch.Stop();
            _metricsService.RecordMessageProcessingTime(stopwatch.ElapsedMilliseconds);
        }
    }

    private async void OnAlertReceived(object? sender, AlertReceivedEventArgs e)
    {
        var stopwatch = System.Diagnostics.Stopwatch.StartNew();
        
        try
        {
            // Store in data service
            _dataService.StoreAlert(e.Alert);
            _metricsService.IncrementAlertMessagesReceived();

            // Broadcast to SignalR clients
            var broadcastStopwatch = System.Diagnostics.Stopwatch.StartNew();
            
            // Send to specific device group
            await _hubContext.Clients.Group($"device-{e.Alert.DeviceId}")
                .SendAsync("AlertUpdate", e.Alert);
            
            // Send to all devices group
            await _hubContext.Clients.Group("all-devices")
                .SendAsync("AlertUpdate", e.Alert);

            broadcastStopwatch.Stop();
            _metricsService.RecordSignalRBroadcastTime(broadcastStopwatch.ElapsedMilliseconds);

            _logger.LogInformation("Processed alert from {DeviceId}: {AlertType} - {Message}", 
                e.Alert.DeviceId, e.Alert.AlertType, e.Alert.Message);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to process alert from {DeviceId}", e.Alert.DeviceId);
        }
        finally
        {
            stopwatch.Stop();
            _metricsService.RecordMessageProcessingTime(stopwatch.ElapsedMilliseconds);
        }
    }

    private void OnConnectionStatusChanged(object? sender, string status)
    {
        _logger.LogInformation("MQTT connection status changed: {Status}", status);
        
        var isConnected = status.StartsWith("Connected");
        _metricsService.SetMqttConnectionStatus(isConnected);
        
        // Broadcast connection status to all clients
        _ = Task.Run(async () =>
        {
            try
            {
                await _hubContext.Clients.All.SendAsync("MqttConnectionStatusChanged", new
                {
                    Status = status,
                    IsConnected = isConnected,
                    Timestamp = DateTime.UtcNow
                });
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Failed to broadcast MQTT connection status change");
            }
        });
    }
}