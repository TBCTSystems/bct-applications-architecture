using Microsoft.AspNetCore.SignalR;
using Microsoft.Extensions.Logging;

namespace WebApi.Hubs;

public class TelemetryHub : Hub
{
    private readonly ILogger<TelemetryHub> _logger;

    public TelemetryHub(ILogger<TelemetryHub> logger)
    {
        _logger = logger;
    }

    public override async Task OnConnectedAsync()
    {
        _logger.LogInformation("Client connected to TelemetryHub: {ConnectionId}", Context.ConnectionId);
        
        // Send welcome message with connection info
        await Clients.Caller.SendAsync("ConnectionEstablished", new
        {
            ConnectionId = Context.ConnectionId,
            ConnectedAt = DateTime.UtcNow,
            Message = "Connected to Blood Separator Centrifuge Telemetry Hub"
        });

        await base.OnConnectedAsync();
    }

    public override async Task OnDisconnectedAsync(Exception? exception)
    {
        _logger.LogInformation("Client disconnected from TelemetryHub: {ConnectionId}. Exception: {Exception}", 
            Context.ConnectionId, exception?.Message);
        
        await base.OnDisconnectedAsync(exception);
    }

    // Allow clients to join specific device groups for targeted updates
    public async Task JoinDeviceGroup(string deviceId)
    {
        try
        {
            await Groups.AddToGroupAsync(Context.ConnectionId, $"device-{deviceId}");
            _logger.LogDebug("Client {ConnectionId} joined device group: {DeviceId}", Context.ConnectionId, deviceId);
            
            await Clients.Caller.SendAsync("JoinedDeviceGroup", new
            {
                DeviceId = deviceId,
                JoinedAt = DateTime.UtcNow
            });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to add client {ConnectionId} to device group {DeviceId}", 
                Context.ConnectionId, deviceId);
        }
    }

    public async Task LeaveDeviceGroup(string deviceId)
    {
        try
        {
            await Groups.RemoveFromGroupAsync(Context.ConnectionId, $"device-{deviceId}");
            _logger.LogDebug("Client {ConnectionId} left device group: {DeviceId}", Context.ConnectionId, deviceId);
            
            await Clients.Caller.SendAsync("LeftDeviceGroup", new
            {
                DeviceId = deviceId,
                LeftAt = DateTime.UtcNow
            });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to remove client {ConnectionId} from device group {DeviceId}", 
                Context.ConnectionId, deviceId);
        }
    }

    // Allow clients to join the "all devices" group for global updates
    public async Task JoinAllDevicesGroup()
    {
        try
        {
            await Groups.AddToGroupAsync(Context.ConnectionId, "all-devices");
            _logger.LogDebug("Client {ConnectionId} joined all-devices group", Context.ConnectionId);
            
            await Clients.Caller.SendAsync("JoinedAllDevicesGroup", new
            {
                JoinedAt = DateTime.UtcNow
            });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to add client {ConnectionId} to all-devices group", Context.ConnectionId);
        }
    }

    public async Task LeaveAllDevicesGroup()
    {
        try
        {
            await Groups.RemoveFromGroupAsync(Context.ConnectionId, "all-devices");
            _logger.LogDebug("Client {ConnectionId} left all-devices group", Context.ConnectionId);
            
            await Clients.Caller.SendAsync("LeftAllDevicesGroup", new
            {
                LeftAt = DateTime.UtcNow
            });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to remove client {ConnectionId} from all-devices group", Context.ConnectionId);
        }
    }

    // Ping/Pong for connection health monitoring
    public async Task Ping()
    {
        await Clients.Caller.SendAsync("Pong", DateTime.UtcNow);
    }
}