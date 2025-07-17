using LumiaApp.Services;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Serilog;

Log.Logger = new LoggerConfiguration()
    .WriteTo.Console()
    .WriteTo.File("logs/lumia-app-.txt", rollingInterval: RollingInterval.Day)
    .CreateLogger();

try
{
    Log.Information("🌟 Starting Lumia 1.1 Application...");

    var builder = Host.CreateApplicationBuilder(args);
    
    builder.Services.AddSerilog();
    
    // Register services
    builder.Services.AddSingleton<ICertificateManager, CertificateManager>();
    builder.Services.AddSingleton<IMqttService, MqttService>();
    builder.Services.AddSingleton<IProvisioningClient, ProvisioningClient>();
    
    // Register the main application service
    builder.Services.AddHostedService<LumiaApplicationService>();

    var host = builder.Build();
    
    await host.RunAsync();
}
catch (Exception ex)
{
    Log.Fatal(ex, "Application terminated unexpectedly");
}
finally
{
    Log.CloseAndFlush();
}