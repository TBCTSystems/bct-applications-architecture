using System.Security.Cryptography.X509Certificates;
using System.Text;
using System.Text.Json;
using Serilog;
using Serilog.Events;
using VaultSharp;
using VaultSharp.V1.AuthMethods;
using VaultSharp.V1.AuthMethods.Cert;

namespace VaultDemo.AuthWithTLSV2;

public static class Program
{
   private const string CertPath = "certs/client.pfx";
   private const string CertPassword = "";
   private const string VaultAddress = "https://127.0.0.1:8200/";

   public static async Task Main(string[] args)
   {
      // Configure Serilog
      Log.Logger = new LoggerConfiguration()
         .MinimumLevel.Override("Microsoft", LogEventLevel.Warning) // Suppress noisy logs
         .Enrich.FromLogContext()
         .WriteTo.Console()
         .CreateLogger();

      await UseHttpClient();
      await UseVaultSharp();
   }

   private static async Task UseHttpClient()
   {
      // 1) Create an HttpClientHandler that uses our client certificate
      var handler = new HttpClientHandler();
      handler.ClientCertificates.Add(
         new X509Certificate2(CertPath,
            CertPassword,
            X509KeyStorageFlags.DefaultKeySet));

      // 2) Optionally trust all server certs, or do a custom check
      //    In production, better to import 'ca.crt' into the machine store
      //    or do a proper check. For a POC:
      handler.ServerCertificateCustomValidationCallback =
         (message, cert, chain, errors) => true;

      // 3) Create HttpClient
      using var client = new HttpClient(handler);
      client.BaseAddress = new Uri(VaultAddress);

      // 4) Cert Auth: POST /v1/auth/cert/login
      var loginRequest = new StringContent("{}", Encoding.UTF8, "application/json");
      var loginResponse = await client.PostAsync("v1/auth/cert/login", loginRequest);
      loginResponse.EnsureSuccessStatusCode();

      var loginContent = await loginResponse.Content.ReadAsStringAsync();

      // 5) Parse JSON to extract client_token
      string vaultToken;
      using var doc = JsonDocument.Parse(loginContent);
      vaultToken = doc.RootElement
         .GetProperty("auth")
         .GetProperty("client_token")
         .GetString();

      Console.WriteLine($"Got Vault token: {vaultToken}");

      // 6) Use the token to read secret
      var secretRequest = new HttpRequestMessage(HttpMethod.Get, "v1/secret/data/hello");
      secretRequest.Headers.Add("X-Vault-Token", vaultToken);

      var secretResponse = await client.SendAsync(secretRequest);
      secretResponse.EnsureSuccessStatusCode();

      var secretJson = await secretResponse.Content.ReadAsStringAsync();
      Console.WriteLine($"Secret JSON: {secretJson}");
   }

   private static async Task UseVaultSharp()
   {
      // Vault Secret Path and mount
      const string secretPath = "hello"; // The path within the mount
      const string secretMountPoint = "secret"; // The mount point of the secrets engine

      // Load the Certificate
      var certificate = new X509Certificate2(CertPath, CertPassword, X509KeyStorageFlags.DefaultKeySet);

      // Vault Authentication
      IAuthMethodInfo authMethod = new CertAuthMethodInfo(certificate);

      // Initialize Vault client settings and provide a custom HttpClient provider.
      // This delegate receives the default handler and returns an HttpClient that uses it.
      // Here we check if the provided handler is an HttpClientHandler and override the certificate validation.
      var vaultClientSettings = new VaultClientSettings(VaultAddress, authMethod)
      {
         MyHttpClientProviderFunc = (handler) =>
         {
            if (handler is HttpClientHandler httpClientHandler)
            {
               // Bypass SSL certificate validation (only for dev environments!)
               httpClientHandler.ServerCertificateCustomValidationCallback =
                  (message, cert, chain, errors) => true;
            }
            // It's essential to use the provided handler to preserve certificate authentication.
            return new HttpClient(handler);
         }

         // You can set other settings if necessary, e.g.:
         // VaultServiceTimeout = TimeSpan.FromSeconds(100),
      };
      
      // // Initialize settings.  Use VaultAddress, and provide the authentication method.
      // var vaultClientSettings = new VaultClientSettings(VaultAddress, authMethod)
      // {
      //    //if you are not using https, then you can disable it.
      //    //VaultServiceTimeout = TimeSpan.FromSeconds(100),  // Optional timeout.
      //    //ContinueAsyncTasksOnCapturedContext = false,  // Often improves performance.
      // };

      IVaultClient vaultClient = new VaultClient(vaultClientSettings);

      var secret = await vaultClient.V1.Secrets.KeyValue.V2.ReadSecretAsync(secretPath, mountPoint: secretMountPoint);

      Log.Logger.Information("Content: {@Secret}", secret.Data.Data);
   }
}