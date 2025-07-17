using ReveosSimpleMocker.Services;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Serilog;

Log.Logger = new LoggerConfiguration()
    .WriteTo.Console()
    .WriteTo.File("logs/reveos-simulator-.txt", rollingInterval: RollingInterval.Day)
    .CreateLogger();

try
{
    var deviceId = Environment.GetEnvironmentVariable("Device__Id") ?? "REVEOS-SIM-001";
    Log.Information("🤖 Starting Reveos Device Simulator - Device ID: {DeviceId}", deviceId);

    var builder = Host.CreateApplicationBuilder(args);
    
    builder.Services.AddSerilog();
    
    // Register services
    builder.Services.AddSingleton<ICertificateManager, CertificateManager>();
    builder.Services.AddSingleton<IMqttService, MqttService>();
    builder.Services.AddSingleton<IProvisioningClient, ProvisioningClient>();
    builder.Services.AddSingleton<IDeviceSimulator, DeviceSimulator>();
    
    // Register the main device service
    builder.Services.AddHostedService<ReveosDeviceService>();

    var host = builder.Build();
    
    await host.RunAsync();
}
catch (Exception ex)
{
    Log.Fatal(ex, "Device simulator terminated unexpectedly");
}
finally
{
    Log.CloseAndFlush();
}