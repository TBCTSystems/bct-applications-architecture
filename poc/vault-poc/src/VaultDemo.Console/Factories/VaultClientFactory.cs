using System.Security.Cryptography.X509Certificates;
using VaultDemo.Console.Models;
using VaultSharp;
using VaultSharp.V1.AuthMethods;
using VaultSharp.V1.AuthMethods.AppRole;
using VaultSharp.V1.AuthMethods.Cert;
using VaultSharp.V1.AuthMethods.Token;
using VaultSharp.V1.AuthMethods.UserPass;
using AuthMethod = VaultDemo.Console.Models.AuthMethod;

namespace VaultDemo.Console.Factories;

public class VaultClientFactory
{
    /// <summary>
    /// Creates an IVaultClient instance configured for different Vault authentication methods
    /// and, if needed, disables SSL certificate validation (for self-signed certs during development).
    /// </summary>
    /// <param name="configuration">Represents the user-selected Vault address and auth settings (token, app role, etc.).</param>
    /// <returns>An IVaultClient with the appropriate auth method and HTTP client handler.</returns>
    public IVaultClient CreateVaultClient(VaultConfiguration configuration)
    {
        // 1. Select which auth method VaultSharp will use based on the configuration's AuthMethod enum.
        //    Each branch instantiates the appropriate IAuthMethodInfo object for that method.
        IAuthMethodInfo authMethod = configuration.AuthMethod switch
        {
            // a) Token-based auth: Provide your Vault token directly.
            AuthMethod.Token => new TokenAuthMethodInfo(configuration.AuthToken),
            // b) User/Pass-based auth: Provide username + password credentials.
            AuthMethod.UserPass => new UserPassAuthMethodInfo(configuration.Username, configuration.Password),
            // c) AppRole-based auth: Provide a RoleId + SecretId (common in CI/CD pipelines).
            AuthMethod.AppRole => new AppRoleAuthMethodInfo(configuration.RoleId, configuration.SecretId),
            // d) TLS Certificate-based auth: Provide a path to your certificate file + its password (if any).
            AuthMethod.Cert => new CertAuthMethodInfo(
                new X509Certificate2(configuration.CertPath, configuration.CertPassword, X509KeyStorageFlags.DefaultKeySet)),
            _ => throw new ArgumentOutOfRangeException(nameof(configuration.AuthMethod), configuration.AuthMethod, "Invalid authentication method")
        };

        // 2. Configure the VaultClientSettings, which tells VaultSharp how to connect to and authenticate with Vault.
        var clientSettings = new VaultClientSettings(configuration.Address, authMethod)
        {
            // 3. Provide a custom way to create the HttpClient. 
            //    This lets us adjust the HttpClientHandler to skip SSL validation if needed.
            MyHttpClientProviderFunc = (handler) =>
            {
                // If VaultSharp gives us an HttpClientHandler, we can customize it further.
                if (handler is HttpClientHandler httpClientHandler)
                { 
                    // Disable SSL certificate validation checks for all calls to Vault
                    // // via this HttpClient (ONLY for dev or testing with self-signed certs).
                    httpClientHandler.ServerCertificateCustomValidationCallback =
                        (_, _, _, _) => true;
                }
                
                // Return a standard HttpClient using whichever handler we just configured.
                return new HttpClient(handler);
            }
        };
        
        // 4. Finally, construct and return the IVaultClient using the configured settings.
        //    This client is used throughout the app to connect and authenticate with Vault.
        return new VaultClient(clientSettings);
    }
}
