using Microsoft.Extensions.Logging;

namespace DeviceSimulator.Services;

public interface IHealthService
{
    HealthStatus GetHealthStatus();
}

public class HealthStatus
{
    public string Status { get; set; } = "Unknown";
    public string DeviceId { get; set; } = "";
    public bool MqttConnected { get; set; }
    public bool CertificatesValid { get; set; }
    public DateTime LastTelemetryTime { get; set; }
    public DateTime LastStatusTime { get; set; }
    public int TotalTelemetryMessages { get; set; }
    public int TotalStatusMessages { get; set; }
    public int TotalAlertMessages { get; set; }
    public int ConnectionAttempts { get; set; }
    public TimeSpan Uptime { get; set; }
    public Dictionary<string, object> AdditionalInfo { get; set; } = new();
}

public class HealthService : IHealthService
{
    private readonly IMqttService _mqttService;
    private readonly ICertificateManager _certificateManager;
    private readonly ILogger<HealthService> _logger;
    private readonly DateTime _startTime;
    private readonly string _deviceId;
    
    private DateTime _lastTelemetryTime = DateTime.MinValue;
    private DateTime _lastStatusTime = DateTime.MinValue;
    private int _totalTelemetryMessages = 0;
    private int _totalStatusMessages = 0;
    private int _totalAlertMessages = 0;
    private int _connectionAttempts = 0;

    public HealthService(
        IMqttService mqttService,
        ICertificateManager certificateManager,
        ILogger<HealthService> logger)
    {
        _mqttService = mqttService;
        _certificateManager = certificateManager;
        _logger = logger;
        _startTime = DateTime.UtcNow;
        _deviceId = Environment.GetEnvironmentVariable("DEVICE_ID") ?? "centrifuge-001";
    }

    public HealthStatus GetHealthStatus()
    {
        var mqttConnected = _mqttService.IsConnected;
        var certificatesValid = CheckCertificatesValid();
        
        var status = DetermineOverallStatus(mqttConnected, certificatesValid);
        
        return new HealthStatus
        {
            Status = status,
            DeviceId = _deviceId,
            MqttConnected = mqttConnected,
            CertificatesValid = certificatesValid,
            LastTelemetryTime = _lastTelemetryTime,
            LastStatusTime = _lastStatusTime,
            TotalTelemetryMessages = _totalTelemetryMessages,
            TotalStatusMessages = _totalStatusMessages,
            TotalAlertMessages = _totalAlertMessages,
            ConnectionAttempts = _connectionAttempts,
            Uptime = DateTime.UtcNow - _startTime,
            AdditionalInfo = new Dictionary<string, object>
            {
                ["mqtt_broker"] = Environment.GetEnvironmentVariable("MQTT_BROKER_HOST") ?? "mosquitto",
                ["mqtt_port"] = Environment.GetEnvironmentVariable("MQTT_BROKER_PORT") ?? "8883",
                ["telemetry_interval_seconds"] = Environment.GetEnvironmentVariable("TELEMETRY_INTERVAL_SECONDS") ?? "10",
                ["status_interval_minutes"] = Environment.GetEnvironmentVariable("STATUS_INTERVAL_MINUTES") ?? "1"
            }
        };
    }

    private bool CheckCertificatesValid()
    {
        try
        {
            var clientCert = _certificateManager.GetClientCertificateAsync().Result;
            var caCert = _certificateManager.GetCaCertificateAsync().Result;
            return clientCert != null && caCert != null;
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "Failed to check certificate validity");
            return false;
        }
    }

    private string DetermineOverallStatus(bool mqttConnected, bool certificatesValid)
    {
        if (!certificatesValid)
            return "Unhealthy - Invalid Certificates";
        
        if (!mqttConnected)
            return "Degraded - MQTT Disconnected";
        
        var timeSinceLastTelemetry = DateTime.UtcNow - _lastTelemetryTime;
        if (_lastTelemetryTime != DateTime.MinValue && timeSinceLastTelemetry > TimeSpan.FromMinutes(2))
            return "Degraded - No Recent Telemetry";
        
        return "Healthy";
    }

    // Methods to update internal counters (called by DeviceSimulatorService)
    public void RecordTelemetryMessage()
    {
        _totalTelemetryMessages++;
        _lastTelemetryTime = DateTime.UtcNow;
    }

    public void RecordStatusMessage()
    {
        _totalStatusMessages++;
        _lastStatusTime = DateTime.UtcNow;
    }

    public void RecordAlertMessage()
    {
        _totalAlertMessages++;
    }

    public void RecordConnectionAttempt()
    {
        _connectionAttempts++;
    }
}