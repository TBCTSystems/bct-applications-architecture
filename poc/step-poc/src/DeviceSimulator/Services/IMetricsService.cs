using Prometheus;

namespace DeviceSimulator.Services;

public interface IMetricsService
{
    void IncrementTelemetryMessagesSent();
    void IncrementStatusMessagesSent();
    void IncrementAlertMessagesSent();
    void IncrementConnectionAttempts();
    void IncrementConnectionFailures();
    void SetConnectionStatus(bool isConnected);
    void RecordTelemetryGenerationTime(double milliseconds);
    void RecordMqttPublishTime(double milliseconds);
    void SetLastMessageTimestamp();
}

public class MetricsService : IMetricsService
{
    private readonly Counter _telemetryMessagesSent = Metrics
        .CreateCounter("device_telemetry_messages_sent_total", "Total number of telemetry messages sent");
    
    private readonly Counter _statusMessagesSent = Metrics
        .CreateCounter("device_status_messages_sent_total", "Total number of status messages sent");
    
    private readonly Counter _alertMessagesSent = Metrics
        .CreateCounter("device_alert_messages_sent_total", "Total number of alert messages sent");
    
    private readonly Counter _connectionAttempts = Metrics
        .CreateCounter("device_mqtt_connection_attempts_total", "Total number of MQTT connection attempts");
    
    private readonly Counter _connectionFailures = Metrics
        .CreateCounter("device_mqtt_connection_failures_total", "Total number of MQTT connection failures");
    
    private readonly Gauge _connectionStatus = Metrics
        .CreateGauge("device_mqtt_connection_status", "Current MQTT connection status (1 = connected, 0 = disconnected)");
    
    private readonly Histogram _telemetryGenerationTime = Metrics
        .CreateHistogram("device_telemetry_generation_duration_milliseconds", "Time taken to generate telemetry data");
    
    private readonly Histogram _mqttPublishTime = Metrics
        .CreateHistogram("device_mqtt_publish_duration_milliseconds", "Time taken to publish MQTT messages");
    
    private readonly Gauge _lastMessageTimestamp = Metrics
        .CreateGauge("device_last_message_timestamp_seconds", "Unix timestamp of the last message sent");

    public void IncrementTelemetryMessagesSent() => _telemetryMessagesSent.Inc();
    
    public void IncrementStatusMessagesSent() => _statusMessagesSent.Inc();
    
    public void IncrementAlertMessagesSent() => _alertMessagesSent.Inc();
    
    public void IncrementConnectionAttempts() => _connectionAttempts.Inc();
    
    public void IncrementConnectionFailures() => _connectionFailures.Inc();
    
    public void SetConnectionStatus(bool isConnected) => _connectionStatus.Set(isConnected ? 1 : 0);
    
    public void RecordTelemetryGenerationTime(double milliseconds) => _telemetryGenerationTime.Observe(milliseconds);
    
    public void RecordMqttPublishTime(double milliseconds) => _mqttPublishTime.Observe(milliseconds);
    
    public void SetLastMessageTimestamp() => _lastMessageTimestamp.SetToCurrentTimeUtc();
}