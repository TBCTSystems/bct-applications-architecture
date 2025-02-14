using System.Text.Json;
using Microsoft.Extensions.Logging;
using VaultSharp;

namespace VaultDemo.Console.Services;

public class VaultService(
   IVaultClient vaultClient, 
   ILogger<VaultService> logger) : IVaultService
{
   public async Task<T> GetSecretAsync<T>(string path, string key)
   {
      try
      {
         // Read the secret from the specified path
         var secret = await vaultClient.V1.Secrets.KeyValue.V2.ReadSecretAsync(path, mountPoint: "secret");

         // Check if the key exists and return its value
         var value = secret.Data.Data.ContainsKey(key) ? secret.Data.Data[key]?.ToString() : null;
         if (value is null)
         {
            logger.LogWarning("Secret not found in Vault (Path: {Path}, Key: {Key})", path, key);
            return default;
         }
         return JsonSerializer.Deserialize<T>(value);
      }
      catch (Exception ex)
      {
         logger.LogError("Error fetching secret from Vault. Path: {SecretPath}, Key: {SecretKey}), Exception {ex.Message}",
            path, key, ex.Message);
         return default;
      }
   }
   
   public async Task<string> GetSimpleSecretAsync(string path, string key)
   {
      try
      {
         // Read the secret from the specified path
         var secret = await vaultClient.V1.Secrets.KeyValue.V2.ReadSecretAsync(path, mountPoint: "secret");

         // Check if the key exists and return its value
         var value = secret.Data.Data.ContainsKey(key) ? secret.Data.Data[key]?.ToString() : null;
         if (value is null)
         {
            logger.LogWarning("Secret not found in Vault (Path: {Path}, Key: {Key})", path, key);
            return null;
         }

         return value;
      }
      catch (Exception ex)
      {
         logger.LogError("Error fetching secret from Vault. Path: {SecretPath}, Key: {SecretKey}), Exception {ex.Message}",
            path, key, ex.Message);
         return null;
      }
   }
   
   public async Task WriteSecretAsync<T>(string path, string key, T value)
   {
      try
      {
         var data = new Dictionary<string, object>
         {
            { key, typeof(T) == typeof(string) ? value : JsonSerializer.Serialize(value) }
         };

         await vaultClient.V1.Secrets.KeyValue.V2.WriteSecretAsync(path, data, mountPoint: "secret");
         logger.LogInformation("Secret written to Vault. Path: {Path}, Key: {Key}", path, key);
      }
      catch (Exception ex)
      {
         logger.LogError("Error writing secret to Vault. Path: {SecretPath}, Key: {SecretKey}, Exception {Message}",
            path, key, ex.Message);
      }
   }
}