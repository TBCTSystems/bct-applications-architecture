using Microsoft.AspNetCore.Mvc;
using ProvisioningService.Models;
using ProvisioningService.Services;

namespace ProvisioningService.Controllers;

[ApiController]
[Route("api/[controller]")]
public class ProvisioningController : ControllerBase
{
    private readonly IProvisioningService _provisioningService;
    private readonly IWhitelistService _whitelistService;
    private readonly ILogger<ProvisioningController> _logger;

    public ProvisioningController(
        IProvisioningService provisioningService,
        IWhitelistService whitelistService,
        ILogger<ProvisioningController> logger)
    {
        _provisioningService = provisioningService;
        _whitelistService = whitelistService;
        _logger = logger;
    }

    [HttpPost("certificate")]
    public async Task<IActionResult> RequestCertificate([FromBody] CertificateRequest request)
    {
        try
        {
            var clientIp = HttpContext.Connection.RemoteIpAddress?.ToString();
            _logger.LogInformation("Certificate request from {ClientIp} for {CommonName}", clientIp, request.CommonName);

            if (!_provisioningService.IsEnabled)
            {
                _logger.LogWarning("Certificate request rejected - provisioning service is disabled");
                return BadRequest(new { Error = "Provisioning service is currently disabled" });
            }

            var certificate = await _provisioningService.IssueCertificateAsync(request);
            
            _logger.LogInformation("Certificate issued successfully for {CommonName}", request.CommonName);
            return Ok(certificate);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to issue certificate for {CommonName}", request.CommonName);
            return StatusCode(500, new { Error = "Failed to issue certificate", Details = ex.Message });
        }
    }

    [HttpGet("status")]
    public IActionResult GetStatus()
    {
        return Ok(new
        {
            Enabled = _provisioningService.IsEnabled,
            WhitelistedIPs = _whitelistService.GetWhitelistedIPs(),
            CertificatesIssued = _provisioningService.CertificatesIssued,
            LastActivity = _provisioningService.LastActivity
        });
    }

    [HttpPost("enable")]
    public IActionResult EnableProvisioning()
    {
        _provisioningService.Enable();
        _logger.LogInformation("Provisioning service enabled");
        return Ok(new { Message = "Provisioning service enabled" });
    }

    [HttpPost("disable")]
    public IActionResult DisableProvisioning()
    {
        _provisioningService.Disable();
        _logger.LogInformation("Provisioning service disabled");
        return Ok(new { Message = "Provisioning service disabled" });
    }
}

[ApiController]
[Route("api/[controller]")]
public class WhitelistController : ControllerBase
{
    private readonly IWhitelistService _whitelistService;
    private readonly ILogger<WhitelistController> _logger;

    public WhitelistController(IWhitelistService whitelistService, ILogger<WhitelistController> logger)
    {
        _whitelistService = whitelistService;
        _logger = logger;
    }

    [HttpGet]
    public IActionResult GetWhitelist()
    {
        return Ok(_whitelistService.GetWhitelistedIPs());
    }

    [HttpPost("add")]
    public IActionResult AddToWhitelist([FromBody] WhitelistRequest request)
    {
        _whitelistService.AddIP(request.IpAddress);
        _logger.LogInformation("Added {IpAddress} to whitelist", request.IpAddress);
        return Ok(new { Message = $"IP {request.IpAddress} added to whitelist" });
    }

    [HttpPost("remove")]
    public IActionResult RemoveFromWhitelist([FromBody] WhitelistRequest request)
    {
        _whitelistService.RemoveIP(request.IpAddress);
        _logger.LogInformation("Removed {IpAddress} from whitelist", request.IpAddress);
        return Ok(new { Message = $"IP {request.IpAddress} removed from whitelist" });
    }

    [HttpPost("clear")]
    public IActionResult ClearWhitelist()
    {
        _whitelistService.ClearWhitelist();
        _logger.LogInformation("Whitelist cleared");
        return Ok(new { Message = "Whitelist cleared" });
    }
}