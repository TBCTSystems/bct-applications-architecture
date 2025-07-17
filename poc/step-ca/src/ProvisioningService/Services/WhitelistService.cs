using System.Collections.Concurrent;
using System.Net;

namespace ProvisioningService.Services;

public class WhitelistService : IWhitelistService
{
    private readonly ConcurrentDictionary<string, bool> _whitelist = new();
    private readonly ILogger<WhitelistService> _logger;

    public WhitelistService(ILogger<WhitelistService> logger)
    {
        _logger = logger;
        
        // Add some default IPs for demo purposes
        AddIP("127.0.0.1");
        AddIP("::1");
        AddIP("172.20.0.0/16"); // Docker network range
    }

    public bool IsWhitelisted(string ipAddress)
    {
        if (string.IsNullOrEmpty(ipAddress))
            return false;

        // Check exact match first
        if (_whitelist.ContainsKey(ipAddress))
            return true;

        // Check CIDR ranges
        foreach (var whitelistedEntry in _whitelist.Keys)
        {
            if (IsIpInRange(ipAddress, whitelistedEntry))
                return true;
        }

        return false;
    }

    public void AddIP(string ipAddress)
    {
        if (string.IsNullOrEmpty(ipAddress))
            return;

        _whitelist.TryAdd(ipAddress, true);
        _logger.LogInformation("Added {IpAddress} to whitelist", ipAddress);
    }

    public void RemoveIP(string ipAddress)
    {
        if (string.IsNullOrEmpty(ipAddress))
            return;

        _whitelist.TryRemove(ipAddress, out _);
        _logger.LogInformation("Removed {IpAddress} from whitelist", ipAddress);
    }

    public void ClearWhitelist()
    {
        _whitelist.Clear();
        _logger.LogInformation("Whitelist cleared");
    }

    public List<string> GetWhitelistedIPs()
    {
        return _whitelist.Keys.ToList();
    }

    private bool IsIpInRange(string ipAddress, string cidrRange)
    {
        try
        {
            if (!cidrRange.Contains('/'))
                return ipAddress == cidrRange;

            var parts = cidrRange.Split('/');
            if (parts.Length != 2)
                return false;

            var networkAddress = IPAddress.Parse(parts[0]);
            var prefixLength = int.Parse(parts[1]);
            var targetAddress = IPAddress.Parse(ipAddress);

            if (networkAddress.AddressFamily != targetAddress.AddressFamily)
                return false;

            var networkBytes = networkAddress.GetAddressBytes();
            var targetBytes = targetAddress.GetAddressBytes();

            var bytesToCheck = prefixLength / 8;
            var bitsToCheck = prefixLength % 8;

            // Check full bytes
            for (int i = 0; i < bytesToCheck; i++)
            {
                if (networkBytes[i] != targetBytes[i])
                    return false;
            }

            // Check remaining bits
            if (bitsToCheck > 0 && bytesToCheck < networkBytes.Length)
            {
                var mask = (byte)(0xFF << (8 - bitsToCheck));
                if ((networkBytes[bytesToCheck] & mask) != (targetBytes[bytesToCheck] & mask))
                    return false;
            }

            return true;
        }
        catch
        {
            return false;
        }
    }
}