using System.Text.Json;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Logging;

namespace ReveosSimpleMocker.Services;

public class DeviceSimulator : IDeviceSimulator
{
    private readonly IMqttService _mqttService;
    private readonly IConfiguration _configuration;
    private readonly ILogger<DeviceSimulator> _logger;
    private readonly string _deviceId;
    private readonly Random _random = new();
    private bool _isRunning = false;

    public DeviceSimulator(
        IMqttService mqttService,
        IConfiguration configuration,
        ILogger<DeviceSimulator> logger)
    {
        _mqttService = mqttService;
        _configuration = configuration;
        _logger = logger;
        _deviceId = Environment.GetEnvironmentVariable("Device__Id") ?? "REVEOS-SIM-001";
    }

    public Task StartAsync()
    {
        _logger.LogInformation("🎭 Starting device simulation for {DeviceId}", _deviceId);
        _isRunning = true;
        return Task.CompletedTask;
    }

    public Task StopAsync()
    {
        _logger.LogInformation("🛑 Stopping device simulation for {DeviceId}", _deviceId);
        _isRunning = false;
        return Task.CompletedTask;
    }

    public async Task SimulateDeviceOperationsAsync()
    {
        if (!_isRunning || !_mqttService.IsConnected)
            return;

        try
        {
            // Simulate different types of device operations
            await SimulateDataCollection();
            await SimulateStatusUpdate();
            
            // Occasionally simulate alerts or events
            if (_random.NextDouble() < 0.1) // 10% chance
            {
                await SimulateDeviceEvent();
            }
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error during device simulation");
        }
    }

    private async Task SimulateDataCollection()
    {
        var deviceData = new DeviceData
        {
            DeviceId = _deviceId,
            Timestamp = DateTime.UtcNow,
            Status = "operational",
            FirmwareVersion = "2.1.0",
            Measurements = GenerateSimulatedMeasurements()
        };

        await _mqttService.PublishDeviceDataAsync(deviceData);
        _logger.LogDebug("📊 Published device data for {DeviceId}", _deviceId);
    }

    private async Task SimulateStatusUpdate()
    {
        var statuses = new[] { "operational", "processing", "idle", "maintenance" };
        var status = statuses[_random.Next(statuses.Length)];
        
        await _mqttService.PublishStatusAsync(status);
        _logger.LogDebug("📡 Published status update: {Status}", status);
    }

    private async Task SimulateDeviceEvent()
    {
        var events = new[]
        {
            "calibration_completed",
            "maintenance_required",
            "temperature_warning",
            "cycle_completed",
            "error_cleared"
        };

        var eventType = events[_random.Next(events.Length)];
        var eventData = new
        {
            DeviceId = _deviceId,
            EventType = eventType,
            Timestamp = DateTime.UtcNow,
            Severity = _random.Next(1, 4), // 1=Info, 2=Warning, 3=Error
            Description = $"Simulated {eventType} event"
        };

        var topic = $"devices/{_deviceId}/events";
        await _mqttService.PublishDeviceDataAsync(eventData);
        
        _logger.LogInformation("🚨 Published device event: {EventType}", eventType);
    }

    private Dictionary<string, object> GenerateSimulatedMeasurements()
    {
        return new Dictionary<string, object>
        {
            ["temperature"] = Math.Round(20 + _random.NextDouble() * 15, 2), // 20-35°C
            ["pressure"] = Math.Round(1000 + _random.NextDouble() * 100, 2), // 1000-1100 hPa
            ["humidity"] = Math.Round(30 + _random.NextDouble() * 40, 2), // 30-70%
            ["vibration"] = Math.Round(_random.NextDouble() * 5, 3), // 0-5 units
            ["cycle_count"] = _random.Next(1000, 10000),
            ["uptime_hours"] = Math.Round(_random.NextDouble() * 8760, 1), // Up to 1 year
            ["error_count"] = _random.Next(0, 5),
            ["last_calibration"] = DateTime.UtcNow.AddDays(-_random.Next(1, 30)).ToString("yyyy-MM-dd")
        };
    }
}