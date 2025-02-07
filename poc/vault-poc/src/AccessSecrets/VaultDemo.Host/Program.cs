using Serilog;
using Serilog.Events;
using VaultDemo.Host.Demo;
using VaultDemo.Host.Services;
using VaultSharp;
using VaultSharp.V1.AuthMethods;
using VaultSharp.V1.AuthMethods.Token;

var builder = Host.CreateApplicationBuilder(args);
var config = builder.Configuration;

// Configure Serilog
Log.Logger = new LoggerConfiguration()
   .MinimumLevel.Override("Microsoft", LogEventLevel.Warning) // Suppress noisy logs
   .Enrich.FromLogContext()
   .WriteTo.Console()
   .CreateLogger();

config.AddJsonFile("appsettings.json", optional: true, reloadOnChange: true);

// Load Vault settings from environment variables or configuration
var vaultAddress = config["Vault:Address"];
var vaultToken = config["Vault:DEV_ROOT_TOKEN_ID"]; // Temporary for dev, will improve this later

// Set up Vault client
IAuthMethodInfo authMethod = new TokenAuthMethodInfo(vaultToken);
IVaultClient vaultClient = new VaultClient(new VaultClientSettings(vaultAddress, authMethod));

builder.Logging.AddSerilog(); 

// Register Vault client as a singleton so it can be injected anywhere
builder.Services.AddSingleton(vaultClient);
builder.Services.AddSingleton<ISecretService, VaultService>();

builder.Services.AddSingleton<ExampleRunner>();


var host = builder.Build();

var exampleRunner = host.Services.GetRequiredService<ExampleRunner>();
await exampleRunner.RunAsync();

Log.CloseAndFlush();