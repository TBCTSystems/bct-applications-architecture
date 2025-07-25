using WebApi.Models;

namespace WebApi.Services;

public interface IMqttSubscriberService
{
    Task<bool> ConnectAsync();
    Task DisconnectAsync();
    bool IsConnected { get; }
    
    event EventHandler<TelemetryReceivedEventArgs>? TelemetryReceived;
    event EventHandler<StatusReceivedEventArgs>? StatusReceived;
    event EventHandler<AlertReceivedEventArgs>? AlertReceived;
    event EventHandler<string>? ConnectionStatusChanged;
}

public class TelemetryReceivedEventArgs : EventArgs
{
    public CentrifugeTelemetryData Telemetry { get; set; } = null!;
    public string Topic { get; set; } = string.Empty;
    public DateTime ReceivedAt { get; set; } = DateTime.UtcNow;
}

public class StatusReceivedEventArgs : EventArgs
{
    public DeviceStatusData Status { get; set; } = null!;
    public string Topic { get; set; } = string.Empty;
    public DateTime ReceivedAt { get; set; } = DateTime.UtcNow;
}

public class AlertReceivedEventArgs : EventArgs
{
    public DeviceAlertData Alert { get; set; } = null!;
    public string Topic { get; set; } = string.Empty;
    public DateTime ReceivedAt { get; set; } = DateTime.UtcNow;
}