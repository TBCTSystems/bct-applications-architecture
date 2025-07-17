using System.Collections.Concurrent;
using DemoWeb.Models;

namespace DemoWeb.Services;

public class MqttMonitorService : IMqttMonitorService
{
    private readonly ConcurrentQueue<MqttMessage> _recentMessages = new();
    private readonly ILogger<MqttMonitorService> _logger;
    private const int MaxMessages = 100;

    public MqttMonitorService(ILogger<MqttMonitorService> logger)
    {
        _logger = logger;
        
        // Add some sample messages for demo
        AddSampleMessages();
    }

    public List<MqttMessage> GetRecentMessages()
    {
        return _recentMessages.ToList().OrderByDescending(m => m.Timestamp).Take(50).ToList();
    }

    public void AddMessage(MqttMessage message)
    {
        _recentMessages.Enqueue(message);
        
        // Keep only the most recent messages
        while (_recentMessages.Count > MaxMessages)
        {
            _recentMessages.TryDequeue(out _);
        }
        
        _logger.LogDebug("Added MQTT message: {Topic}", message.Topic);
    }

    public Task StartMonitoringAsync()
    {
        _logger.LogInformation("MQTT monitoring started");
        return Task.CompletedTask;
    }

    public Task StopMonitoringAsync()
    {
        _logger.LogInformation("MQTT monitoring stopped");
        return Task.CompletedTask;
    }

    private void AddSampleMessages()
    {
        var sampleMessages = new[]
        {
            new MqttMessage
            {
                Topic = "devices/REVEOS-SIM-001/data",
                Payload = """{"deviceId":"REVEOS-SIM-001","temperature":23.5,"pressure":1013.2,"timestamp":"2024-01-15T10:30:00Z"}""",
                Timestamp = DateTime.UtcNow.AddMinutes(-2),
                ClientId = "REVEOS-SIM-001"
            },
            new MqttMessage
            {
                Topic = "devices/REVEOS-SIM-001/status",
                Payload = """{"deviceId":"REVEOS-SIM-001","status":"operational","timestamp":"2024-01-15T10:29:00Z"}""",
                Timestamp = DateTime.UtcNow.AddMinutes(-3),
                ClientId = "REVEOS-SIM-001"
            },
            new MqttMessage
            {
                Topic = "lumia/heartbeat",
                Payload = """{"clientId":"lumia-app","status":"healthy","timestamp":"2024-01-15T10:28:00Z"}""",
                Timestamp = DateTime.UtcNow.AddMinutes(-4),
                ClientId = "lumia-app"
            }
        };

        foreach (var message in sampleMessages)
        {
            _recentMessages.Enqueue(message);
        }
    }
}