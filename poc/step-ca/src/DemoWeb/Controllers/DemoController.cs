using Microsoft.AspNetCore.Mvc;
using DemoWeb.Services;
using DemoWeb.Models;

namespace DemoWeb.Controllers;

[ApiController]
[Route("api/[controller]")]
public class DemoController : ControllerBase
{
    private readonly ISystemMonitorService _systemMonitor;
    private readonly IMqttMonitorService _mqttMonitor;
    private readonly ILogger<DemoController> _logger;

    public DemoController(
        ISystemMonitorService systemMonitor,
        IMqttMonitorService mqttMonitor,
        ILogger<DemoController> logger)
    {
        _systemMonitor = systemMonitor;
        _mqttMonitor = mqttMonitor;
        _logger = logger;
    }

    [HttpGet("status")]
    public async Task<IActionResult> GetSystemStatus()
    {
        try
        {
            var status = await _systemMonitor.GetSystemStatusAsync();
            return Ok(status);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to get system status");
            return StatusCode(500, new { Error = "Failed to get system status" });
        }
    }

    [HttpGet("mqtt/messages")]
    public IActionResult GetRecentMqttMessages()
    {
        try
        {
            var messages = _mqttMonitor.GetRecentMessages();
            return Ok(messages);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to get MQTT messages");
            return StatusCode(500, new { Error = "Failed to get MQTT messages" });
        }
    }

    [HttpPost("provisioning/enable")]
    public async Task<IActionResult> EnableProvisioning()
    {
        try
        {
            await _systemMonitor.EnableProvisioningServiceAsync();
            _logger.LogInformation("Provisioning service enabled via demo interface");
            return Ok(new { Message = "Provisioning service enabled" });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to enable provisioning service");
            return StatusCode(500, new { Error = "Failed to enable provisioning service" });
        }
    }

    [HttpPost("provisioning/disable")]
    public async Task<IActionResult> DisableProvisioning()
    {
        try
        {
            await _systemMonitor.DisableProvisioningServiceAsync();
            _logger.LogInformation("Provisioning service disabled via demo interface");
            return Ok(new { Message = "Provisioning service disabled" });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to disable provisioning service");
            return StatusCode(500, new { Error = "Failed to disable provisioning service" });
        }
    }

    [HttpPost("whitelist/add")]
    public async Task<IActionResult> AddToWhitelist([FromBody] WhitelistRequest request)
    {
        try
        {
            await _systemMonitor.AddToWhitelistAsync(request.IpAddress);
            _logger.LogInformation("Added {IpAddress} to whitelist via demo interface", request.IpAddress);
            return Ok(new { Message = $"IP {request.IpAddress} added to whitelist" });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to add IP to whitelist");
            return StatusCode(500, new { Error = "Failed to add IP to whitelist" });
        }
    }

    [HttpGet("certificates")]
    public async Task<IActionResult> GetCertificateStatus()
    {
        try
        {
            var certificates = await _systemMonitor.GetCertificateStatusAsync();
            return Ok(certificates);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to get certificate status");
            return StatusCode(500, new { Error = "Failed to get certificate status" });
        }
    }

    [HttpPost("simulate/device-event")]
    public async Task<IActionResult> SimulateDeviceEvent([FromBody] DeviceEventRequest request)
    {
        try
        {
            // This would trigger a simulated device event
            _logger.LogInformation("Simulating device event: {EventType} for device {DeviceId}", 
                request.EventType, request.DeviceId);
            
            return Ok(new { Message = $"Device event {request.EventType} simulated" });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to simulate device event");
            return StatusCode(500, new { Error = "Failed to simulate device event" });
        }
    }
}