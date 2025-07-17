using System.Security.Cryptography.X509Certificates;

namespace LumiaApp.Services;

public interface ICertificateManager
{
    Task InitializeAsync();
    Task<X509Certificate2?> GetCurrentCertificateAsync();
    Task CheckCertificateStatusAsync();
    Task RenewCertificateAsync();
    bool IsCertificateValid(X509Certificate2? certificate);
    TimeSpan? GetTimeUntilExpiry(X509Certificate2? certificate);
}

public interface IMqttService
{
    Task StartAsync();
    Task StopAsync();
    Task PublishHeartbeatAsync();
    Task PublishMessageAsync(string topic, string message);
    bool IsConnected { get; }
}

public interface IProvisioningClient
{
    Task<CertificateData> RequestInitialCertificateAsync(string commonName, List<string> sans);
}