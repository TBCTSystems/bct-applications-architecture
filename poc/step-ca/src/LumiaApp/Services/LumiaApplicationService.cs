using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;

namespace LumiaApp.Services;

public class LumiaApplicationService : BackgroundService
{
    private readonly ICertificateManager _certificateManager;
    private readonly IMqttService _mqttService;
    private readonly ILogger<LumiaApplicationService> _logger;

    public LumiaApplicationService(
        ICertificateManager certificateManager,
        IMqttService mqttService,
        ILogger<LumiaApplicationService> logger)
    {
        _certificateManager = certificateManager;
        _mqttService = mqttService;
        _logger = logger;
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        _logger.LogInformation("🚀 Lumia Application Service starting...");

        try
        {
            // Initialize certificate management
            await _certificateManager.InitializeAsync();
            
            // Start MQTT service
            await _mqttService.StartAsync();
            
            _logger.LogInformation("✅ Lumia Application Service started successfully");

            // Main application loop
            while (!stoppingToken.IsCancellationRequested)
            {
                try
                {
                    // Check certificate status
                    await _certificateManager.CheckCertificateStatusAsync();
                    
                    // Send periodic heartbeat via MQTT
                    await _mqttService.PublishHeartbeatAsync();
                    
                    // Wait for next iteration
                    await Task.Delay(TimeSpan.FromMinutes(1), stoppingToken);
                }
                catch (OperationCanceledException)
                {
                    // Expected when cancellation is requested
                    break;
                }
                catch (Exception ex)
                {
                    _logger.LogError(ex, "Error in main application loop");
                    await Task.Delay(TimeSpan.FromSeconds(30), stoppingToken);
                }
            }
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Fatal error in Lumia Application Service");
            throw;
        }
        finally
        {
            await _mqttService.StopAsync();
            _logger.LogInformation("🛑 Lumia Application Service stopped");
        }
    }
}