using System.Collections.Concurrent;
using Prometheus;

namespace WebApi.Services;

public class MetricsService : IMetricsService
{
    // Prometheus metrics
    private readonly Counter _mqttConnectionAttempts = Metrics
        .CreateCounter("webapi_mqtt_connection_attempts_total", "Total MQTT connection attempts");
    
    private readonly Counter _mqttConnectionFailures = Metrics
        .CreateCounter("webapi_mqtt_connection_failures_total", "Total MQTT connection failures");
    
    private readonly Gauge _mqttConnectionStatus = Metrics
        .CreateGauge("webapi_mqtt_connection_status", "MQTT connection status (1=connected, 0=disconnected)");
    
    private readonly Counter _telemetryMessagesReceived = Metrics
        .CreateCounter("webapi_telemetry_messages_received_total", "Total telemetry messages received");
    
    private readonly Counter _statusMessagesReceived = Metrics
        .CreateCounter("webapi_status_messages_received_total", "Total status messages received");
    
    private readonly Counter _alertMessagesReceived = Metrics
        .CreateCounter("webapi_alert_messages_received_total", "Total alert messages received");
    
    private readonly Gauge _activeSignalRConnections = Metrics
        .CreateGauge("webapi_signalr_active_connections", "Number of active SignalR connections");
    
    private readonly Histogram _messageProcessingTime = Metrics
        .CreateHistogram("webapi_message_processing_duration_ms", "Time spent processing MQTT messages");
    
    private readonly Histogram _signalRBroadcastTime = Metrics
        .CreateHistogram("webapi_signalr_broadcast_duration_ms", "Time spent broadcasting via SignalR");
    
    private readonly Counter _apiRequests = Metrics
        .CreateCounter("webapi_api_requests_total", "Total API requests", new[] { "endpoint" });
    
    private readonly Histogram _apiResponseTime = Metrics
        .CreateHistogram("webapi_api_response_duration_ms", "API response time", new[] { "endpoint" });

    // Internal state
    private volatile bool _mqttConnected = false;
    private volatile int _signalRConnections = 0;

    public void IncrementMqttConnectionAttempts()
    {
        _mqttConnectionAttempts.Inc();
    }

    public void IncrementMqttConnectionFailures()
    {
        _mqttConnectionFailures.Inc();
    }

    public void SetMqttConnectionStatus(bool connected)
    {
        _mqttConnected = connected;
        _mqttConnectionStatus.Set(connected ? 1 : 0);
    }

    public bool IsMqttConnected()
    {
        return _mqttConnected;
    }

    public void IncrementTelemetryMessagesReceived()
    {
        _telemetryMessagesReceived.Inc();
    }

    public void IncrementStatusMessagesReceived()
    {
        _statusMessagesReceived.Inc();
    }

    public void IncrementAlertMessagesReceived()
    {
        _alertMessagesReceived.Inc();
    }

    public long GetTotalMessagesReceived()
    {
        return (long)(_telemetryMessagesReceived.Value + _statusMessagesReceived.Value + _alertMessagesReceived.Value);
    }

    public void IncrementSignalRConnections()
    {
        Interlocked.Increment(ref _signalRConnections);
        _activeSignalRConnections.Set(_signalRConnections);
    }

    public void DecrementSignalRConnections()
    {
        Interlocked.Decrement(ref _signalRConnections);
        _activeSignalRConnections.Set(_signalRConnections);
    }

    public int GetActiveSignalRConnections()
    {
        return _signalRConnections;
    }

    public void RecordMessageProcessingTime(double milliseconds)
    {
        _messageProcessingTime.Observe(milliseconds);
    }

    public void RecordSignalRBroadcastTime(double milliseconds)
    {
        _signalRBroadcastTime.Observe(milliseconds);
    }

    public void IncrementApiRequests(string endpoint)
    {
        _apiRequests.WithLabels(endpoint).Inc();
    }

    public void RecordApiResponseTime(string endpoint, double milliseconds)
    {
        _apiResponseTime.WithLabels(endpoint).Observe(milliseconds);
    }
}