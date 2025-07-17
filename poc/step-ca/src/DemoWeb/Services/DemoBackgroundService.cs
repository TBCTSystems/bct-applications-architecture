using DemoWeb.Models;

namespace DemoWeb.Services;

public class DemoBackgroundService : BackgroundService
{
    private readonly IMqttMonitorService _mqttMonitor;
    private readonly ILogger<DemoBackgroundService> _logger;
    private readonly Random _random = new();

    public DemoBackgroundService(IMqttMonitorService mqttMonitor, ILogger<DemoBackgroundService> logger)
    {
        _mqttMonitor = mqttMonitor;
        _logger = logger;
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        _logger.LogInformation("🎭 Demo background service started");

        await _mqttMonitor.StartMonitoringAsync();

        while (!stoppingToken.IsCancellationRequested)
        {
            try
            {
                // Simulate incoming MQTT messages for demo purposes
                await SimulateMqttTraffic();
                
                await Task.Delay(TimeSpan.FromSeconds(15), stoppingToken);
            }
            catch (OperationCanceledException)
            {
                break;
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error in demo background service");
                await Task.Delay(TimeSpan.FromSeconds(5), stoppingToken);
            }
        }

        await _mqttMonitor.StopMonitoringAsync();
        _logger.LogInformation("🛑 Demo background service stopped");
    }

    private async Task SimulateMqttTraffic()
    {
        var messageTypes = new[]
        {
            ("devices/REVEOS-SIM-001/data", GenerateDeviceData),
            ("devices/REVEOS-SIM-001/status", GenerateStatusUpdate),
            ("lumia/heartbeat", GenerateHeartbeat)
        };

        var (topic, generator) = messageTypes[_random.Next(messageTypes.Length)];
        var payload = generator();
        
        var message = new MqttMessage
        {
            Topic = topic,
            Payload = payload,
            Timestamp = DateTime.UtcNow,
            ClientId = topic.Contains("lumia") ? "lumia-app" : "REVEOS-SIM-001"
        };

        _mqttMonitor.AddMessage(message);
    }

    private string GenerateDeviceData()
    {
        var data = new
        {
            deviceId = "REVEOS-SIM-001",
            timestamp = DateTime.UtcNow,
            measurements = new
            {
                temperature = Math.Round(20 + _random.NextDouble() * 15, 2),
                pressure = Math.Round(1000 + _random.NextDouble() * 100, 2),
                humidity = Math.Round(30 + _random.NextDouble() * 40, 2),
                cycle_count = _random.Next(1000, 10000)
            }
        };

        return System.Text.Json.JsonSerializer.Serialize(data);
    }

    private string GenerateStatusUpdate()
    {
        var statuses = new[] { "operational", "processing", "idle", "maintenance" };
        var data = new
        {
            deviceId = "REVEOS-SIM-001",
            status = statuses[_random.Next(statuses.Length)],
            timestamp = DateTime.UtcNow
        };

        return System.Text.Json.JsonSerializer.Serialize(data);
    }

    private string GenerateHeartbeat()
    {
        var data = new
        {
            clientId = "lumia-app",
            status = "healthy",
            timestamp = DateTime.UtcNow,
            certificateExpiry = DateTime.UtcNow.AddDays(29)
        };

        return System.Text.Json.JsonSerializer.Serialize(data);
    }
}