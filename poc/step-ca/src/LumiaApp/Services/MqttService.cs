using System.Security.Cryptography.X509Certificates;
using System.Text;
using System.Text.Json;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Logging;
using MQTTnet;
using MQTTnet.Client;
using MQTTnet.Extensions.ManagedClient;

namespace LumiaApp.Services;

public class MqttService : IMqttService
{
    private readonly ICertificateManager _certificateManager;
    private readonly IConfiguration _configuration;
    private readonly ILogger<MqttService> _logger;
    private IManagedMqttClient? _mqttClient;
    private readonly string _clientId = "lumia-app-" + Environment.MachineName;

    public bool IsConnected => _mqttClient?.IsConnected ?? false;

    public MqttService(
        ICertificateManager certificateManager,
        IConfiguration configuration,
        ILogger<MqttService> logger)
    {
        _certificateManager = certificateManager;
        _configuration = configuration;
        _logger = logger;
    }

    public async Task StartAsync()
    {
        _logger.LogInformation("🦟 Starting MQTT service...");

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
                        // In production, validate against step-ca root certificate
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

            // Subscribe to topics
            await SubscribeToTopicsAsync();

            _logger.LogInformation("✅ MQTT service started successfully");
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to start MQTT service");
            throw;
        }
    }

    public async Task StopAsync()
    {
        if (_mqttClient != null)
        {
            _logger.LogInformation("🛑 Stopping MQTT service...");
            await _mqttClient.StopAsync();
            _mqttClient.Dispose();
            _mqttClient = null;
        }
    }

    public async Task PublishHeartbeatAsync()
    {
        if (!IsConnected)
        {
            _logger.LogWarning("Cannot publish heartbeat - MQTT client not connected");
            return;
        }

        var heartbeat = new
        {
            ClientId = _clientId,
            Timestamp = DateTime.UtcNow,
            Status = "healthy",
            CertificateExpiry = (await _certificateManager.GetCurrentCertificateAsync())?.NotAfter
        };

        await PublishMessageAsync("lumia/heartbeat", JsonSerializer.Serialize(heartbeat));
    }

    public async Task PublishMessageAsync(string topic, string message)
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
            "lumia/commands/+",
            "devices/+/status",
            "devices/+/data"
        };

        foreach (var topic in subscriptions)
        {
            await _mqttClient.SubscribeAsync(topic);
            _logger.LogInformation("Subscribed to topic: {Topic}", topic);
        }
    }

    private Task OnConnectedAsync(MqttClientConnectedEventArgs args)
    {
        _logger.LogInformation("🔗 MQTT client connected to broker");
        return Task.CompletedTask;
    }

    private Task OnDisconnectedAsync(MqttClientDisconnectedEventArgs args)
    {
        _logger.LogWarning("🔌 MQTT client disconnected from broker. Reason: {Reason}", args.Reason);
        return Task.CompletedTask;
    }

    private Task OnMessageReceivedAsync(MqttApplicationMessageReceivedEventArgs args)
    {
        try
        {
            var topic = args.ApplicationMessage.Topic;
            var payload = Encoding.UTF8.GetString(args.ApplicationMessage.PayloadSegment);
            
            _logger.LogInformation("📨 Received message on topic {Topic}: {Payload}", topic, payload);

            // Handle different message types
            if (topic.StartsWith("lumia/commands/"))
            {
                HandleCommandMessage(topic, payload);
            }
            else if (topic.StartsWith("devices/"))
            {
                HandleDeviceMessage(topic, payload);
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
        _logger.LogInformation("Processing command: {Topic} -> {Payload}", topic, payload);
        
        // In a real application, this would handle various commands
        // For demo purposes, just log the command
    }

    private void HandleDeviceMessage(string topic, string payload)
    {
        _logger.LogInformation("Processing device message: {Topic} -> {Payload}", topic, payload);
        
        // In a real application, this would process device data
        // For demo purposes, just log the message
    }
}