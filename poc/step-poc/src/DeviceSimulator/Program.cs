using DeviceSimulator.Services;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using Serilog;
using Serilog.Events;
using Prometheus;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Http;

namespace DeviceSimulator;

class Program
{
    static async Task Main(string[] args)
    {
        // Configure Serilog for structured logging to Loki
        Log.Logger = new LoggerConfiguration()
            .MinimumLevel.Information()
            .MinimumLevel.Override("Microsoft", LogEventLevel.Warning)
            .Enrich.FromLogContext()
            .Enrich.WithProperty("service", "device-simulator")
            .Enrich.WithProperty("device_id", "centrifuge-001")
            .WriteTo.Console()
            .WriteTo.Http(
                requestUri: Environment.GetEnvironmentVariable("LOKI_URL") ?? "http://loki:3100/loki/api/v1/push",
                queueLimitBytes: null,
                textFormatter: new Serilog.Formatting.Compact.CompactJsonFormatter())
            .CreateLogger();

        try
        {
            Log.Information("Starting Blood Separator Centrifuge Device Simulator");

            var host = CreateHostBuilder(args).Build();
            
            // Start the simulator service
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
    }

    static IHostBuilder CreateHostBuilder(string[] args) =>
        Host.CreateDefaultBuilder(args)
            .UseSerilog()
            .ConfigureWebHostDefaults(webBuilder =>
            {
                webBuilder.Configure(app =>
                {
                    app.UseRouting();
                    app.UseHttpMetrics();
                    
                    app.UseEndpoints(endpoints =>
                    {
                        endpoints.MapMetrics();
                        endpoints.MapGet("/health", async context =>
                        {
                            var healthService = context.RequestServices.GetRequiredService<IHealthService>();
                            var health = healthService.GetHealthStatus();
                            
                            context.Response.ContentType = "application/json";
                            context.Response.StatusCode = health.Status == "Healthy" ? 200 : 
                                                        health.Status.StartsWith("Degraded") ? 200 : 503;
                            
                            await context.Response.WriteAsync(System.Text.Json.JsonSerializer.Serialize(health, new System.Text.Json.JsonSerializerOptions 
                            { 
                                PropertyNamingPolicy = System.Text.Json.JsonNamingPolicy.CamelCase,
                                WriteIndented = true 
                            }));
                        });
                        
                        endpoints.MapGet("/", async context =>
                        {
                            await context.Response.WriteAsync("Blood Separator Centrifuge Device Simulator - Phase 3.2 Observability");
                        });
                    });
                });
                
                webBuilder.UseUrls("http://0.0.0.0:8080");
            })
            .ConfigureServices((context, services) =>
            {
                services.AddSingleton<ICertificateManager, CertificateManager>();
                services.AddSingleton<IMqttService, MqttService>();
                services.AddSingleton<ITelemetryGenerator, CentrifugeTelemetryGenerator>();
                services.AddSingleton<IMetricsService, MetricsService>();
                services.AddSingleton<IHealthService, HealthService>();
                services.AddHostedService<DeviceSimulatorService>();
            });
}