using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Serilog;
using Serilog.Events;
using VaultDemo.Console.Examples;
using VaultDemo.Console.Factories;
using VaultDemo.Console.Models;
using VaultDemo.Console.Services;

var builder = Host.CreateApplicationBuilder(args);
var config = builder.Configuration;

// Configure Serilog
Log.Logger = new LoggerConfiguration()
   .MinimumLevel.Override("Microsoft", LogEventLevel.Warning) // Suppress noisy logs
   .Enrich.FromLogContext()
   .WriteTo.Console()
   .CreateLogger();

// Add configuration sources
config.AddJsonFile("appsettings.json", optional: true, reloadOnChange: true);

// Load Vault config
var vaultConfig = config.GetSection("Vault").Get<VaultConfiguration>();
Log.Logger.Information("Vault configuration loaded: {@VaultConfig}", vaultConfig);

// Register Vault client as a singleton so it can be injected anywhere
builder.Services.AddSingleton(new VaultClientFactory().CreateVaultClient(vaultConfig));
builder.Services.AddSingleton<IVaultService, VaultService>();

// Register the example runner
builder.Services.AddSingleton<VaultSecretEngineExamples>();

// Add Serilog to the logging pipeline
builder.Logging.AddSerilog(); 

var host = builder.Build();

// Run examples
var exampleRunner = host.Services.GetRequiredService<VaultSecretEngineExamples>();
await exampleRunner.RunExamplesAsync();

Log.CloseAndFlush();