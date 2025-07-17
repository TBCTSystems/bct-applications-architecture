using System.Security.Cryptography.X509Certificates;
using System.Text.Json;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Logging;

namespace LumiaApp.Services;

public class CertificateManager : ICertificateManager
{
    private readonly IProvisioningClient _provisioningClient;
    private readonly IConfiguration _configuration;
    private readonly ILogger<CertificateManager> _logger;
    private X509Certificate2? _currentCertificate;
    private readonly string _certificateStorePath;

    public CertificateManager(
        IProvisioningClient provisioningClient,
        IConfiguration configuration,
        ILogger<CertificateManager> logger)
    {
        _provisioningClient = provisioningClient;
        _configuration = configuration;
        _logger = logger;
        _certificateStorePath = "/app/data/certificates";
        
        Directory.CreateDirectory(_certificateStorePath);
    }

    public async Task InitializeAsync()
    {
        _logger.LogInformation("🔐 Initializing certificate manager...");

        // Try to load existing certificate
        _currentCertificate = await LoadCertificateFromDiskAsync();

        if (_currentCertificate == null || !IsCertificateValid(_currentCertificate))
        {
            _logger.LogInformation("No valid certificate found, requesting new certificate...");
            await RequestNewCertificateAsync();
        }
        else
        {
            _logger.LogInformation("Valid certificate loaded from disk");
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
            _logger.LogWarning("No certificate available");
            await RequestNewCertificateAsync();
            return;
        }

        var timeUntilExpiry = GetTimeUntilExpiry(_currentCertificate);
        if (timeUntilExpiry.HasValue)
        {
            _logger.LogDebug("Certificate expires in {TimeUntilExpiry}", timeUntilExpiry.Value);

            // Renew if less than 7 days remaining
            if (timeUntilExpiry.Value.TotalDays < 7)
            {
                _logger.LogInformation("Certificate expires soon, initiating renewal...");
                await RenewCertificateAsync();
            }
        }
        else
        {
            _logger.LogWarning("Certificate is expired or invalid");
            await RequestNewCertificateAsync();
        }
    }

    public async Task RenewCertificateAsync()
    {
        _logger.LogInformation("🔄 Renewing certificate...");
        await RequestNewCertificateAsync();
    }

    public bool IsCertificateValid(X509Certificate2? certificate)
    {
        if (certificate == null)
            return false;

        try
        {
            // Check if certificate is not expired
            var now = DateTime.UtcNow;
            if (now < certificate.NotBefore || now > certificate.NotAfter)
            {
                _logger.LogDebug("Certificate is outside valid time range");
                return false;
            }

            // Check if certificate has private key
            if (!certificate.HasPrivateKey)
            {
                _logger.LogDebug("Certificate does not have private key");
                return false;
            }

            return true;
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error validating certificate");
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
            var commonName = "lumia-app";
            var sans = new List<string> { "lumia-app", "localhost", "127.0.0.1" };

            var certificateData = await _provisioningClient.RequestInitialCertificateAsync(commonName, sans);
            
            // Create certificate from response
            var certBytes = Convert.FromBase64String(certificateData.Certificate);
            var certificate = new X509Certificate2(certBytes);

            // TODO: In a real implementation, we would properly combine the certificate with its private key
            // For the demo, we'll create a self-signed certificate
            _currentCertificate = CreateDemoCertificate(commonName, sans);

            await SaveCertificateToDiskAsync(_currentCertificate);
            
            _logger.LogInformation("✅ New certificate obtained and saved");
            LogCertificateInfo(_currentCertificate);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to request new certificate");
            throw;
        }
    }

    private X509Certificate2 CreateDemoCertificate(string commonName, List<string> sans)
    {
        // For demo purposes, create a self-signed certificate
        // In production, this would use the actual certificate from step-ca
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
            var certPath = Path.Combine(_certificateStorePath, "lumia-app.pfx");
            if (!File.Exists(certPath))
                return null;

            var certBytes = await File.ReadAllBytesAsync(certPath);
            return new X509Certificate2(certBytes, "demo-password");
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to load certificate from disk");
            return null;
        }
    }

    private async Task SaveCertificateToDiskAsync(X509Certificate2 certificate)
    {
        try
        {
            var certPath = Path.Combine(_certificateStorePath, "lumia-app.pfx");
            var certBytes = certificate.Export(X509ContentType.Pfx, "demo-password");
            await File.WriteAllBytesAsync(certPath, certBytes);
            
            _logger.LogDebug("Certificate saved to {CertPath}", certPath);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to save certificate to disk");
        }
    }

    private void LogCertificateInfo(X509Certificate2 certificate)
    {
        _logger.LogInformation("Certificate Info - Subject: {Subject}, Expires: {Expiry}, Serial: {Serial}",
            certificate.Subject,
            certificate.NotAfter,
            certificate.SerialNumber);
    }
}

public class CertificateData
{
    public string Certificate { get; set; } = string.Empty;
    public string PrivateKey { get; set; } = string.Empty;
    public string CertificateChain { get; set; } = string.Empty;
    public DateTime ExpiresAt { get; set; }
}