using System.Text;
using System.Text.Json;
using DemoWeb.Models;

namespace DemoWeb.Services;

public class SystemMonitorService : ISystemMonitorService
{
    private readonly HttpClient _httpClient;
    private readonly IConfiguration _configuration;
    private readonly ILogger<SystemMonitorService> _logger;

    public SystemMonitorService(IConfiguration configuration, ILogger<SystemMonitorService> logger)
    {
        _configuration = configuration;
        _logger = logger;
        
        var handler = new HttpClientHandler()
        {
            ServerCertificateCustomValidationCallback = (message, cert, chain, errors) => true
        };
        _httpClient = new HttpClient(handler);
    }

    public async Task<SystemStatus> GetSystemStatusAsync()
    {
        var status = new SystemStatus
        {
            LastUpdated = DateTime.UtcNow,
            OverallStatus = "Checking..."
        };

        try
        {
            // Check step-ca
            status.StepCA = await CheckServiceAsync("step-ca", "https://step-ca:9000/health");
            
            // Check provisioning service
            status.ProvisioningService = await CheckProvisioningServiceAsync();
            
            // Check MQTT broker (simplified check)
            status.MqttBroker = CheckMqttBroker();
            
            // Check Lumia app (simplified)
            status.LumiaApp = new ServiceStatus
            {
                Name = "Lumia 1.1 Application",
                Status = "Running",
                LastCheck = DateTime.UtcNow
            };

            // Simulate device status
            status.Devices = GetSimulatedDeviceStatus();

            // Determine overall status
            var allServices = new[] { status.StepCA, status.ProvisioningService, status.MqttBroker, status.LumiaApp };
            status.OverallStatus = allServices.All(s => s.Status == "Healthy" || s.Status == "Running") 
                ? "Healthy" : "Degraded";
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error getting system status");
            status.OverallStatus = "Error";
        }

        return status;
    }

    public async Task EnableProvisioningServiceAsync()
    {
        try
        {
            var url = "https://provisioning-service:5001/api/provisioning/enable";
            var response = await _httpClient.PostAsync(url, null);
            
            if (!response.IsSuccessStatusCode)
            {
                throw new HttpRequestException($"Failed to enable provisioning service: {response.StatusCode}");
            }
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to enable provisioning service");
            throw;
        }
    }

    public async Task DisableProvisioningServiceAsync()
    {
        try
        {
            var url = "https://provisioning-service:5001/api/provisioning/disable";
            var response = await _httpClient.PostAsync(url, null);
            
            if (!response.IsSuccessStatusCode)
            {
                throw new HttpRequestException($"Failed to disable provisioning service: {response.StatusCode}");
            }
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to disable provisioning service");
            throw;
        }
    }

    public async Task AddToWhitelistAsync(string ipAddress)
    {
        try
        {
            var url = "https://provisioning-service:5001/api/whitelist/add";
            var request = new { IpAddress = ipAddress };
            var json = JsonSerializer.Serialize(request);
            var content = new StringContent(json, Encoding.UTF8, "application/json");
            
            var response = await _httpClient.PostAsync(url, content);
            
            if (!response.IsSuccessStatusCode)
            {
                throw new HttpRequestException($"Failed to add IP to whitelist: {response.StatusCode}");
            }
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to add IP to whitelist");
            throw;
        }
    }

    public async Task<List<CertificateInfo>> GetCertificateStatusAsync()
    {
        // For demo purposes, return simulated certificate information
        return new List<CertificateInfo>
        {
            new CertificateInfo
            {
                Subject = "CN=lumia-app",
                Issuer = "CN=Enterprise Root CA",
                NotBefore = DateTime.UtcNow.AddDays(-1),
                NotAfter = DateTime.UtcNow.AddDays(29),
                SerialNumber = "123456789",
                IsValid = true,
                TimeUntilExpiry = TimeSpan.FromDays(29),
                Owner = "Lumia Application"
            },
            new CertificateInfo
            {
                Subject = "CN=REVEOS-SIM-001",
                Issuer = "CN=Enterprise Root CA",
                NotBefore = DateTime.UtcNow.AddDays(-1),
                NotAfter = DateTime.UtcNow.AddDays(29),
                SerialNumber = "987654321",
                IsValid = true,
                TimeUntilExpiry = TimeSpan.FromDays(29),
                Owner = "Reveos Device Simulator"
            },
            new CertificateInfo
            {
                Subject = "CN=mosquitto",
                Issuer = "CN=Enterprise Root CA",
                NotBefore = DateTime.UtcNow.AddDays(-1),
                NotAfter = DateTime.UtcNow.AddDays(29),
                SerialNumber = "456789123",
                IsValid = true,
                TimeUntilExpiry = TimeSpan.FromDays(29),
                Owner = "MQTT Broker"
            }
        };
    }

    private async Task<ServiceStatus> CheckServiceAsync(string serviceName, string healthUrl)
    {
        var status = new ServiceStatus
        {
            Name = serviceName,
            Url = healthUrl,
            LastCheck = DateTime.UtcNow
        };

        try
        {
            var response = await _httpClient.GetAsync(healthUrl);
            status.Status = response.IsSuccessStatusCode ? "Healthy" : "Unhealthy";
            
            if (response.IsSuccessStatusCode)
            {
                var content = await response.Content.ReadAsStringAsync();
                // Parse any metrics from the response if available
            }
        }
        catch (Exception ex)
        {
            status.Status = "Unreachable";
            status.ErrorMessage = ex.Message;
        }

        return status;
    }

    private async Task<ServiceStatus> CheckProvisioningServiceAsync()
    {
        var status = new ServiceStatus
        {
            Name = "Provisioning Service",
            Url = "https://provisioning-service:5001",
            LastCheck = DateTime.UtcNow
        };

        try
        {
            var response = await _httpClient.GetAsync("https://provisioning-service:5001/api/provisioning/status");
            
            if (response.IsSuccessStatusCode)
            {
                status.Status = "Healthy";
                var content = await response.Content.ReadAsStringAsync();
                var statusData = JsonSerializer.Deserialize<JsonElement>(content);
                
                if (statusData.TryGetProperty("enabled", out var enabled))
                {
                    status.Metrics["Enabled"] = enabled.GetBoolean();
                }
                if (statusData.TryGetProperty("certificatesIssued", out var issued))
                {
                    status.Metrics["CertificatesIssued"] = issued.GetInt32();
                }
            }
            else
            {
                status.Status = "Unhealthy";
            }
        }
        catch (Exception ex)
        {
            status.Status = "Unreachable";
            status.ErrorMessage = ex.Message;
        }

        return status;
    }

    private ServiceStatus CheckMqttBroker()
    {
        // For demo purposes, assume MQTT broker is running
        return new ServiceStatus
        {
            Name = "MQTT Broker (Mosquitto)",
            Status = "Running",
            Url = "mosquitto:8883",
            LastCheck = DateTime.UtcNow,
            Metrics = new Dictionary<string, object>
            {
                ["Port"] = 8883,
                ["TLS"] = true,
                ["ClientAuth"] = "Required"
            }
        };
    }

    private List<DeviceStatus> GetSimulatedDeviceStatus()
    {
        return new List<DeviceStatus>
        {
            new DeviceStatus
            {
                DeviceId = "REVEOS-SIM-001",
                Status = "operational",
                LastSeen = DateTime.UtcNow.AddSeconds(-30),
                CertificateValid = true,
                CertificateExpiry = DateTime.UtcNow.AddDays(29),
                MqttConnected = true,
                LastData = new Dictionary<string, object>
                {
                    ["temperature"] = 23.5,
                    ["pressure"] = 1013.2,
                    ["cycle_count"] = 1234
                }
            }
        };
    }
}