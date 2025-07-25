using WebApi.Models;

namespace WebApi.Services;

public interface ITelemetryDataService
{
    // Store incoming data
    void StoreTelemetry(CentrifugeTelemetryData telemetry);
    void StoreStatus(DeviceStatusData status);
    void StoreAlert(DeviceAlertData alert);

    // Retrieve current data
    DeviceSummary? GetDeviceSummary(string deviceId);
    List<DeviceSummary> GetAllDeviceSummaries();
    
    // Retrieve historical data
    List<CentrifugeTelemetryData> GetTelemetryHistory(string deviceId, TelemetryHistoryRequest request);
    List<DeviceStatusData> GetStatusHistory(string deviceId, TelemetryHistoryRequest request);
    List<DeviceAlertData> GetAlertHistory(string deviceId, TelemetryHistoryRequest request);
    
    // Real-time data access
    CentrifugeTelemetryData? GetLatestTelemetry(string deviceId);
    DeviceStatusData? GetLatestStatus(string deviceId);
    List<DeviceAlertData> GetRecentAlerts(string deviceId, int count = 10);
    
    // Device management
    List<string> GetKnownDeviceIds();
    bool IsDeviceConnected(string deviceId);
    DateTime? GetLastSeenTime(string deviceId);
}