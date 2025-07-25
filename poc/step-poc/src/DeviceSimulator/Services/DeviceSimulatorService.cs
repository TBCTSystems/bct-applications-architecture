using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;

namespace DeviceSimulator.Services;

public class DeviceSimulatorService : BackgroundService
{
    private readonly ILogger<DeviceSimulatorService> _logger;
    private readonly IMqttService _mqttService;
    private readonly ITelemetryGenerator _telemetryGenerator;
    private readonly ICertificateManager _certificateManager;
    private readonly IMetricsService _metricsService;
    private readonly HealthService _healthService;
    private readonly string _deviceId;

    // Timing configuration
    private readonly TimeSpan _telemetryInterval = TimeSpan.FromSeconds(10);
    private readonly TimeSpan _statusInterval = TimeSpan.FromMinutes(1);
    private readonly TimeSpan _connectionRetryInterval = TimeSpan.FromSeconds(30);

    private DateTime _lastStatusUpdate = DateTime.MinValue;
    private int _telemetryCount = 0;
    private int _connectionAttempts = 0;

    public DeviceSimulatorService(
        ILogger<DeviceSimulatorService> logger,
        IMqttService mqttService,
        ITelemetryGenerator telemetryGenerator,
        ICertificateManager certificateManager,
        IMetricsService metricsService,
        IHealthService healthService)
    {
        _logger = logger;
        _mqttService = mqttService;
        _telemetryGenerator = telemetryGenerator;
        _certificateManager = certificateManager;
        _metricsService = metricsService;
        _healthService = (HealthService)healthService;
        _deviceId = Environment.GetEnvironmentVariable("DEVICE_ID") ?? "centrifuge-001";

        // Subscribe to connection status changes
        _mqttService.ConnectionStatusChanged += OnConnectionStatusChanged;
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        _logger.LogInformation("Blood Separator Centrifuge Device Simulator starting for device {DeviceId}", _deviceId);

        // Wait for certificates to be available
        await WaitForCertificatesAsync(stoppingToken);

        // Initial MQTT connection
        await EnsureMqttConnectionAsync();

        // Main simulation loop
        while (!stoppingToken.IsCancellationRequested)
        {
            try
            {
                // Ensure MQTT connection is active
                if (!_mqttService.IsConnected)
                {
                    await EnsureMqttConnectionAsync();
                }

                if (_mqttService.IsConnected)
                {
                    // Generate and publish telemetry
                    await PublishTelemetryAsync();

                    // Publish status update if interval has passed
                    if (DateTime.UtcNow - _lastStatusUpdate >= _statusInterval)
                    {
                        await PublishStatusAsync();
                        _lastStatusUpdate = DateTime.UtcNow;
                    }

                    // Occasionally publish alerts
                    await PublishAlertsAsync();
                }
                else
                {
                    _logger.LogWarning("MQTT connection not available, skipping telemetry cycle");
                }

                // Wait for next telemetry interval
                await Task.Delay(_telemetryInterval, stoppingToken);
            }
            catch (OperationCanceledException)
            {
                _logger.LogInformation("Device simulator stopping due to cancellation");
                break;
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error in device simulator main loop");
                await Task.Delay(TimeSpan.FromSeconds(5), stoppingToken);
            }
        }

        // Cleanup
        await _mqttService.DisconnectAsync();
        _logger.LogInformation("Blood Separator Centrifuge Device Simulator stopped");
    }

    private async Task WaitForCertificatesAsync(CancellationToken cancellationToken)
    {
        _logger.LogInformation("Waiting for certificates to become available...");

        while (!cancellationToken.IsCancellationRequested)
        {
            var clientCert = await _certificateManager.GetClientCertificateAsync();
            var caCert = await _certificateManager.GetCaCertificateAsync();

            if (clientCert != null && caCert != null)
            {
                _logger.LogInformation("Certificates are available and valid");
                return;
            }

            _logger.LogInformation("Certificates not yet available, waiting 10 seconds...");
            await Task.Delay(TimeSpan.FromSeconds(10), cancellationToken);
        }
    }

    private async Task EnsureMqttConnectionAsync()
    {
        if (_mqttService.IsConnected)
        {
            _metricsService.SetConnectionStatus(true);
            return;
        }

        try
        {
            _connectionAttempts++;
            _metricsService.IncrementConnectionAttempts();
            _healthService.RecordConnectionAttempt();
            _logger.LogInformation("Attempting MQTT connection (attempt {Attempt})", _connectionAttempts);

            var connected = await _mqttService.ConnectAsync();
            if (connected)
            {
                _logger.LogInformation("Successfully connected to MQTT broker");
                _metricsService.SetConnectionStatus(true);
                _connectionAttempts = 0; // Reset counter on successful connection
            }
            else
            {
                _logger.LogWarning("Failed to connect to MQTT broker, will retry in {RetryInterval}", _connectionRetryInterval);
                _metricsService.IncrementConnectionFailures();
                _metricsService.SetConnectionStatus(false);
                await Task.Delay(_connectionRetryInterval);
            }
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Exception during MQTT connection attempt");
            _metricsService.IncrementConnectionFailures();
            _metricsService.SetConnectionStatus(false);
            await Task.Delay(_connectionRetryInterval);
        }
    }

    private async Task PublishTelemetryAsync()
    {
        var stopwatch = System.Diagnostics.Stopwatch.StartNew();
        try
        {
            var telemetry = _telemetryGenerator.GenerateTelemetry();
            _metricsService.RecordTelemetryGenerationTime(stopwatch.ElapsedMilliseconds);
            
            stopwatch.Restart();
            await _mqttService.PublishTelemetryAsync(telemetry);
            _metricsService.RecordMqttPublishTime(stopwatch.ElapsedMilliseconds);
            
            _telemetryCount++;
            _metricsService.IncrementTelemetryMessagesSent();
            _metricsService.SetLastMessageTimestamp();
            _healthService.RecordTelemetryMessage();
            
            if (_telemetryCount % 10 == 0) // Log every 10th telemetry message
            {
                _logger.LogInformation("Published {TelemetryCount} telemetry messages", _telemetryCount);
            }
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to publish telemetry");
        }
        finally
        {
            stopwatch.Stop();
        }
    }

    private async Task PublishStatusAsync()
    {
        try
        {
            var status = _telemetryGenerator.GenerateStatusUpdate();
            await _mqttService.PublishStatusAsync(status);
            
            _metricsService.IncrementStatusMessagesSent();
            _metricsService.SetLastMessageTimestamp();
            _healthService.RecordStatusMessage();
            
            _logger.LogDebug("Published status update");
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to publish status update");
        }
    }

    private async Task PublishAlertsAsync()
    {
        try
        {
            var alert = _telemetryGenerator.GenerateAlert();
            if (alert != null)
            {
                await _mqttService.PublishAlertAsync(alert);
                
                _metricsService.IncrementAlertMessagesSent();
                _metricsService.SetLastMessageTimestamp();
                _healthService.RecordAlertMessage();
                
                _logger.LogDebug("Published alert");
            }
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to publish alert");
        }
    }

    private void OnConnectionStatusChanged(object? sender, string status)
    {
        _logger.LogInformation("MQTT connection status changed: {Status}", status);
    }
}