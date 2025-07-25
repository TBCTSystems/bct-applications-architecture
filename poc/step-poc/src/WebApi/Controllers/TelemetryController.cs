using Microsoft.AspNetCore.Mvc;
using WebApi.Models;
using WebApi.Services;

namespace WebApi.Controllers;

[ApiController]
[Route("api/[controller]")]
public class TelemetryController : ControllerBase
{
    private readonly ILogger<TelemetryController> _logger;
    private readonly ITelemetryDataService _dataService;
    private readonly IMetricsService _metricsService;

    public TelemetryController(
        ILogger<TelemetryController> logger,
        ITelemetryDataService dataService,
        IMetricsService metricsService)
    {
        _logger = logger;
        _dataService = dataService;
        _metricsService = metricsService;
    }

    /// <summary>
    /// Get all known devices with their current status
    /// </summary>
    [HttpGet("devices")]
    public ActionResult<List<DeviceSummary>> GetDevices()
    {
        var stopwatch = System.Diagnostics.Stopwatch.StartNew();
        
        try
        {
            _metricsService.IncrementApiRequests("GET /api/telemetry/devices");
            
            var devices = _dataService.GetAllDeviceSummaries();
            
            _logger.LogDebug("Retrieved {DeviceCount} device summaries", devices.Count);
            
            return Ok(devices);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to retrieve device summaries");
            return StatusCode(500, new { error = "Failed to retrieve devices" });
        }
        finally
        {
            stopwatch.Stop();
            _metricsService.RecordApiResponseTime("GET /api/telemetry/devices", stopwatch.ElapsedMilliseconds);
        }
    }

    /// <summary>
    /// Get detailed information for a specific device
    /// </summary>
    [HttpGet("devices/{deviceId}")]
    public ActionResult<DeviceSummary> GetDevice(string deviceId)
    {
        var stopwatch = System.Diagnostics.Stopwatch.StartNew();
        
        try
        {
            _metricsService.IncrementApiRequests("GET /api/telemetry/devices/{deviceId}");
            
            var device = _dataService.GetDeviceSummary(deviceId);
            
            if (device == null)
            {
                return NotFound(new { error = $"Device '{deviceId}' not found" });
            }
            
            _logger.LogDebug("Retrieved device summary for {DeviceId}", deviceId);
            
            return Ok(device);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to retrieve device summary for {DeviceId}", deviceId);
            return StatusCode(500, new { error = "Failed to retrieve device information" });
        }
        finally
        {
            stopwatch.Stop();
            _metricsService.RecordApiResponseTime("GET /api/telemetry/devices/{deviceId}", stopwatch.ElapsedMilliseconds);
        }
    }

    /// <summary>
    /// Get the latest telemetry data for a specific device
    /// </summary>
    [HttpGet("devices/{deviceId}/latest")]
    public ActionResult<CentrifugeTelemetryData> GetLatestTelemetry(string deviceId)
    {
        var stopwatch = System.Diagnostics.Stopwatch.StartNew();
        
        try
        {
            _metricsService.IncrementApiRequests("GET /api/telemetry/devices/{deviceId}/latest");
            
            var telemetry = _dataService.GetLatestTelemetry(deviceId);
            
            if (telemetry == null)
            {
                return NotFound(new { error = $"No telemetry data found for device '{deviceId}'" });
            }
            
            _logger.LogDebug("Retrieved latest telemetry for {DeviceId}", deviceId);
            
            return Ok(telemetry);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to retrieve latest telemetry for {DeviceId}", deviceId);
            return StatusCode(500, new { error = "Failed to retrieve telemetry data" });
        }
        finally
        {
            stopwatch.Stop();
            _metricsService.RecordApiResponseTime("GET /api/telemetry/devices/{deviceId}/latest", stopwatch.ElapsedMilliseconds);
        }
    }

    /// <summary>
    /// Get historical telemetry data for a specific device
    /// </summary>
    [HttpGet("devices/{deviceId}/history")]
    public ActionResult<List<CentrifugeTelemetryData>> GetTelemetryHistory(
        string deviceId,
        [FromQuery] DateTime? startTime,
        [FromQuery] DateTime? endTime,
        [FromQuery] int? limit)
    {
        var stopwatch = System.Diagnostics.Stopwatch.StartNew();
        
        try
        {
            _metricsService.IncrementApiRequests("GET /api/telemetry/devices/{deviceId}/history");
            
            var request = new TelemetryHistoryRequest
            {
                StartTime = startTime,
                EndTime = endTime,
                Limit = limit ?? 100,
                MetricType = "telemetry"
            };
            
            var history = _dataService.GetTelemetryHistory(deviceId, request);
            
            _logger.LogDebug("Retrieved {RecordCount} telemetry records for {DeviceId}", history.Count, deviceId);
            
            return Ok(history);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to retrieve telemetry history for {DeviceId}", deviceId);
            return StatusCode(500, new { error = "Failed to retrieve telemetry history" });
        }
        finally
        {
            stopwatch.Stop();
            _metricsService.RecordApiResponseTime("GET /api/telemetry/devices/{deviceId}/history", stopwatch.ElapsedMilliseconds);
        }
    }

    /// <summary>
    /// Get historical status data for a specific device
    /// </summary>
    [HttpGet("devices/{deviceId}/status-history")]
    public ActionResult<List<DeviceStatusData>> GetStatusHistory(
        string deviceId,
        [FromQuery] DateTime? startTime,
        [FromQuery] DateTime? endTime,
        [FromQuery] int? limit)
    {
        var stopwatch = System.Diagnostics.Stopwatch.StartNew();
        
        try
        {
            _metricsService.IncrementApiRequests("GET /api/telemetry/devices/{deviceId}/status-history");
            
            var request = new TelemetryHistoryRequest
            {
                StartTime = startTime,
                EndTime = endTime,
                Limit = limit ?? 100,
                MetricType = "status"
            };
            
            var history = _dataService.GetStatusHistory(deviceId, request);
            
            _logger.LogDebug("Retrieved {RecordCount} status records for {DeviceId}", history.Count, deviceId);
            
            return Ok(history);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to retrieve status history for {DeviceId}", deviceId);
            return StatusCode(500, new { error = "Failed to retrieve status history" });
        }
        finally
        {
            stopwatch.Stop();
            _metricsService.RecordApiResponseTime("GET /api/telemetry/devices/{deviceId}/status-history", stopwatch.ElapsedMilliseconds);
        }
    }

    /// <summary>
    /// Get recent alerts for a specific device
    /// </summary>
    [HttpGet("devices/{deviceId}/alerts")]
    public ActionResult<List<DeviceAlertData>> GetRecentAlerts(
        string deviceId,
        [FromQuery] int? count)
    {
        var stopwatch = System.Diagnostics.Stopwatch.StartNew();
        
        try
        {
            _metricsService.IncrementApiRequests("GET /api/telemetry/devices/{deviceId}/alerts");
            
            var alerts = _dataService.GetRecentAlerts(deviceId, count ?? 10);
            
            _logger.LogDebug("Retrieved {AlertCount} recent alerts for {DeviceId}", alerts.Count, deviceId);
            
            return Ok(alerts);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to retrieve alerts for {DeviceId}", deviceId);
            return StatusCode(500, new { error = "Failed to retrieve alerts" });
        }
        finally
        {
            stopwatch.Stop();
            _metricsService.RecordApiResponseTime("GET /api/telemetry/devices/{deviceId}/alerts", stopwatch.ElapsedMilliseconds);
        }
    }
}