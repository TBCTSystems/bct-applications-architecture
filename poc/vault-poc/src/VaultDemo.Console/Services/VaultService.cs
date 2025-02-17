using System.Text.Json;
using Microsoft.Extensions.Logging;
using VaultSharp;

namespace VaultDemo.Console.Services;

/// <summary>
/// Service for interacting with HashiCorp Vault using VaultSharp.
/// Provides methods to read and write secrets using the Key-Value (KV) v2 secrets engine.
/// </summary>
public class VaultService(
   IVaultClient vaultClient, 
   ILogger<VaultService> logger) : IVaultService
{

   /// <inheritdoc />
   public async Task<T> GetSecretAsync<T>(string path, string key)
   {
      try
      {
         // Read the secret from Vault at the specified path
         var secret = await vaultClient.V1.Secrets.KeyValue.V2.ReadSecretAsync(path, mountPoint: "secret");

         // Check if the key exists within the retrieved data
         var value = secret.Data.Data.ContainsKey(key) ? secret.Data.Data[key]?.ToString() : null;
         if (value is null)
         {
            logger.LogWarning("Secret not found in Vault (Path: {Path}, Key: {Key})", path, key);
            return default;
         }
         
         // Deserialize the retrieved value into the requested type
         return JsonSerializer.Deserialize<T>(value);
      }
      catch (Exception ex)
      {
         // Log error and return default value if an exception occurs
         logger.LogError("Error fetching secret from Vault. Path: {SecretPath}, Key: {SecretKey}, Exception {Message}",
            path, key, ex.Message);
         return default;
      }
   }
   
   /// <inheritdoc />
   public async Task<string> GetSimpleSecretAsync(string path, string key)
   {
      try
      {
         // Read the secret from Vault at the specified path
         var secret = await vaultClient.V1.Secrets.KeyValue.V2.ReadSecretAsync(path, mountPoint: "secret");

         // Extract and return the value if the key exists
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
         // Log error and return null if an exception occurs
         logger.LogError("Error fetching secret from Vault. Path: {SecretPath}, Key: {SecretKey}, Exception {Message}",
            path, key, ex.Message);
         return null;
      }
   }
   
   /// <inheritdoc />
   public async Task WriteSecretAsync<T>(string path, string key, T value)
   {
      try
      {
         // Prepare the secret data dictionary for Vault storage
         var data = new Dictionary<string, object>
         {
            { key, typeof(T) == typeof(string) ? value : JsonSerializer.Serialize(value) }
         };

         // Write the secret to Vault at the specified path
         await vaultClient.V1.Secrets.KeyValue.V2.WriteSecretAsync(path, data, mountPoint: "secret");
         logger.LogInformation("Secret written to Vault. Path: {Path}, Key: {Key}", path, key);
      }
      catch (Exception ex)
      {
         // Log error if writing to Vault fails
         logger.LogError("Error writing secret to Vault. Path: {SecretPath}, Key: {SecretKey}, Exception {Message}",
            path, key, ex.Message);
      }
   }
}