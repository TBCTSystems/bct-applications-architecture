using System.Security.Cryptography.X509Certificates;
using VaultSharp;
using VaultSharp.V1.AuthMethods.Cert;

namespace OpenBaoSecretDemo
{
    class Program
    {
        static async Task Main(string[] args)
        {
            var baoServerUrl = "https://127.0.0.1:8200"; // TODO: GetEnvironmentVariable()
            var certPath = Environment.GetEnvironmentVariable("CLIENT_CERT_PATH"); // path to client.pfx;
            var certPassword = Environment.GetEnvironmentVariable("CLIENT_CERT_PASSWORD"); // passwoord when creating client.pfx (e.g.,"pfxpwd");
            
            var secretPath = "myapp/mysecrets"; // Note myapp is the path from myapp-policy.hcl where permission is granted

            var secretKey = "myuser";
            var secretValue = "MySupersecret123!";

            try
            {
                IVaultClient vaultClient = CreateVaultClient(baoServerUrl, certPath, certPassword);
                
                // Store secret
                await StoreSecretAsync(vaultClient, secretPath, secretKey, secretValue);
                Console.WriteLine("Secret stored successfully!");

                // Retrieve secret
                var retrievedValue = await RetrieveSecretAsync(vaultClient, secretPath, secretKey);
                Console.WriteLine($"Retrieved secret value: {retrievedValue}");
            }
            catch (Exception ex)
            {
                Console.WriteLine($"Error: {ex.Message}");
            }
        }

        private static IVaultClient CreateVaultClient(string serverUrl, string certPath, string certPassword)
        {
            var clientCert = new X509Certificate2(certPath, certPassword);
            var httpHandler = new HttpClientHandler
            {
                ClientCertificates = { clientCert },
                ServerCertificateCustomValidationCallback = (message, cert, chain, errors) => true
            };

            var authMethod = new CertAuthMethodInfo(clientCert);
            var vaultClientSettings = new VaultClientSettings(serverUrl, authMethod)
            {
                Namespace = "", // Set if using Vault namespaces
                MyHttpClientProviderFunc = handler => new HttpClient(httpHandler)
            };

            return new VaultClient(vaultClientSettings);
        }

        private static async Task StoreSecretAsync(IVaultClient client, string path, string key, string value)
        {
            await client.V1.Secrets.KeyValue.V2.WriteSecretAsync(
                path: path,
                data: new Dictionary<string, object> { { key, value } },
                mountPoint: "secret"
            );
        }

        private static async Task<string> RetrieveSecretAsync(IVaultClient client, string path, string key)
        {
            var secret = await client.V1.Secrets.KeyValue.V2.ReadSecretAsync(
                path: path,
                mountPoint: "secret"
            );

            return secret.Data.Data[key].ToString();
        }
    }
}