using System.Text;
using System.Text.Json;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Logging;

namespace LumiaApp.Services;

public class ProvisioningClient : IProvisioningClient
{
    private readonly HttpClient _httpClient;
    private readonly IConfiguration _configuration;
    private readonly ILogger<ProvisioningClient> _logger;

    public ProvisioningClient(IConfiguration configuration, ILogger<ProvisioningClient> logger)
    {
        _configuration = configuration;
        _logger = logger;
        
        // Configure HttpClient to ignore SSL certificate validation for demo
        var handler = new HttpClientHandler()
        {
            ServerCertificateCustomValidationCallback = (message, cert, chain, errors) => true
        };
        _httpClient = new HttpClient(handler);
    }

    public async Task<CertificateData> RequestInitialCertificateAsync(string commonName, List<string> sans)
    {
        var baseUrl = _configuration["ProvisioningService:BaseUrl"] ?? "https://provisioning-service:5001";
        var endpoint = $"{baseUrl}/api/provisioning/certificate";

        _logger.LogInformation("🔐 Requesting initial certificate from provisioning service...");

        try
        {
            var request = new
            {
                CommonName = commonName,
                SubjectAlternativeNames = sans,
                DeviceId = "lumia-app",
                DeviceType = "application"
            };

            var json = JsonSerializer.Serialize(request);
            var content = new StringContent(json, Encoding.UTF8, "application/json");

            _logger.LogDebug("Sending certificate request to {Endpoint}", endpoint);

            var response = await _httpClient.PostAsync(endpoint, content);

            if (!response.IsSuccessStatusCode)
            {
                var errorContent = await response.Content.ReadAsStringAsync();
                _logger.LogError("Certificate request failed with status {StatusCode}: {Error}", 
                    response.StatusCode, errorContent);
                throw new HttpRequestException($"Certificate request failed: {response.StatusCode} - {errorContent}");
            }

            var responseJson = await response.Content.ReadAsStringAsync();
            var certificateResponse = JsonSerializer.Deserialize<CertificateResponse>(responseJson, new JsonSerializerOptions
            {
                PropertyNameCaseInsensitive = true
            });

            if (certificateResponse == null)
            {
                throw new InvalidOperationException("Invalid certificate response from provisioning service");
            }

            _logger.LogInformation("✅ Certificate received from provisioning service");

            return new CertificateData
            {
                Certificate = certificateResponse.Certificate,
                PrivateKey = certificateResponse.PrivateKey,
                CertificateChain = certificateResponse.CertificateChain,
                ExpiresAt = certificateResponse.ExpiresAt
            };
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to request certificate from provisioning service");
            throw;
        }
    }

    private class CertificateResponse
    {
        public string Certificate { get; set; } = string.Empty;
        public string PrivateKey { get; set; } = string.Empty;
        public string CertificateChain { get; set; } = string.Empty;
        public DateTime ExpiresAt { get; set; }
        public string SerialNumber { get; set; } = string.Empty;
    }
}