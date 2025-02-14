namespace VaultDemo.Console.Services;

public interface IVaultService
{
   // For complex values, like objects
   Task<T> GetSecretAsync<T>(string path, string key);
   
   // For simple values, like strings
   Task<string> GetSimpleSecretAsync(string path, string key); 
   
   // For adding or updating secrets
   Task WriteSecretAsync<T>(string path, string key, T value);
}