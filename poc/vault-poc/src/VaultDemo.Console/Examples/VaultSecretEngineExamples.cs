using Microsoft.Extensions.Logging;
using VaultDemo.Console.Models;
using VaultDemo.Console.Services;

namespace VaultDemo.Console.Examples;

public class VaultSecretEngineExamples(IVaultService vaultService, ILogger<VaultSecretEngineExamples> logger)
{
    public async Task RunExamplesAsync()
    {
        await InsertAndRetrieveSimpleSecretAsync();
        await InsertAndRetrieveDatabaseConfigAsync();
    }
    
    /// <summary>
    /// Example: Write and then read a simple key-value pair (e.g., "appName"="MyApplication").
    /// </summary>
    private async Task InsertAndRetrieveSimpleSecretAsync()
    {
        const string path = "myapp/config";
        const string key = "appName";
        const string value = "MyApplication";

        // 1. Write the secret
        await vaultService.WriteSecretAsync(path, key, value);

        // 2. Read the secret
        var retrievedValue = await vaultService.GetSimpleSecretAsync(path, key);

        if (retrievedValue != null)
        {
            logger.LogInformation("Successfully retrieved: {Key} = {Value}", key, retrievedValue);
        }
        else
        {
            logger.LogWarning("Failed to retrieve secret for {Key} in {Path}", key, path);
        }
    }

    /// <summary>
    /// Example: Write and then read a structured object (DatabaseConfig) as JSON.
    /// </summary>
    private async Task InsertAndRetrieveDatabaseConfigAsync()
    {
        const string path = "myapp/dbconfig";
        const string key = "dbConfig";
        
        var dbConfig = new DatabaseConfig
        {
            Username = "dbuser",
            Password = "supersecret",
            Host = "localhost",
            Port = 5432,
            Database = "myDatabase"
        };

        // 1. Write the database config
        await vaultService.WriteSecretAsync(path, key, dbConfig);

        // 2. Read the database config
        var retrievedConfig = await vaultService.GetSecretAsync<DatabaseConfig>(path, key);

        if (retrievedConfig != null)
        {
            logger.LogInformation("Successfully retrieved DatabaseConfig: {@DataBaseConfig}", retrievedConfig);
        }
        else
        {
            logger.LogWarning("Failed to retrieve DatabaseConfig in {Path} for key={Key}", path, key);
        }
    }
}