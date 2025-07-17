using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;

namespace ReveosSimpleMocker.Services;

public class ReveosDeviceService : BackgroundService
{
    private readonly ICertificateManager _certificateManager;
    private readonly IMqttService _mqttService;
    private readonly IDeviceSimulator _deviceSimulator;
    private readonly ILogger<ReveosDeviceService> _logger;
    private readonly string _deviceId;

    public ReveosDeviceService(
        ICertificateManager certificateManager,
        IMqttService mqttService,
        IDeviceSimulator deviceSimulator,
        ILogger<ReveosDeviceService> logger)
    {
        _certificateManager = certificateManager;
        _mqttService = mqttService;
        _deviceSimulator = deviceSimulator;
        _logger = logger;
        _deviceId = Environment.GetEnvironmentVariable("Device__Id") ?? "REVEOS-SIM-001";
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        _logger.LogInformation("🤖 Reveos Device Service starting for device {DeviceId}...", _deviceId);

        try
        {
            // Initialize certificate management
            await _certificateManager.InitializeAsync();
            
            // Start MQTT service
            await _mqttService.StartAsync();
            
            // Start device simulation
            await _deviceSimulator.StartAsync();
            
            _logger.LogInformation("✅ Reveos Device Service started successfully");

            // Main device loop
            while (!stoppingToken.IsCancellationRequested)
            {
                try
                {
                    // Check certificate status
                    await _certificateManager.CheckCertificateStatusAsync();
                    
                    // Simulate device operations
                    await _deviceSimulator.SimulateDeviceOperationsAsync();
                    
                    // Wait for next iteration
                    await Task.Delay(TimeSpan.FromSeconds(30), stoppingToken);
                }
                catch (OperationCanceledException)
                {
                    // Expected when cancellation is requested
                    break;
                }
                catch (Exception ex)
                {
                    _logger.LogError(ex, "Error in device main loop");
                    await Task.Delay(TimeSpan.FromSeconds(10), stoppingToken);
                }
            }
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Fatal error in Reveos Device Service");
            throw;
        }
        finally
        {
            await _deviceSimulator.StopAsync();
            await _mqttService.StopAsync();
            _logger.LogInformation("🛑 Reveos Device Service stopped");
        }
    }
}