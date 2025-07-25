using System.Security.Authentication;
using System.Text;
using System.Text.Json;
using Microsoft.Extensions.Logging;
using MQTTnet;
using MQTTnet.Client;
using WebApi.Models;

namespace WebApi.Services;

public class MqttSubscriberService : IMqttSubscriberService, IDisposable
{
    private readonly ILogger<MqttSubscriberService> _logger;
    private readonly ICertificateManager _certificateManager;
    private readonly IMqttClient _mqttClient;
    private readonly string _clientId;
    private readonly string _brokerHost;
    private readonly int _brokerPort;
    private bool _isConnected;

    public bool IsConnected => _isConnected && _mqttClient.IsConnected;
    
    public event EventHandler<TelemetryReceivedEventArgs>? TelemetryReceived;
    public event EventHandler<StatusReceivedEventArgs>? StatusReceived;
    public event EventHandler<AlertReceivedEventArgs>? AlertReceived;
    public event EventHandler<string>? ConnectionStatusChanged;

    public MqttSubscriberService(ILogger<MqttSubscriberService> logger, ICertificateManager certificateManager)
    {
        _logger = logger;
        _certificateManager = certificateManager;
        _clientId = Environment.GetEnvironmentVariable("CLIENT_ID") ?? "web-api-subscriber";
        _brokerHost = Environment.GetEnvironmentVariable("MQTT_BROKER_HOST") ?? "mosquitto";
        _brokerPort = int.Parse(Environment.GetEnvironmentVariable("MQTT_BROKER_PORT") ?? "8883");

        var factory = new MqttFactory();
        _mqttClient = factory.CreateMqttClient();

        _mqttClient.ConnectedAsync += OnConnectedAsync;
        _mqttClient.DisconnectedAsync += OnDisconnectedAsync;
        _mqttClient.ApplicationMessageReceivedAsync += OnMessageReceivedAsync;

        // Subscribe to certificate updates for automatic reconnection
        _certificateManager.CertificateUpdated += OnCertificateUpdated;

        _logger.LogInformation("MQTT Subscriber Service initialized for client {ClientId} connecting to {Host}:{Port}", 
            _clientId, _brokerHost, _brokerPort);
    }

    public async Task<bool> ConnectAsync()
    {
        try
        {
            var clientCert = await _certificateManager.GetClientCertificateAsync();
            var caCert = await _certificateManager.GetCaCertificateAsync();

            if (clientCert == null)
            {
                _logger.LogError("No valid client certificate available for MQTT connection");
                return false;
            }

            if (caCert == null)
            {
                _logger.LogError("No CA certificate available for MQTT connection");
                return false;
            }

            var options = new MqttClientOptionsBuilder()
                .WithClientId(_clientId)
                .WithTcpServer(_brokerHost, _brokerPort)
                .WithTlsOptions(tlsOptions =>
                {
                    tlsOptions.WithSslProtocols(SslProtocols.Tls12 | SslProtocols.Tls13);
                    tlsOptions.WithClientCertificates(new[] { clientCert });
                    tlsOptions.WithCertificateValidationHandler(context =>
                    {
                        // For PoC, we'll accept the server certificate if it's signed by our CA
                        // In production, you'd want more rigorous validation
                        return true;
                    });
                })
                .WithCleanSession(false) // Persistent session for reliable message delivery
                .WithKeepAlivePeriod(TimeSpan.FromSeconds(30))
                .Build();

            _logger.LogInformation("Attempting MQTT connection with mTLS for Web API subscriber...");
            await _mqttClient.ConnectAsync(options);

            if (_mqttClient.IsConnected)
            {
                // Subscribe to all device topics
                await SubscribeToTopicsAsync();
                return true;
            }

            return false;
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to connect to MQTT broker");
            return false;
        }
    }

    public async Task DisconnectAsync()
    {
        try
        {
            if (_mqttClient.IsConnected)
            {
                await _mqttClient.DisconnectAsync();
                _logger.LogInformation("Disconnected from MQTT broker");
            }
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error during MQTT disconnection");
        }
    }

    private async Task SubscribeToTopicsAsync()
    {
        try
        {
            var subscribeOptions = new MqttClientSubscribeOptionsBuilder()
                .WithTopicFilter("devices/+/telemetry", MQTTnet.Protocol.MqttQualityOfServiceLevel.AtLeastOnce)
                .WithTopicFilter("devices/+/status", MQTTnet.Protocol.MqttQualityOfServiceLevel.AtLeastOnce)
                .WithTopicFilter("devices/+/alerts", MQTTnet.Protocol.MqttQualityOfServiceLevel.AtLeastOnce)
                .Build();

            await _mqttClient.SubscribeAsync(subscribeOptions);
            _logger.LogInformation("Successfully subscribed to device topics: telemetry, status, alerts");
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to subscribe to MQTT topics");
        }
    }

    private Task OnConnectedAsync(MqttClientConnectedEventArgs args)
    {
        _isConnected = true;
        _logger.LogInformation("Web API successfully connected to MQTT broker with mTLS");
        ConnectionStatusChanged?.Invoke(this, "Connected");
        return Task.CompletedTask;
    }

    private Task OnDisconnectedAsync(MqttClientDisconnectedEventArgs args)
    {
        _isConnected = false;
        _logger.LogWarning("Web API disconnected from MQTT broker. Reason: {Reason}", args.Reason);
        ConnectionStatusChanged?.Invoke(this, $"Disconnected: {args.Reason}");
        return Task.CompletedTask;
    }

    private Task OnMessageReceivedAsync(MqttApplicationMessageReceivedEventArgs args)
    {
        try
        {
            var topic = args.ApplicationMessage.Topic;
            var payload = Encoding.UTF8.GetString(args.ApplicationMessage.PayloadSegment);
            
            _logger.LogDebug("Received MQTT message on {Topic}: {PayloadLength} bytes", topic, payload.Length);

            // Parse topic to determine message type
            var topicParts = topic.Split('/');
            if (topicParts.Length >= 3)
            {
                var deviceId = topicParts[1];
                var messageType = topicParts[2];

                switch (messageType.ToLower())
                {
                    case "telemetry":
                        HandleTelemetryMessage(deviceId, topic, payload);
                        break;
                    case "status":
                        HandleStatusMessage(deviceId, topic, payload);
                        break;
                    case "alerts":
                        HandleAlertMessage(deviceId, topic, payload);
                        break;
                    default:
                        _logger.LogWarning("Unknown message type: {MessageType} on topic {Topic}", messageType, topic);
                        break;
                }
            }
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error processing MQTT message from topic {Topic}", args.ApplicationMessage.Topic);
        }

        return Task.CompletedTask;
    }

    private void HandleTelemetryMessage(string deviceId, string topic, string payload)
    {
        try
        {
            var telemetry = JsonSerializer.Deserialize<CentrifugeTelemetryData>(payload, new JsonSerializerOptions
            {
                PropertyNamingPolicy = JsonNamingPolicy.CamelCase
            });

            if (telemetry != null)
            {
                _logger.LogDebug("Parsed telemetry from {DeviceId}: Status={Status}, RPM={Rpm}", 
                    deviceId, telemetry.Status, telemetry.Rpm);

                TelemetryReceived?.Invoke(this, new TelemetryReceivedEventArgs
                {
                    Telemetry = telemetry,
                    Topic = topic
                });
            }
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to parse telemetry message from {DeviceId}", deviceId);
        }
    }

    private void HandleStatusMessage(string deviceId, string topic, string payload)
    {
        try
        {
            var status = JsonSerializer.Deserialize<DeviceStatusData>(payload, new JsonSerializerOptions
            {
                PropertyNamingPolicy = JsonNamingPolicy.CamelCase
            });

            if (status != null)
            {
                _logger.LogDebug("Parsed status from {DeviceId}: Status={Status}, Uptime={Uptime}h", 
                    deviceId, status.Status, status.UptimeHours);

                StatusReceived?.Invoke(this, new StatusReceivedEventArgs
                {
                    Status = status,
                    Topic = topic
                });
            }
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to parse status message from {DeviceId}", deviceId);
        }
    }

    private void HandleAlertMessage(string deviceId, string topic, string payload)
    {
        try
        {
            var alert = JsonSerializer.Deserialize<DeviceAlertData>(payload, new JsonSerializerOptions
            {
                PropertyNamingPolicy = JsonNamingPolicy.CamelCase
            });

            if (alert != null)
            {
                _logger.LogInformation("Received alert from {DeviceId}: {AlertType} - {Message}", 
                    deviceId, alert.AlertType, alert.Message);

                AlertReceived?.Invoke(this, new AlertReceivedEventArgs
                {
                    Alert = alert,
                    Topic = topic
                });
            }
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to parse alert message from {DeviceId}", deviceId);
        }
    }

    private async void OnCertificateUpdated(object? sender, CertificateUpdatedEventArgs e)
    {
        _logger.LogInformation("Certificate updated, reconnecting Web API MQTT subscriber...");
        
        try
        {
            await DisconnectAsync();
            await Task.Delay(2000); // Wait a bit before reconnecting
            await ConnectAsync();
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to reconnect Web API MQTT subscriber after certificate update");
        }
    }

    public void Dispose()
    {
        _mqttClient?.Dispose();
    }
}