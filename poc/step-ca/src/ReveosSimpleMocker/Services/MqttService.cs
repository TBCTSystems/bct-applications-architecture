using System.Security.Cryptography.X509Certificates;
using System.Text;
using System.Text.Json;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Logging;
using MQTTnet;
using MQTTnet.Client;
using MQTTnet.Extensions.ManagedClient;

namespace ReveosSimpleMocker.Services;

public class MqttService : IMqttService
{
    private readonly ICertificateManager _certificateManager;
    private readonly IConfiguration _configuration;
    private readonly ILogger<MqttService> _logger;
    private IManagedMqttClient? _mqttClient;
    private readonly string _deviceId;
    private readonly string _clientId;

    public bool IsConnected => _mqttClient?.IsConnected ?? false;

    public MqttService(
        ICertificateManager certificateManager,
        IConfiguration configuration,
        ILogger<MqttService> logger)
    {
        _certificateManager = certificateManager;
        _configuration = configuration;
        _logger = logger;
        _deviceId = Environment.GetEnvironmentVariable("Device__Id") ?? "REVEOS-SIM-001";
        _clientId = $"{_deviceId}-{Environment.MachineName}";
    }

    public async Task StartAsync()
    {
        _logger.LogInformation("🦟 Starting MQTT service for device {DeviceId}...", _deviceId);

        try
        {
            var certificate = await _certificateManager.GetCurrentCertificateAsync();
            if (certificate == null)
            {
                throw new InvalidOperationException("No valid certificate available for MQTT connection");
            }

            var factory = new MqttFactory();
            _mqttClient = factory.CreateManagedMqttClient();

            // Configure MQTT client options
            var clientOptions = new MqttClientOptionsBuilder()
                .WithClientId(_clientId)
                .WithTcpServer(_configuration["MQTT:BrokerHost"] ?? "mosquitto", 
                              int.Parse(_configuration["MQTT:BrokerPort"] ?? "8883"))
                .WithTls(new MqttClientOptionsBuilderTlsParameters
                {
                    UseTls = true,
                    Certificates = new List<X509Certificate> { certificate },
                    CertificateValidationHandler = context =>
                    {
                        // For demo purposes, accept all server certificates
                        return true;
                    },
                    IgnoreCertificateChainErrors = true,
                    IgnoreCertificateRevocationErrors = true
                })
                .WithCleanSession(false)
                .Build();

            var managedOptions = new ManagedMqttClientOptionsBuilder()
                .WithClientOptions(clientOptions)
                .WithAutoReconnectDelay(TimeSpan.FromSeconds(5))
                .Build();

            // Set up event handlers
            _mqttClient.ConnectedAsync += OnConnectedAsync;
            _mqttClient.DisconnectedAsync += OnDisconnectedAsync;
            _mqttClient.ApplicationMessageReceivedAsync += OnMessageReceivedAsync;

            // Start the client
            await _mqttClient.StartAsync(managedOptions);

            // Subscribe to device-specific topics
            await SubscribeToTopicsAsync();

            _logger.LogInformation("✅ MQTT service started successfully for device {DeviceId}", _deviceId);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to start MQTT service for device {DeviceId}", _deviceId);
            throw;
        }
    }

    public async Task StopAsync()
    {
        if (_mqttClient != null)
        {
            _logger.LogInformation("🛑 Stopping MQTT service for device {DeviceId}...", _deviceId);
            await _mqttClient.StopAsync();
            _mqttClient.Dispose();
            _mqttClient = null;
        }
    }

    public async Task PublishDeviceDataAsync(object data)
    {
        var topic = $"devices/{_deviceId}/data";
        var message = JsonSerializer.Serialize(data, new JsonSerializerOptions
        {
            PropertyNamingPolicy = JsonNamingPolicy.CamelCase
        });
        
        await PublishMessageAsync(topic, message);
    }

    public async Task PublishStatusAsync(string status)
    {
        var topic = $"devices/{_deviceId}/status";
        var statusData = new
        {
            DeviceId = _deviceId,
            Status = status,
            Timestamp = DateTime.UtcNow
        };
        
        var message = JsonSerializer.Serialize(statusData, new JsonSerializerOptions
        {
            PropertyNamingPolicy = JsonNamingPolicy.CamelCase
        });
        
        await PublishMessageAsync(topic, message);
    }

    private async Task PublishMessageAsync(string topic, string message)
    {
        if (_mqttClient == null || !IsConnected)
        {
            _logger.LogWarning("Cannot publish message - MQTT client not connected");
            return;
        }

        try
        {
            var mqttMessage = new MqttApplicationMessageBuilder()
                .WithTopic(topic)
                .WithPayload(Encoding.UTF8.GetBytes(message))
                .WithQualityOfServiceLevel(MQTTnet.Protocol.MqttQualityOfServiceLevel.AtLeastOnce)
                .WithRetainFlag(false)
                .Build();

            await _mqttClient.EnqueueAsync(mqttMessage);
            _logger.LogDebug("Published message to topic {Topic}", topic);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to publish message to topic {Topic}", topic);
        }
    }

    private async Task SubscribeToTopicsAsync()
    {
        if (_mqttClient == null)
            return;

        var subscriptions = new[]
        {
            $"devices/{_deviceId}/commands/+",
            $"lumia/commands/{_deviceId}",
            "lumia/broadcast/+"
        };

        foreach (var topic in subscriptions)
        {
            await _mqttClient.SubscribeAsync(topic);
            _logger.LogInformation("Subscribed to topic: {Topic}", topic);
        }
    }

    private Task OnConnectedAsync(MqttClientConnectedEventArgs args)
    {
        _logger.LogInformation("🔗 Device {DeviceId} MQTT client connected to broker", _deviceId);
        return Task.CompletedTask;
    }

    private Task OnDisconnectedAsync(MqttClientDisconnectedEventArgs args)
    {
        _logger.LogWarning("🔌 Device {DeviceId} MQTT client disconnected from broker. Reason: {Reason}", 
            _deviceId, args.Reason);
        return Task.CompletedTask;
    }

    private Task OnMessageReceivedAsync(MqttApplicationMessageReceivedEventArgs args)
    {
        try
        {
            var topic = args.ApplicationMessage.Topic;
            var payload = Encoding.UTF8.GetString(args.ApplicationMessage.PayloadSegment);
            
            _logger.LogInformation("📨 Device {DeviceId} received message on topic {Topic}: {Payload}", 
                _deviceId, topic, payload);

            // Handle different message types
            if (topic.Contains("/commands/"))
            {
                HandleCommandMessage(topic, payload);
            }
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error processing received MQTT message");
        }

        return Task.CompletedTask;
    }

    private void HandleCommandMessage(string topic, string payload)
    {
        _logger.LogInformation("🎯 Device {DeviceId} processing command: {Topic} -> {Payload}", 
            _deviceId, topic, payload);
        
        // In a real device, this would execute actual commands
        // For demo purposes, just acknowledge the command
        _ = Task.Run(async () =>
        {
            await Task.Delay(1000); // Simulate command processing time
            await PublishStatusAsync($"command_executed_{DateTime.UtcNow:HHmmss}");
        });
    }
}