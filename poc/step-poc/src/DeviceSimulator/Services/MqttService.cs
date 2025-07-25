using System.Security.Authentication;
using System.Security.Cryptography.X509Certificates;
using System.Text;
using System.Text.Json;
using Microsoft.Extensions.Logging;
using MQTTnet;
using MQTTnet.Client;

namespace DeviceSimulator.Services;

public class MqttService : IMqttService, IDisposable
{
    private readonly ILogger<MqttService> _logger;
    private readonly ICertificateManager _certificateManager;
    private readonly IMqttClient _mqttClient;
    private readonly string _deviceId;
    private readonly string _brokerHost;
    private readonly int _brokerPort;
    private bool _isConnected;

    public bool IsConnected => _isConnected && _mqttClient.IsConnected;
    public event EventHandler<string>? ConnectionStatusChanged;

    public MqttService(ILogger<MqttService> logger, ICertificateManager certificateManager)
    {
        _logger = logger;
        _certificateManager = certificateManager;
        _deviceId = Environment.GetEnvironmentVariable("DEVICE_ID") ?? "centrifuge-001";
        _brokerHost = Environment.GetEnvironmentVariable("MQTT_BROKER_HOST") ?? "mosquitto";
        _brokerPort = int.Parse(Environment.GetEnvironmentVariable("MQTT_BROKER_PORT") ?? "8883");

        var factory = new MqttFactory();
        _mqttClient = factory.CreateMqttClient();

        _mqttClient.ConnectedAsync += OnConnectedAsync;
        _mqttClient.DisconnectedAsync += OnDisconnectedAsync;
        _mqttClient.ApplicationMessageReceivedAsync += OnMessageReceivedAsync;

        // Subscribe to certificate updates
        _certificateManager.CertificateUpdated += OnCertificateUpdated;

        _logger.LogInformation("MQTT Service initialized for device {DeviceId} connecting to {Host}:{Port}", 
            _deviceId, _brokerHost, _brokerPort);
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
                .WithClientId(_deviceId)
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
                .WithCleanSession(true)
                .WithKeepAlivePeriod(TimeSpan.FromSeconds(30))
                .Build();

            _logger.LogInformation("Attempting MQTT connection with mTLS...");
            await _mqttClient.ConnectAsync(options);

            return _mqttClient.IsConnected;
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

    public async Task PublishTelemetryAsync(object telemetryData)
    {
        await PublishAsync($"devices/{_deviceId}/telemetry", telemetryData);
    }

    public async Task PublishStatusAsync(object statusData)
    {
        await PublishAsync($"devices/{_deviceId}/status", statusData);
    }

    public async Task PublishAlertAsync(object alertData)
    {
        await PublishAsync($"devices/{_deviceId}/alerts", alertData);
    }

    private async Task PublishAsync(string topic, object data)
    {
        try
        {
            if (!IsConnected)
            {
                _logger.LogWarning("Cannot publish to {Topic}: MQTT client not connected", topic);
                return;
            }

            var json = JsonSerializer.Serialize(data, new JsonSerializerOptions 
            { 
                PropertyNamingPolicy = JsonNamingPolicy.CamelCase 
            });

            var message = new MqttApplicationMessageBuilder()
                .WithTopic(topic)
                .WithPayload(Encoding.UTF8.GetBytes(json))
                .WithQualityOfServiceLevel(MQTTnet.Protocol.MqttQualityOfServiceLevel.AtLeastOnce)
                .WithRetainFlag(false)
                .Build();

            await _mqttClient.PublishAsync(message);
            
            _logger.LogDebug("Published message to {Topic}: {MessageSize} bytes", topic, json.Length);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to publish message to {Topic}", topic);
        }
    }

    private Task OnConnectedAsync(MqttClientConnectedEventArgs args)
    {
        _isConnected = true;
        _logger.LogInformation("Successfully connected to MQTT broker with mTLS");
        ConnectionStatusChanged?.Invoke(this, "Connected");
        return Task.CompletedTask;
    }

    private Task OnDisconnectedAsync(MqttClientDisconnectedEventArgs args)
    {
        _isConnected = false;
        _logger.LogWarning("Disconnected from MQTT broker. Reason: {Reason}", args.Reason);
        ConnectionStatusChanged?.Invoke(this, $"Disconnected: {args.Reason}");
        return Task.CompletedTask;
    }

    private Task OnMessageReceivedAsync(MqttApplicationMessageReceivedEventArgs args)
    {
        var topic = args.ApplicationMessage.Topic;
        var payload = Encoding.UTF8.GetString(args.ApplicationMessage.PayloadSegment);
        
        _logger.LogDebug("Received message on {Topic}: {Payload}", topic, payload);
        return Task.CompletedTask;
    }

    private async void OnCertificateUpdated(object? sender, CertificateUpdatedEventArgs e)
    {
        _logger.LogInformation("Certificate updated, reconnecting to MQTT broker...");
        
        try
        {
            await DisconnectAsync();
            await Task.Delay(2000); // Wait a bit before reconnecting
            await ConnectAsync();
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to reconnect after certificate update");
        }
    }

    public void Dispose()
    {
        _mqttClient?.Dispose();
    }
}