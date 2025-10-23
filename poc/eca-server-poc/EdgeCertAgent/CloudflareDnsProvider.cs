using System;
using System.Collections.Generic;
using System.Net.Http;
using System.Text;
using System.Text.Json;
using System.Threading.Tasks;

namespace EdgeCertAgent;

/// <summary>
/// Cloudflare DNS provider - FREE tier available at cloudflare.com
/// Get API token from: https://dash.cloudflare.com/profile/api-tokens
/// Required permissions: Zone.DNS (Edit)
/// </summary>
public sealed class CloudflareDnsProvider : IDnsProvider
{
    private readonly string _apiToken;
    private readonly string _zoneId;
    private readonly HttpClient _httpClient;
    private readonly Dictionary<string, string> _recordIds = new();

    public CloudflareDnsProvider(string apiToken, string zoneId)
    {
        _apiToken = apiToken ?? throw new ArgumentNullException(nameof(apiToken));
        _zoneId = zoneId ?? throw new ArgumentNullException(nameof(zoneId));
        
        _httpClient = new HttpClient
        {
            BaseAddress = new Uri("https://api.cloudflare.com/client/v4/")
        };
        _httpClient.DefaultRequestHeaders.Add("Authorization", $"Bearer {_apiToken}");
    }

    public async Task CreateTxtRecord(string name, string value)
    {
        try
        {
            Console.WriteLine($"[Cloudflare] Creating TXT record: {name} = {value}");
            
            var payload = new
            {
                type = "TXT",
                name = name,
                content = value,
                ttl = 120 // 2 minutes TTL for faster propagation
            };

            var json = JsonSerializer.Serialize(payload);
            var content = new StringContent(json, Encoding.UTF8, "application/json");
            
            var response = await _httpClient.PostAsync($"zones/{_zoneId}/dns_records", content);
            var responseBody = await response.Content.ReadAsStringAsync();
            
            if (response.IsSuccessStatusCode)
            {
                var result = JsonSerializer.Deserialize<JsonElement>(responseBody);
                if (result.TryGetProperty("result", out var resultObj) && resultObj.TryGetProperty("id", out var idProp))
                {
                    var recordId = idProp.GetString();
                    _recordIds[name] = recordId!;
                    Console.WriteLine($"[Cloudflare] TXT record created successfully. ID: {recordId}");
                }
            }
            else
            {
                throw new InvalidOperationException($"Cloudflare API error: {response.StatusCode} - {responseBody}");
            }
        }
        catch (Exception ex)
        {
            Console.WriteLine($"[Cloudflare] Error creating TXT record: {ex.Message}");
            throw;
        }
    }

    public async Task DeleteTxtRecord(string name, string value)
    {
        try
        {
            if (_recordIds.TryGetValue(name, out var recordId))
            {
                Console.WriteLine($"[Cloudflare] Deleting TXT record: {name} (ID: {recordId})");
                var response = await _httpClient.DeleteAsync($"zones/{_zoneId}/dns_records/{recordId}");
                
                if (response.IsSuccessStatusCode)
                {
                    _recordIds.Remove(name);
                    Console.WriteLine($"[Cloudflare] TXT record deleted successfully.");
                }
                else
                {
                    var responseBody = await response.Content.ReadAsStringAsync();
                    Console.WriteLine($"[Cloudflare] Warning: Failed to delete DNS record: {response.StatusCode} - {responseBody}");
                }
            }
            else
            {
                Console.WriteLine($"[Cloudflare] No record ID found for {name}, skipping deletion.");
            }
        }
        catch (Exception ex)
        {
            Console.WriteLine($"[Cloudflare] Warning: Error deleting TXT record: {ex.Message}");
        }
    }
}
