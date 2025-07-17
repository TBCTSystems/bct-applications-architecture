using ProvisioningService.Models;

namespace ProvisioningService.Services;

public interface IProvisioningService
{
    bool IsEnabled { get; }
    int CertificatesIssued { get; }
    DateTime? LastActivity { get; }
    
    Task<CertificateResponse> IssueCertificateAsync(CertificateRequest request);
    void Enable();
    void Disable();
}

public interface IWhitelistService
{
    bool IsWhitelisted(string ipAddress);
    void AddIP(string ipAddress);
    void RemoveIP(string ipAddress);
    void ClearWhitelist();
    List<string> GetWhitelistedIPs();
}

public interface ICertificateService
{
    Task<CertificateResponse> RequestCertificateFromStepCAAsync(CertificateRequest request);
}