using System.Text.Json;
using VaultSharp;

namespace VaultDemo.Host.Services;

public interface ISecretService
{
   Task<T> GetSecretAsync<T>(string path, string key);
   Task<string> GetSimpleSecretAsync(string path, string key); // For simple values, like strings
}

public class VaultService(
   IVaultClient vaultClient, 
   ILogger<ISecretService> logger) : ISecretService
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
         Console.WriteLine($"Error fetching secret from Vault (Path: {path}, Key: {key}): {ex.Message}");
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
         Console.WriteLine($"Error fetching secret from Vault (Path: {path}, Key: {key}): {ex.Message}");
         return null;
      }
   }
}