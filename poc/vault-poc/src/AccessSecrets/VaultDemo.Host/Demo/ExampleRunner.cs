using VaultDemo.Host.Models;
using VaultDemo.Host.Services;

namespace VaultDemo.Host.Demo;

public class ExampleRunner(ISecretService secretService, ILogger<ExampleRunner> logger)
{
   public async Task RunAsync()
   {
      await GetStringSecretAsync();
      await GetObjectSecret();
   }
   
   private async Task GetStringSecretAsync()
   {
      // Get the secret from Vault
      logger.LogInformation("Fetching string secret from Vault...");
      var secret = await secretService.GetSimpleSecretAsync(path: "demo/config", key: "ApplicationName");

      // Print the secret to the console
      logger.LogInformation("ApplicationName: {ApplicationName}", secret);
   }
   
   private async Task GetObjectSecret()
   {
      // Get the secret from Vault
      logger.LogInformation("Fetching string secret from Vault...");
      var secret = await secretService.GetSecretAsync<DatabaseConfig>(path: "demo/config", key: "Persistence");

      // Print the secret to the console
      logger.LogInformation("Persistence Config: {@DatabaseConfig}", secret);
   }
}