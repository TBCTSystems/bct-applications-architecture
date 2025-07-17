namespace DemoWeb.Models;

public class SystemStatus
{
    public string OverallStatus { get; set; } = string.Empty;
    public DateTime LastUpdated { get; set; }
    public ServiceStatus StepCA { get; set; } = new();
    public ServiceStatus ProvisioningService { get; set; } = new();
    public ServiceStatus MqttBroker { get; set; } = new();
    public ServiceStatus LumiaApp { get; set; } = new();
    public List<DeviceStatus> Devices { get; set; } = new();
}

public class ServiceStatus
{
    public string Name { get; set; } = string.Empty;
    public string Status { get; set; } = string.Empty;
    public string Url { get; set; } = string.Empty;
    public DateTime LastCheck { get; set; }
    public string? ErrorMessage { get; set; }
    public Dictionary<string, object> Metrics { get; set; } = new();
}

public class DeviceStatus
{
    public string DeviceId { get; set; } = string.Empty;
    public string Status { get; set; } = string.Empty;
    public DateTime LastSeen { get; set; }
    public bool CertificateValid { get; set; }
    public DateTime? CertificateExpiry { get; set; }
    public bool MqttConnected { get; set; }
    public Dictionary<string, object> LastData { get; set; } = new();
}

public class MqttMessage
{
    public string Topic { get; set; } = string.Empty;
    public string Payload { get; set; } = string.Empty;
    public DateTime Timestamp { get; set; }
    public string ClientId { get; set; } = string.Empty;
}

public class CertificateInfo
{
    public string Subject { get; set; } = string.Empty;
    public string Issuer { get; set; } = string.Empty;
    public DateTime NotBefore { get; set; }
    public DateTime NotAfter { get; set; }
    public string SerialNumber { get; set; } = string.Empty;
    public bool IsValid { get; set; }
    public TimeSpan? TimeUntilExpiry { get; set; }
    public string Owner { get; set; } = string.Empty;
}

public class WhitelistRequest
{
    public string IpAddress { get; set; } = string.Empty;
}

public class DeviceEventRequest
{
    public string DeviceId { get; set; } = string.Empty;
    public string EventType { get; set; } = string.Empty;
    public Dictionary<string, object> Data { get; set; } = new();
}