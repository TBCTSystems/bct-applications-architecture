using System.Security.Cryptography.X509Certificates;

namespace ReveosSimpleMocker.Services;

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
    Task PublishDeviceDataAsync(object data);
    Task PublishStatusAsync(string status);
    bool IsConnected { get; }
}

public interface IProvisioningClient
{
    Task<CertificateData> RequestInitialCertificateAsync(string commonName, List<string> sans);
}

public interface IDeviceSimulator
{
    Task StartAsync();
    Task StopAsync();
    Task SimulateDeviceOperationsAsync();
}

public class CertificateData
{
    public string Certificate { get; set; } = string.Empty;
    public string PrivateKey { get; set; } = string.Empty;
    public string CertificateChain { get; set; } = string.Empty;
    public DateTime ExpiresAt { get; set; }
}

public class DeviceData
{
    public string DeviceId { get; set; } = string.Empty;
    public DateTime Timestamp { get; set; }
    public string Status { get; set; } = string.Empty;
    public Dictionary<string, object> Measurements { get; set; } = new();
    public string FirmwareVersion { get; set; } = "2.1.0";
}