namespace VaultDemo.Console.Services;

/// <summary>
/// Service for interacting with HashiCorp Vault using VaultSharp.
/// Provides methods to read and write secrets using the Key-Value (KV) v2 secrets engine.
/// </summary>
public interface IVaultService
{
   /// <summary>
   /// Retrieves a secret from Vault and deserializes it to the specified type.
   /// </summary>
   /// <typeparam name="T">The expected return type.</typeparam>
   /// <param name="path">Path in Vault where the secret is stored.</param>
   /// <param name="key">Key of the secret value to retrieve.</param>
   /// <returns>The secret value deserialized into the requested type.</returns>
   Task<T> GetSecretAsync<T>(string path, string key);
   
   /// <summary>
   /// Retrieves a secret from Vault as a string.
   /// </summary>
   /// <param name="path">Path in Vault where the secret is stored.</param>
   /// <param name="key">Key of the secret value to retrieve.</param>
   /// <returns>The secret value as a string, or null if not found.</returns>
   Task<string> GetSimpleSecretAsync(string path, string key); 
   
   /// <summary>
   /// Writes a secret to Vault.
   /// </summary>
   /// <typeparam name="T">Type of the value being stored.</typeparam>
   /// <param name="path">Path in Vault where the secret should be stored.</param>
   /// <param name="key">Key under which the secret should be stored.</param>
   /// <param name="value">Value to store in Vault.</param>
   Task WriteSecretAsync<T>(string path, string key, T value);
}