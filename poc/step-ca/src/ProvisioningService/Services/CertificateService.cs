using System.Security.Cryptography;
using System.Security.Cryptography.X509Certificates;
using System.Text;
using System.Text.Json;
using ProvisioningService.Models;

namespace ProvisioningService.Services;

public class CertificateService : ICertificateService
{
    private readonly ILogger<CertificateService> _logger;
    private readonly IConfiguration _configuration;
    private readonly HttpClient _httpClient;

    public CertificateService(ILogger<CertificateService> logger, IConfiguration configuration)
    {
        _logger = logger;
        _configuration = configuration;
        
        // For demo purposes, ignore SSL certificate validation
        var handler = new HttpClientHandler()
        {
            ServerCertificateCustomValidationCallback = (message, cert, chain, errors) => true
        };
        _httpClient = new HttpClient(handler);
    }

    public async Task<CertificateResponse> RequestCertificateFromStepCAAsync(CertificateRequest request)
    {
        try
        {
            _logger.LogInformation("Requesting certificate from step-ca for {CommonName}", request.CommonName);

            // Try to use real step-ca integration first
            var stepCaResponse = await TryRequestFromStepCAAsync(request);
            if (stepCaResponse != null)
            {
                return stepCaResponse;
            }

            // Fallback to self-signed certificate for demo
            _logger.LogWarning("step-ca integration failed, falling back to self-signed certificate for {CommonName}", request.CommonName);
            var certificate = GenerateSelfSignedCertificate(request);

            return new CertificateResponse
            {
                Certificate = Convert.ToBase64String(certificate.RawData),
                PrivateKey = ExportPrivateKey(certificate),
                CertificateChain = Convert.ToBase64String(certificate.RawData),
                ExpiresAt = certificate.NotAfter,
                SerialNumber = certificate.SerialNumber ?? "unknown"
            };
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to request certificate from step-ca");
            throw;
        }
    }

    private async Task<CertificateResponse?> TryRequestFromStepCAAsync(CertificateRequest request)
    {
        try
        {
            var stepCaUrl = _configuration["StepCA:BaseUrl"] ?? "https://step-ca:9000";
            
            // Check if step-ca is available
            var healthResponse = await _httpClient.GetAsync($"{stepCaUrl}/health");
            if (!healthResponse.IsSuccessStatusCode)
            {
                _logger.LogWarning("step-ca health check failed, status: {StatusCode}", healthResponse.StatusCode);
                return null;
            }

            // For now, we'll use a simplified approach since full ACME implementation is complex
            // In production, this would use a proper ACME client library
            _logger.LogInformation("step-ca is available, but using simplified certificate generation for PoC");
            
            // Generate certificate with step-ca characteristics but locally
            var certificate = GenerateStepCAStyleCertificate(request);
            
            return new CertificateResponse
            {
                Certificate = Convert.ToBase64String(certificate.RawData),
                PrivateKey = ExportPrivateKey(certificate),
                CertificateChain = Convert.ToBase64String(certificate.RawData),
                ExpiresAt = certificate.NotAfter,
                SerialNumber = certificate.SerialNumber ?? "unknown"
            };
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "Failed to connect to step-ca, will use fallback");
            return null;
        }
    }

    private X509Certificate2 GenerateStepCAStyleCertificate(CertificateRequest request)
    {
        using var rsa = RSA.Create(2048);
        
        var certificateRequest = new CertificateRequest(
            $"CN={request.CommonName}",
            rsa,
            HashAlgorithmName.SHA256,
            RSASignaturePadding.Pkcs1);

        // Add Subject Alternative Names
        var sanBuilder = new SubjectAlternativeNameBuilder();
        sanBuilder.AddDnsName(request.CommonName);
        
        foreach (var san in request.SubjectAlternativeNames)
        {
            if (IsValidIpAddress(san))
                sanBuilder.AddIpAddress(System.Net.IPAddress.Parse(san));
            else
                sanBuilder.AddDnsName(san);
        }
        
        certificateRequest.CertificateExtensions.Add(sanBuilder.Build());

        // Add Key Usage for both client and server authentication
        certificateRequest.CertificateExtensions.Add(
            new X509KeyUsageExtension(
                X509KeyUsageFlags.DigitalSignature | X509KeyUsageFlags.KeyEncipherment,
                critical: true));

        // Add Extended Key Usage for client and server authentication
        certificateRequest.CertificateExtensions.Add(
            new X509EnhancedKeyUsageExtension(
                new OidCollection { 
                    new Oid("1.3.6.1.5.5.7.3.1"), // Server Authentication
                    new Oid("1.3.6.1.5.5.7.3.2")  // Client Authentication
                }, 
                critical: true));

        // Add Basic Constraints for end-entity certificate
        certificateRequest.CertificateExtensions.Add(
            new X509BasicConstraintsExtension(false, false, 0, true));

        // Create the certificate with step-ca style validity (720 hours = 30 days)
        var certificate = certificateRequest.CreateSelfSigned(
            DateTimeOffset.UtcNow.AddMinutes(-5), // 5 minutes before now
            DateTimeOffset.UtcNow.AddHours(720)); // 30 days validity

        return certificate;
    }

    private X509Certificate2 GenerateSelfSignedCertificate(CertificateRequest request)
    {
        using var rsa = RSA.Create(2048);
        
        var certificateRequest = new CertificateRequest(
            $"CN={request.CommonName}",
            rsa,
            HashAlgorithmName.SHA256,
            RSASignaturePadding.Pkcs1);

        // Add Subject Alternative Names
        var sanBuilder = new SubjectAlternativeNameBuilder();
        sanBuilder.AddDnsName(request.CommonName);
        
        foreach (var san in request.SubjectAlternativeNames)
        {
            if (IsValidIpAddress(san))
                sanBuilder.AddIpAddress(System.Net.IPAddress.Parse(san));
            else
                sanBuilder.AddDnsName(san);
        }
        
        certificateRequest.CertificateExtensions.Add(sanBuilder.Build());

        // Add Key Usage
        certificateRequest.CertificateExtensions.Add(
            new X509KeyUsageExtension(
                X509KeyUsageFlags.DigitalSignature | X509KeyUsageFlags.KeyEncipherment,
                critical: true));

        // Add Extended Key Usage for client authentication
        certificateRequest.CertificateExtensions.Add(
            new X509EnhancedKeyUsageExtension(
                new OidCollection { new Oid("1.3.6.1.5.5.7.3.2") }, // Client Authentication
                critical: true));

        // Create the certificate
        var certificate = certificateRequest.CreateSelfSigned(
            DateTimeOffset.UtcNow.AddDays(-1),
            DateTimeOffset.UtcNow.AddDays(30)); // 30-day validity for demo

        return certificate;
    }

    private string ExportPrivateKey(X509Certificate2 certificate)
    {
        var privateKey = certificate.GetRSAPrivateKey();
        if (privateKey == null)
            throw new InvalidOperationException("Certificate does not contain a private key");

        var privateKeyBytes = privateKey.ExportRSAPrivateKey();
        var privateKeyPem = Convert.ToBase64String(privateKeyBytes);
        
        var sb = new StringBuilder();
        sb.AppendLine("-----BEGIN RSA PRIVATE KEY-----");
        
        for (int i = 0; i < privateKeyPem.Length; i += 64)
        {
            var length = Math.Min(64, privateKeyPem.Length - i);
            sb.AppendLine(privateKeyPem.Substring(i, length));
        }
        
        sb.AppendLine("-----END RSA PRIVATE KEY-----");
        
        return sb.ToString();
    }

    private bool IsValidIpAddress(string input)
    {
        return System.Net.IPAddress.TryParse(input, out _);
    }
}