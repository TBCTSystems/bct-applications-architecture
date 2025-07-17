using System.Security.Cryptography.X509Certificates;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Logging;

namespace ReveosSimpleMocker.Services;

public class CertificateManager : ICertificateManager
{
    private readonly IProvisioningClient _provisioningClient;
    private readonly IConfiguration _configuration;
    private readonly ILogger<CertificateManager> _logger;
    private X509Certificate2? _currentCertificate;
    private readonly string _certificateStorePath;
    private readonly string _deviceId;

    public CertificateManager(
        IProvisioningClient provisioningClient,
        IConfiguration configuration,
        ILogger<CertificateManager> logger)
    {
        _provisioningClient = provisioningClient;
        _configuration = configuration;
        _logger = logger;
        _deviceId = Environment.GetEnvironmentVariable("Device__Id") ?? "REVEOS-SIM-001";
        _certificateStorePath = "/app/data/certificates";
        
        Directory.CreateDirectory(_certificateStorePath);
    }

    public async Task InitializeAsync()
    {
        _logger.LogInformation("🔐 Initializing certificate manager for device {DeviceId}...", _deviceId);

        // Try to load existing certificate
        _currentCertificate = await LoadCertificateFromDiskAsync();

        if (_currentCertificate == null || !IsCertificateValid(_currentCertificate))
        {
            _logger.LogInformation("No valid certificate found for device {DeviceId}, requesting new certificate...", _deviceId);
            await RequestNewCertificateAsync();
        }
        else
        {
            _logger.LogInformation("Valid certificate loaded from disk for device {DeviceId}", _deviceId);
            LogCertificateInfo(_currentCertificate);
        }
    }

    public async Task<X509Certificate2?> GetCurrentCertificateAsync()
    {
        return _currentCertificate;
    }

    public async Task CheckCertificateStatusAsync()
    {
        if (_currentCertificate == null)
        {
            _logger.LogWarning("No certificate available for device {DeviceId}", _deviceId);
            await RequestNewCertificateAsync();
            return;
        }

        var timeUntilExpiry = GetTimeUntilExpiry(_currentCertificate);
        if (timeUntilExpiry.HasValue)
        {
            _logger.LogDebug("Device {DeviceId} certificate expires in {TimeUntilExpiry}", _deviceId, timeUntilExpiry.Value);

            // Renew if less than 7 days remaining
            if (timeUntilExpiry.Value.TotalDays < 7)
            {
                _logger.LogInformation("Device {DeviceId} certificate expires soon, initiating renewal...", _deviceId);
                await RenewCertificateAsync();
            }
        }
        else
        {
            _logger.LogWarning("Device {DeviceId} certificate is expired or invalid", _deviceId);
            await RequestNewCertificateAsync();
        }
    }

    public async Task RenewCertificateAsync()
    {
        _logger.LogInformation("🔄 Renewing certificate for device {DeviceId}...", _deviceId);
        await RequestNewCertificateAsync();
    }

    public bool IsCertificateValid(X509Certificate2? certificate)
    {
        if (certificate == null)
            return false;

        try
        {
            var now = DateTime.UtcNow;
            if (now < certificate.NotBefore || now > certificate.NotAfter)
            {
                _logger.LogDebug("Certificate for device {DeviceId} is outside valid time range", _deviceId);
                return false;
            }

            if (!certificate.HasPrivateKey)
            {
                _logger.LogDebug("Certificate for device {DeviceId} does not have private key", _deviceId);
                return false;
            }

            return true;
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error validating certificate for device {DeviceId}", _deviceId);
            return false;
        }
    }

    public TimeSpan? GetTimeUntilExpiry(X509Certificate2? certificate)
    {
        if (certificate == null)
            return null;

        var timeUntilExpiry = certificate.NotAfter - DateTime.UtcNow;
        return timeUntilExpiry.TotalSeconds > 0 ? timeUntilExpiry : null;
    }

    private async Task RequestNewCertificateAsync()
    {
        try
        {
            var commonName = _deviceId;
            var sans = new List<string> { _deviceId, "localhost" };

            var certificateData = await _provisioningClient.RequestInitialCertificateAsync(commonName, sans);
            
            // For demo purposes, create a self-signed certificate
            // In production, this would use the actual certificate from step-ca
            _currentCertificate = CreateDemoCertificate(commonName, sans);

            await SaveCertificateToDiskAsync(_currentCertificate);
            
            _logger.LogInformation("✅ New certificate obtained and saved for device {DeviceId}", _deviceId);
            LogCertificateInfo(_currentCertificate);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to request new certificate for device {DeviceId}", _deviceId);
            throw;
        }
    }

    private X509Certificate2 CreateDemoCertificate(string commonName, List<string> sans)
    {
        using var rsa = System.Security.Cryptography.RSA.Create(2048);
        
        var request = new System.Security.Cryptography.X509Certificates.CertificateRequest(
            $"CN={commonName}",
            rsa,
            System.Security.Cryptography.HashAlgorithmName.SHA256,
            System.Security.Cryptography.RSASignaturePadding.Pkcs1);

        var sanBuilder = new System.Security.Cryptography.X509Certificates.SubjectAlternativeNameBuilder();
        foreach (var san in sans)
        {
            sanBuilder.AddDnsName(san);
        }
        request.CertificateExtensions.Add(sanBuilder.Build());

        return request.CreateSelfSigned(
            DateTimeOffset.UtcNow.AddDays(-1),
            DateTimeOffset.UtcNow.AddDays(30));
    }

    private async Task<X509Certificate2?> LoadCertificateFromDiskAsync()
    {
        try
        {
            var certPath = Path.Combine(_certificateStorePath, $"{_deviceId}.pfx");
            if (!File.Exists(certPath))
                return null;

            var certBytes = await File.ReadAllBytesAsync(certPath);
            return new X509Certificate2(certBytes, "demo-password");
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to load certificate from disk for device {DeviceId}", _deviceId);
            return null;
        }
    }

    private async Task SaveCertificateToDiskAsync(X509Certificate2 certificate)
    {
        try
        {
            var certPath = Path.Combine(_certificateStorePath, $"{_deviceId}.pfx");
            var certBytes = certificate.Export(X509ContentType.Pfx, "demo-password");
            await File.WriteAllBytesAsync(certPath, certBytes);
            
            _logger.LogDebug("Certificate saved to {CertPath} for device {DeviceId}", certPath, _deviceId);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to save certificate to disk for device {DeviceId}", _deviceId);
        }
    }

    private void LogCertificateInfo(X509Certificate2 certificate)
    {
        _logger.LogInformation("Device {DeviceId} Certificate Info - Subject: {Subject}, Expires: {Expiry}, Serial: {Serial}",
            _deviceId,
            certificate.Subject,
            certificate.NotAfter,
            certificate.SerialNumber);
    }
}