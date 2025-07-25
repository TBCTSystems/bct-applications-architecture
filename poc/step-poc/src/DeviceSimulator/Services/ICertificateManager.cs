using System.Security.Cryptography.X509Certificates;

namespace DeviceSimulator.Services;

public interface ICertificateManager
{
    Task<X509Certificate2?> GetClientCertificateAsync();
    Task<X509Certificate2?> GetCaCertificateAsync();
    bool IsCertificateValid(X509Certificate2? certificate);
    event EventHandler<CertificateUpdatedEventArgs>? CertificateUpdated;
}

public class CertificateUpdatedEventArgs : EventArgs
{
    public X509Certificate2? Certificate { get; set; }
    public DateTime UpdatedAt { get; set; } = DateTime.UtcNow;
}