using Microsoft.Extensions.Logging;

namespace DeviceSimulator.Services;

public class CentrifugeTelemetryGenerator : ITelemetryGenerator
{
    private readonly ILogger<CentrifugeTelemetryGenerator> _logger;
    private readonly Random _random;
    private readonly string _deviceId;
    private readonly DateTime _startTime;
    private int _cycleCount;
    private int _totalCycles;
    private DateTime _lastMaintenanceDate;

    // Simulation parameters for realistic blood separator centrifuge operation
    private const int NormalRpmMin = 3000;
    private const int NormalRpmMax = 4200;
    private const double NormalTempMin = 18.5;
    private const double NormalTempMax = 24.0;
    private const double NormalVibrationMax = 0.3;
    private const int NormalPressureMin = 85;
    private const int NormalPressureMax = 115;

    public CentrifugeTelemetryGenerator(ILogger<CentrifugeTelemetryGenerator> logger)
    {
        _logger = logger;
        _random = new Random();
        _deviceId = Environment.GetEnvironmentVariable("DEVICE_ID") ?? "centrifuge-001";
        _startTime = DateTime.UtcNow;
        _lastMaintenanceDate = DateTime.UtcNow.AddDays(-_random.Next(1, 30));
        _totalCycles = _random.Next(1000, 5000);
        
        _logger.LogInformation("Telemetry generator initialized for device {DeviceId}", _deviceId);
    }

    public object GenerateTelemetry()
    {
        _cycleCount++;
        _totalCycles++;

        // Simulate some operational variance and occasional issues
        var isOperational = _random.NextDouble() > 0.05; // 95% uptime
        var hasMinorIssue = _random.NextDouble() < 0.1; // 10% chance of minor issues

        var rpm = isOperational ? 
            _random.Next(NormalRpmMin, NormalRpmMax) + (hasMinorIssue ? _random.Next(-200, 200) : 0) : 0;

        var temperature = NormalTempMin + (_random.NextDouble() * (NormalTempMax - NormalTempMin));
        if (hasMinorIssue) temperature += _random.NextDouble() * 3; // Slight temperature increase

        var vibration = _random.NextDouble() * NormalVibrationMax;
        if (hasMinorIssue) vibration += _random.NextDouble() * 0.2; // Increased vibration

        var pressure = _random.Next(NormalPressureMin, NormalPressureMax);
        if (hasMinorIssue) pressure += _random.Next(-10, 20);

        // Blood component yields (should add up to ~100% with some variance)
        var plasmaYield = 45 + (_random.NextDouble() * 10); // 45-55%
        var plateletYield = 15 + (_random.NextDouble() * 10); // 15-25%
        var redBloodCellYield = 100 - plasmaYield - plateletYield; // Remainder

        var powerConsumption = isOperational ? 
            2.5 + (_random.NextDouble() * 1.5) + (rpm / 1000.0 * 0.5) : 0.1; // kW

        var status = isOperational ? 
            (hasMinorIssue ? "Warning" : "Running") : "Stopped";

        var telemetry = new CentrifugeTelemetryData
        {
            DeviceId = _deviceId,
            Timestamp = DateTime.UtcNow,
            Rpm = Math.Max(0, rpm),
            Temperature = Math.Round(temperature, 1),
            Vibration = Math.Round(vibration, 3),
            Pressure = Math.Max(0, pressure),
            PlasmaYield = Math.Round(plasmaYield, 1),
            PlateletYield = Math.Round(plateletYield, 1),
            RedBloodCellYield = Math.Round(redBloodCellYield, 1),
            Status = status,
            PowerConsumption = Math.Round(powerConsumption, 2),
            CycleCount = _cycleCount
        };

        _logger.LogDebug("Generated telemetry for cycle {CycleCount}: Status={Status}, RPM={Rpm}, Temp={Temperature}°C", 
            _cycleCount, status, rpm, temperature);

        return telemetry;
    }

    public object GenerateStatusUpdate()
    {
        var uptime = DateTime.UtcNow - _startTime;
        var memoryUsage = 45 + (_random.NextDouble() * 20); // 45-65%
        var cpuUsage = 15 + (_random.NextDouble() * 25); // 15-40%

        var status = new DeviceStatusData
        {
            DeviceId = _deviceId,
            Timestamp = DateTime.UtcNow,
            Status = "Online",
            UptimeHours = Math.Round(uptime.TotalHours, 2),
            SoftwareVersion = "v2.1.3",
            MemoryUsagePercent = Math.Round(memoryUsage, 1),
            CpuUsagePercent = Math.Round(cpuUsage, 1),
            LastMaintenanceDate = _lastMaintenanceDate,
            TotalCycles = _totalCycles
        };

        _logger.LogDebug("Generated status update: Uptime={UptimeHours}h, Memory={MemoryUsage}%, CPU={CpuUsage}%", 
            status.UptimeHours, status.MemoryUsagePercent, status.CpuUsagePercent);

        return status;
    }

    public object? GenerateAlert()
    {
        // Generate alerts based on various conditions (5% chance per call)
        if (_random.NextDouble() > 0.05) return null;

        var alertTypes = new[]
        {
            ("HighVibration", "Warning", "Vibration levels above normal threshold"),
            ("TemperatureAnomaly", "Warning", "Temperature reading outside normal range"),
            ("MaintenanceRequired", "Info", "Scheduled maintenance approaching"),
            ("LowPressure", "Warning", "System pressure below optimal range"),
            ("HighCycleCount", "Info", "High cycle count detected - consider maintenance"),
            ("PowerFluctuation", "Warning", "Power consumption fluctuation detected")
        };

        var (alertType, severity, message) = alertTypes[_random.Next(alertTypes.Length)];

        var alert = new DeviceAlertData
        {
            DeviceId = _deviceId,
            Timestamp = DateTime.UtcNow,
            AlertType = alertType,
            Severity = severity,
            Message = message,
            Parameters = new Dictionary<string, object>
            {
                ["cycleCount"] = _cycleCount,
                ["totalCycles"] = _totalCycles,
                ["uptimeHours"] = Math.Round((DateTime.UtcNow - _startTime).TotalHours, 2)
            }
        };

        _logger.LogInformation("Generated alert: {AlertType} - {Message}", alertType, message);

        return alert;
    }
}