using System.Collections.Concurrent;
using Microsoft.Extensions.Logging;
using WebApi.Models;

namespace WebApi.Services;

public class TelemetryDataService : ITelemetryDataService
{
    private readonly ILogger<TelemetryDataService> _logger;
    
    // In-memory storage for PoC - in production, use a proper database
    private readonly ConcurrentDictionary<string, List<CentrifugeTelemetryData>> _telemetryHistory = new();
    private readonly ConcurrentDictionary<string, List<DeviceStatusData>> _statusHistory = new();
    private readonly ConcurrentDictionary<string, List<DeviceAlertData>> _alertHistory = new();
    private readonly ConcurrentDictionary<string, DateTime> _lastSeenTimes = new();
    
    // Keep latest data for quick access
    private readonly ConcurrentDictionary<string, CentrifugeTelemetryData> _latestTelemetry = new();
    private readonly ConcurrentDictionary<string, DeviceStatusData> _latestStatus = new();
    
    // Configuration
    private readonly int _maxHistoryPerDevice = 1000; // Keep last 1000 records per device
    private readonly TimeSpan _connectionTimeout = TimeSpan.FromMinutes(2); // Consider device disconnected after 2 minutes

    public TelemetryDataService(ILogger<TelemetryDataService> logger)
    {
        _logger = logger;
        _logger.LogInformation("Telemetry Data Service initialized with in-memory storage");
    }

    public void StoreTelemetry(CentrifugeTelemetryData telemetry)
    {
        try
        {
            var deviceId = telemetry.DeviceId;
            
            // Update latest telemetry
            _latestTelemetry[deviceId] = telemetry;
            _lastSeenTimes[deviceId] = DateTime.UtcNow;
            
            // Add to history
            var history = _telemetryHistory.GetOrAdd(deviceId, _ => new List<CentrifugeTelemetryData>());
            
            lock (history)
            {
                history.Add(telemetry);
                
                // Trim history if it gets too large
                if (history.Count > _maxHistoryPerDevice)
                {
                    history.RemoveRange(0, history.Count - _maxHistoryPerDevice);
                }
            }
            
            _logger.LogDebug("Stored telemetry for device {DeviceId}: Status={Status}, RPM={Rpm}", 
                deviceId, telemetry.Status, telemetry.Rpm);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to store telemetry for device {DeviceId}", telemetry.DeviceId);
        }
    }

    public void StoreStatus(DeviceStatusData status)
    {
        try
        {
            var deviceId = status.DeviceId;
            
            // Update latest status
            _latestStatus[deviceId] = status;
            _lastSeenTimes[deviceId] = DateTime.UtcNow;
            
            // Add to history
            var history = _statusHistory.GetOrAdd(deviceId, _ => new List<DeviceStatusData>());
            
            lock (history)
            {
                history.Add(status);
                
                // Trim history if it gets too large
                if (history.Count > _maxHistoryPerDevice)
                {
                    history.RemoveRange(0, history.Count - _maxHistoryPerDevice);
                }
            }
            
            _logger.LogDebug("Stored status for device {DeviceId}: Status={Status}, Uptime={Uptime}h", 
                deviceId, status.Status, status.UptimeHours);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to store status for device {DeviceId}", status.DeviceId);
        }
    }

    public void StoreAlert(DeviceAlertData alert)
    {
        try
        {
            var deviceId = alert.DeviceId;
            _lastSeenTimes[deviceId] = DateTime.UtcNow;
            
            // Add to history
            var history = _alertHistory.GetOrAdd(deviceId, _ => new List<DeviceAlertData>());
            
            lock (history)
            {
                history.Add(alert);
                
                // Trim history if it gets too large
                if (history.Count > _maxHistoryPerDevice)
                {
                    history.RemoveRange(0, history.Count - _maxHistoryPerDevice);
                }
            }
            
            _logger.LogInformation("Stored alert for device {DeviceId}: {AlertType} - {Message}", 
                deviceId, alert.AlertType, alert.Message);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to store alert for device {DeviceId}", alert.DeviceId);
        }
    }

    public DeviceSummary? GetDeviceSummary(string deviceId)
    {
        try
        {
            if (!_lastSeenTimes.ContainsKey(deviceId))
            {
                return null;
            }

            var lastSeen = _lastSeenTimes[deviceId];
            var isConnected = IsDeviceConnected(deviceId);
            
            var summary = new DeviceSummary
            {
                DeviceId = deviceId,
                LastSeen = lastSeen,
                IsConnected = isConnected,
                LatestTelemetry = GetLatestTelemetry(deviceId),
                LatestStatus = GetLatestStatus(deviceId),
                RecentAlerts = GetRecentAlerts(deviceId, 5),
                Status = isConnected ? "Online" : "Offline"
            };

            // Calculate uptime from latest status
            if (summary.LatestStatus != null)
            {
                summary.Uptime = TimeSpan.FromHours(summary.LatestStatus.UptimeHours);
            }

            return summary;
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to get device summary for {DeviceId}", deviceId);
            return null;
        }
    }

    public List<DeviceSummary> GetAllDeviceSummaries()
    {
        var summaries = new List<DeviceSummary>();
        
        foreach (var deviceId in GetKnownDeviceIds())
        {
            var summary = GetDeviceSummary(deviceId);
            if (summary != null)
            {
                summaries.Add(summary);
            }
        }
        
        return summaries.OrderBy(s => s.DeviceId).ToList();
    }

    public List<CentrifugeTelemetryData> GetTelemetryHistory(string deviceId, TelemetryHistoryRequest request)
    {
        if (!_telemetryHistory.TryGetValue(deviceId, out var history))
        {
            return new List<CentrifugeTelemetryData>();
        }

        lock (history)
        {
            var query = history.AsEnumerable();

            // Apply time filters
            if (request.StartTime.HasValue)
            {
                query = query.Where(t => t.Timestamp >= request.StartTime.Value);
            }
            
            if (request.EndTime.HasValue)
            {
                query = query.Where(t => t.Timestamp <= request.EndTime.Value);
            }

            // Apply limit
            if (request.Limit.HasValue)
            {
                query = query.TakeLast(request.Limit.Value);
            }

            return query.ToList();
        }
    }

    public List<DeviceStatusData> GetStatusHistory(string deviceId, TelemetryHistoryRequest request)
    {
        if (!_statusHistory.TryGetValue(deviceId, out var history))
        {
            return new List<DeviceStatusData>();
        }

        lock (history)
        {
            var query = history.AsEnumerable();

            if (request.StartTime.HasValue)
            {
                query = query.Where(s => s.Timestamp >= request.StartTime.Value);
            }
            
            if (request.EndTime.HasValue)
            {
                query = query.Where(s => s.Timestamp <= request.EndTime.Value);
            }

            if (request.Limit.HasValue)
            {
                query = query.TakeLast(request.Limit.Value);
            }

            return query.ToList();
        }
    }

    public List<DeviceAlertData> GetAlertHistory(string deviceId, TelemetryHistoryRequest request)
    {
        if (!_alertHistory.TryGetValue(deviceId, out var history))
        {
            return new List<DeviceAlertData>();
        }

        lock (history)
        {
            var query = history.AsEnumerable();

            if (request.StartTime.HasValue)
            {
                query = query.Where(a => a.Timestamp >= request.StartTime.Value);
            }
            
            if (request.EndTime.HasValue)
            {
                query = query.Where(a => a.Timestamp <= request.EndTime.Value);
            }

            if (request.Limit.HasValue)
            {
                query = query.TakeLast(request.Limit.Value);
            }

            return query.ToList();
        }
    }

    public CentrifugeTelemetryData? GetLatestTelemetry(string deviceId)
    {
        return _latestTelemetry.TryGetValue(deviceId, out var telemetry) ? telemetry : null;
    }

    public DeviceStatusData? GetLatestStatus(string deviceId)
    {
        return _latestStatus.TryGetValue(deviceId, out var status) ? status : null;
    }

    public List<DeviceAlertData> GetRecentAlerts(string deviceId, int count = 10)
    {
        if (!_alertHistory.TryGetValue(deviceId, out var history))
        {
            return new List<DeviceAlertData>();
        }

        lock (history)
        {
            return history.TakeLast(count).ToList();
        }
    }

    public List<string> GetKnownDeviceIds()
    {
        return _lastSeenTimes.Keys.ToList();
    }

    public bool IsDeviceConnected(string deviceId)
    {
        if (!_lastSeenTimes.TryGetValue(deviceId, out var lastSeen))
        {
            return false;
        }

        return DateTime.UtcNow - lastSeen <= _connectionTimeout;
    }

    public DateTime? GetLastSeenTime(string deviceId)
    {
        return _lastSeenTimes.TryGetValue(deviceId, out var lastSeen) ? lastSeen : null;
    }
}