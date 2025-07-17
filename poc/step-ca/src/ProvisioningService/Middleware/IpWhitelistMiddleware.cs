using ProvisioningService.Services;

namespace ProvisioningService.Middleware;

public class IpWhitelistMiddleware
{
    private readonly RequestDelegate _next;
    private readonly IWhitelistService _whitelistService;
    private readonly ILogger<IpWhitelistMiddleware> _logger;

    public IpWhitelistMiddleware(
        RequestDelegate next,
        IWhitelistService whitelistService,
        ILogger<IpWhitelistMiddleware> logger)
    {
        _next = next;
        _whitelistService = whitelistService;
        _logger = logger;
    }

    public async Task InvokeAsync(HttpContext context)
    {
        var clientIp = GetClientIpAddress(context);
        
        // Skip whitelist check for health endpoint and admin endpoints
        if (IsExemptPath(context.Request.Path))
        {
            await _next(context);
            return;
        }

        // Check if IP is whitelisted for certificate requests
        if (context.Request.Path.StartsWithSegments("/api/provisioning/certificate"))
        {
            if (!_whitelistService.IsWhitelisted(clientIp))
            {
                _logger.LogWarning("Certificate request from non-whitelisted IP: {ClientIp}", clientIp);
                context.Response.StatusCode = 403;
                await context.Response.WriteAsync($"IP address {clientIp} is not whitelisted for certificate requests");
                return;
            }
        }

        _logger.LogDebug("Request from whitelisted IP: {ClientIp}", clientIp);
        await _next(context);
    }

    private string GetClientIpAddress(HttpContext context)
    {
        // Check for forwarded headers first (for reverse proxy scenarios)
        var forwardedFor = context.Request.Headers["X-Forwarded-For"].FirstOrDefault();
        if (!string.IsNullOrEmpty(forwardedFor))
        {
            return forwardedFor.Split(',')[0].Trim();
        }

        var realIp = context.Request.Headers["X-Real-IP"].FirstOrDefault();
        if (!string.IsNullOrEmpty(realIp))
        {
            return realIp;
        }

        // Fall back to connection remote IP
        return context.Connection.RemoteIpAddress?.ToString() ?? "unknown";
    }

    private bool IsExemptPath(PathString path)
    {
        var exemptPaths = new[]
        {
            "/health",
            "/api/provisioning/status",
            "/api/provisioning/enable",
            "/api/provisioning/disable",
            "/api/whitelist",
            "/swagger"
        };

        return exemptPaths.Any(exemptPath => path.StartsWithSegments(exemptPath));
    }
}