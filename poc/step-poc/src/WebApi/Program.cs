using WebApi.Services;
using WebApi.Hubs;
using Serilog;
using Serilog.Events;
using Prometheus;

namespace WebApi;

class Program
{
    static async Task Main(string[] args)
    {
        // Configure Serilog for structured logging to Loki
        Log.Logger = new LoggerConfiguration()
            .MinimumLevel.Information()
            .MinimumLevel.Override("Microsoft", LogEventLevel.Warning)
            .Enrich.FromLogContext()
            .Enrich.WithProperty("service", "web-api")
            .Enrich.WithProperty("component", "telemetry-api")
            .WriteTo.Console()
            .WriteTo.Http(
                requestUri: Environment.GetEnvironmentVariable("LOKI_URL") ?? "http://loki:3100/loki/api/v1/push",
                queueLimitBytes: null,
                textFormatter: new Serilog.Formatting.Compact.CompactJsonFormatter())
            .CreateLogger();

        try
        {
            Log.Information("Starting Blood Separator Centrifuge Web API");

            var builder = WebApplication.CreateBuilder(args);

            // Add services to the container
            builder.Services.AddControllers();
            builder.Services.AddEndpointsApiExplorer();
            builder.Services.AddSwaggerGen(c =>
            {
                c.SwaggerDoc("v1", new() { 
                    Title = "Blood Separator Centrifuge API", 
                    Version = "v1",
                    Description = "Real-time telemetry API for blood separator centrifuge monitoring"
                });
            });

            // Add SignalR
            builder.Services.AddSignalR();

            // Add CORS for React frontend
            builder.Services.AddCors(options =>
            {
                options.AddPolicy("AllowReactApp", policy =>
                {
                    policy.WithOrigins("http://localhost:3001", "https://localhost:3002", "http://frontend:3000")
                          .AllowAnyHeader()
                          .AllowAnyMethod()
                          .AllowCredentials();
                });
            });

            // Register services
            builder.Services.AddSingleton<ICertificateManager, CertificateManager>();
            builder.Services.AddSingleton<IMqttSubscriberService, MqttSubscriberService>();
            builder.Services.AddSingleton<ITelemetryDataService, TelemetryDataService>();
            builder.Services.AddSingleton<IMetricsService, MetricsService>();
            builder.Services.AddHostedService<MqttSubscriberBackgroundService>();

            // Use Serilog
            builder.Host.UseSerilog();

            var app = builder.Build();

            // Configure the HTTP request pipeline
            if (app.Environment.IsDevelopment())
            {
                app.UseSwagger();
                app.UseSwaggerUI(c =>
                {
                    c.SwaggerEndpoint("/swagger/v1/swagger.json", "Blood Separator Centrifuge API v1");
                    c.RoutePrefix = string.Empty; // Serve Swagger at root
                });
            }

            app.UseCors("AllowReactApp");
            // app.UseHttpsRedirection(); // Disabled for Docker deployment
            app.UseRouting();
            app.UseHttpMetrics(); // Prometheus metrics

            app.MapControllers();
            app.MapHub<TelemetryHub>("/telemetryHub");
            app.MapMetrics(); // Prometheus metrics endpoint

            // Health check endpoint
            app.MapGet("/health", (IMetricsService metricsService) =>
            {
                var health = new
                {
                    Status = "Healthy",
                    Timestamp = DateTime.UtcNow,
                    Service = "web-api",
                    Version = "1.0.0",
                    MqttConnected = metricsService.IsMqttConnected(),
                    ActiveConnections = metricsService.GetActiveSignalRConnections(),
                    TotalMessagesReceived = metricsService.GetTotalMessagesReceived()
                };
                
                return Results.Ok(health);
            });

            Log.Information("Web API starting on ports 5000 (HTTP) and 5001 (HTTPS)");
            await app.RunAsync();
        }
        catch (Exception ex)
        {
            Log.Fatal(ex, "Web API terminated unexpectedly");
        }
        finally
        {
            Log.CloseAndFlush();
        }
    }
}