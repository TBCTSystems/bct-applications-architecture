namespace DeviceSimulator.Services;

public interface IMqttService
{
    Task<bool> ConnectAsync();
    Task DisconnectAsync();
    Task PublishTelemetryAsync(object telemetryData);
    Task PublishStatusAsync(object statusData);
    Task PublishAlertAsync(object alertData);
    bool IsConnected { get; }
    event EventHandler<string>? ConnectionStatusChanged;
}