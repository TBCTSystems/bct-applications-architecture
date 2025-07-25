namespace DeviceSimulator.Services;

public interface ITelemetryGenerator
{
    object GenerateTelemetry();
    object GenerateStatusUpdate();
    object? GenerateAlert(); // Returns null if no alert needed
}

public class CentrifugeTelemetryData
{
    public string DeviceId { get; set; } = string.Empty;
    public DateTime Timestamp { get; set; }
    public int Rpm { get; set; }
    public double Temperature { get; set; }
    public double Vibration { get; set; }
    public int Pressure { get; set; }
    public double PlasmaYield { get; set; }
    public double PlateletYield { get; set; }
    public double RedBloodCellYield { get; set; }
    public string Status { get; set; } = string.Empty;
    public double PowerConsumption { get; set; }
    public int CycleCount { get; set; }
}

public class DeviceStatusData
{
    public string DeviceId { get; set; } = string.Empty;
    public DateTime Timestamp { get; set; }
    public string Status { get; set; } = string.Empty;
    public double UptimeHours { get; set; }
    public string SoftwareVersion { get; set; } = string.Empty;
    public double MemoryUsagePercent { get; set; }
    public double CpuUsagePercent { get; set; }
    public DateTime LastMaintenanceDate { get; set; }
    public int TotalCycles { get; set; }
}

public class DeviceAlertData
{
    public string DeviceId { get; set; } = string.Empty;
    public DateTime Timestamp { get; set; }
    public string AlertType { get; set; } = string.Empty;
    public string Severity { get; set; } = string.Empty;
    public string Message { get; set; } = string.Empty;
    public Dictionary<string, object> Parameters { get; set; } = new();
}