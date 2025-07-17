namespace ProvisioningService.Models;

public class CertificateRequest
{
    public string CommonName { get; set; } = string.Empty;
    public List<string> SubjectAlternativeNames { get; set; } = new();
    public string DeviceId { get; set; } = string.Empty;
    public string DeviceType { get; set; } = string.Empty;
}

public class CertificateResponse
{
    public string Certificate { get; set; } = string.Empty;
    public string PrivateKey { get; set; } = string.Empty;
    public string CertificateChain { get; set; } = string.Empty;
    public DateTime ExpiresAt { get; set; }
    public string SerialNumber { get; set; } = string.Empty;
}

public class WhitelistRequest
{
    public string IpAddress { get; set; } = string.Empty;
}