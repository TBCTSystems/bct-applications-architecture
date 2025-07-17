using ProvisioningService.Models;

namespace ProvisioningService.Services;

public class ProvisioningService : IProvisioningService
{
    private readonly ICertificateService _certificateService;
    private readonly ILogger<ProvisioningService> _logger;
    private bool _isEnabled = true;
    private int _certificatesIssued = 0;
    private DateTime? _lastActivity;

    public bool IsEnabled => _isEnabled;
    public int CertificatesIssued => _certificatesIssued;
    public DateTime? LastActivity => _lastActivity;

    public ProvisioningService(ICertificateService certificateService, ILogger<ProvisioningService> logger)
    {
        _certificateService = certificateService;
        _logger = logger;
    }

    public async Task<CertificateResponse> IssueCertificateAsync(CertificateRequest request)
    {
        if (!_isEnabled)
        {
            throw new InvalidOperationException("Provisioning service is disabled");
        }

        _logger.LogInformation("Issuing certificate for {CommonName}", request.CommonName);
        
        var certificate = await _certificateService.RequestCertificateFromStepCAAsync(request);
        
        _certificatesIssued++;
        _lastActivity = DateTime.UtcNow;
        
        _logger.LogInformation("Certificate issued successfully. Total certificates: {Count}", _certificatesIssued);
        
        return certificate;
    }

    public void Enable()
    {
        _isEnabled = true;
        _logger.LogInformation("Provisioning service enabled");
    }

    public void Disable()
    {
        _isEnabled = false;
        _logger.LogInformation("Provisioning service disabled");
    }
}