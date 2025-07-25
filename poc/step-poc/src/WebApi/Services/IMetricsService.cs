namespace WebApi.Services;

public interface IMetricsService
{
    // MQTT connection metrics
    void IncrementMqttConnectionAttempts();
    void IncrementMqttConnectionFailures();
    void SetMqttConnectionStatus(bool connected);
    bool IsMqttConnected();

    // Message processing metrics
    void IncrementTelemetryMessagesReceived();
    void IncrementStatusMessagesReceived();
    void IncrementAlertMessagesReceived();
    long GetTotalMessagesReceived();

    // SignalR connection metrics
    void IncrementSignalRConnections();
    void DecrementSignalRConnections();
    int GetActiveSignalRConnections();

    // Performance metrics
    void RecordMessageProcessingTime(double milliseconds);
    void RecordSignalRBroadcastTime(double milliseconds);

    // API metrics
    void IncrementApiRequests(string endpoint);
    void RecordApiResponseTime(string endpoint, double milliseconds);
}