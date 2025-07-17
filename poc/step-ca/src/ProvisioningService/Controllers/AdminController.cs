using Microsoft.AspNetCore.Mvc;
using ProvisioningService.Services;

namespace ProvisioningService.Controllers;

[ApiController]
[Route("admin")]
public class AdminController : ControllerBase
{
    private readonly IProvisioningService _provisioningService;
    private readonly IWhitelistService _whitelistService;
    private readonly ILogger<AdminController> _logger;

    public AdminController(
        IProvisioningService provisioningService,
        IWhitelistService whitelistService,
        ILogger<AdminController> logger)
    {
        _provisioningService = provisioningService;
        _whitelistService = whitelistService;
        _logger = logger;
    }

    [HttpGet]
    public IActionResult Index()
    {
        var html = GenerateAdminInterface();
        return Content(html, "text/html");
    }

    private string GenerateAdminInterface()
    {
        var status = _provisioningService.IsEnabled ? "Enabled" : "Disabled";
        var statusColor = _provisioningService.IsEnabled ? "#28a745" : "#dc3545";
        var whitelistedIPs = _whitelistService.GetWhitelistedIPs();

        return $@"
<!DOCTYPE html>
<html lang='en'>
<head>
    <meta charset='UTF-8'>
    <meta name='viewport' content='width=device-width, initial-scale=1.0'>
    <title>Provisioning Service Admin</title>
    <style>
        body {{
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            margin: 0;
            padding: 20px;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            min-height: 100vh;
        }}
        .container {{
            max-width: 800px;
            margin: 0 auto;
            background: white;
            border-radius: 12px;
            padding: 30px;
            box-shadow: 0 8px 32px rgba(0,0,0,0.1);
        }}
        h1 {{
            color: #333;
            text-align: center;
            margin-bottom: 30px;
        }}
        .status {{
            text-align: center;
            padding: 15px;
            border-radius: 8px;
            margin-bottom: 30px;
            font-weight: bold;
            color: white;
            background-color: {statusColor};
        }}
        .section {{
            margin-bottom: 30px;
            padding: 20px;
            border: 1px solid #e0e0e0;
            border-radius: 8px;
        }}
        .section h2 {{
            margin-top: 0;
            color: #333;
        }}
        .btn {{
            background: #007bff;
            color: white;
            border: none;
            padding: 10px 20px;
            border-radius: 5px;
            cursor: pointer;
            margin: 5px;
            text-decoration: none;
            display: inline-block;
        }}
        .btn:hover {{
            background: #0056b3;
        }}
        .btn-success {{
            background: #28a745;
        }}
        .btn-success:hover {{
            background: #1e7e34;
        }}
        .btn-danger {{
            background: #dc3545;
        }}
        .btn-danger:hover {{
            background: #c82333;
        }}
        .form-group {{
            margin-bottom: 15px;
        }}
        label {{
            display: block;
            margin-bottom: 5px;
            font-weight: bold;
        }}
        input[type='text'] {{
            width: 100%;
            padding: 8px;
            border: 1px solid #ddd;
            border-radius: 4px;
            box-sizing: border-box;
        }}
        .ip-list {{
            background: #f8f9fa;
            padding: 15px;
            border-radius: 5px;
            max-height: 200px;
            overflow-y: auto;
        }}
        .ip-item {{
            padding: 5px 0;
            border-bottom: 1px solid #e0e0e0;
        }}
        .stats {{
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
            gap: 20px;
            margin-bottom: 30px;
        }}
        .stat-card {{
            background: #f8f9fa;
            padding: 20px;
            border-radius: 8px;
            text-align: center;
        }}
        .stat-number {{
            font-size: 2em;
            font-weight: bold;
            color: #007bff;
        }}
        .stat-label {{
            color: #666;
            margin-top: 5px;
        }}
    </style>
</head>
<body>
    <div class='container'>
        <h1>🔧 Provisioning Service Administration</h1>
        
        <div class='status'>
            Service Status: {status}
        </div>

        <div class='stats'>
            <div class='stat-card'>
                <div class='stat-number'>{_provisioningService.CertificatesIssued}</div>
                <div class='stat-label'>Certificates Issued</div>
            </div>
            <div class='stat-card'>
                <div class='stat-number'>{whitelistedIPs.Count}</div>
                <div class='stat-label'>Whitelisted IPs</div>
            </div>
            <div class='stat-card'>
                <div class='stat-number'>{(_provisioningService.LastActivity?.ToString("HH:mm:ss") ?? "Never")}</div>
                <div class='stat-label'>Last Activity</div>
            </div>
        </div>

        <div class='section'>
            <h2>Service Control</h2>
            <p>Enable or disable the certificate provisioning service.</p>
            <button class='btn btn-success' onclick='enableService()'>✅ Enable Service</button>
            <button class='btn btn-danger' onclick='disableService()'>❌ Disable Service</button>
        </div>

        <div class='section'>
            <h2>IP Whitelist Management</h2>
            <p>Manage which IP addresses are allowed to request certificates.</p>
            
            <div class='form-group'>
                <label for='ipAddress'>Add IP Address:</label>
                <input type='text' id='ipAddress' placeholder='192.168.1.100 or 172.20.0.0/16'>
                <button class='btn' onclick='addIP()'>➕ Add IP</button>
            </div>

            <h3>Current Whitelist:</h3>
            <div class='ip-list'>
                {string.Join("", whitelistedIPs.Select(ip => $"<div class='ip-item'>{ip} <button class='btn btn-danger' style='padding: 2px 8px; font-size: 12px;' onclick='removeIP(\"{ip}\")'>Remove</button></div>"))}
            </div>
            
            <button class='btn btn-danger' onclick='clearWhitelist()'>🗑️ Clear All</button>
        </div>

        <div class='section'>
            <h2>Quick Actions</h2>
            <a href='/api/provisioning/status' class='btn'>📊 View API Status</a>
            <a href='/swagger' class='btn'>📚 API Documentation</a>
            <button class='btn' onclick='refreshPage()'>🔄 Refresh</button>
        </div>
    </div>

    <script>
        async function enableService() {{
            try {{
                const response = await fetch('/api/provisioning/enable', {{ method: 'POST' }});
                if (response.ok) {{
                    alert('Service enabled successfully');
                    location.reload();
                }} else {{
                    alert('Failed to enable service');
                }}
            }} catch (error) {{
                alert('Error: ' + error.message);
            }}
        }}

        async function disableService() {{
            try {{
                const response = await fetch('/api/provisioning/disable', {{ method: 'POST' }});
                if (response.ok) {{
                    alert('Service disabled successfully');
                    location.reload();
                }} else {{
                    alert('Failed to disable service');
                }}
            }} catch (error) {{
                alert('Error: ' + error.message);
            }}
        }}

        async function addIP() {{
            const ipAddress = document.getElementById('ipAddress').value.trim();
            if (!ipAddress) {{
                alert('Please enter an IP address');
                return;
            }}

            try {{
                const response = await fetch('/api/whitelist/add', {{
                    method: 'POST',
                    headers: {{ 'Content-Type': 'application/json' }},
                    body: JSON.stringify({{ ipAddress: ipAddress }})
                }});
                
                if (response.ok) {{
                    alert('IP added successfully');
                    location.reload();
                }} else {{
                    alert('Failed to add IP');
                }}
            }} catch (error) {{
                alert('Error: ' + error.message);
            }}
        }}

        async function removeIP(ipAddress) {{
            try {{
                const response = await fetch('/api/whitelist/remove', {{
                    method: 'POST',
                    headers: {{ 'Content-Type': 'application/json' }},
                    body: JSON.stringify({{ ipAddress: ipAddress }})
                }});
                
                if (response.ok) {{
                    alert('IP removed successfully');
                    location.reload();
                }} else {{
                    alert('Failed to remove IP');
                }}
            }} catch (error) {{
                alert('Error: ' + error.message);
            }}
        }}

        async function clearWhitelist() {{
            if (confirm('Are you sure you want to clear all whitelisted IPs?')) {{
                try {{
                    const response = await fetch('/api/whitelist/clear', {{ method: 'POST' }});
                    if (response.ok) {{
                        alert('Whitelist cleared successfully');
                        location.reload();
                    }} else {{
                        alert('Failed to clear whitelist');
                    }}
                }} catch (error) {{
                    alert('Error: ' + error.message);
                }}
            }}
        }}

        function refreshPage() {{
            location.reload();
        }}

        // Auto-refresh every 30 seconds
        setInterval(() => {{
            location.reload();
        }}, 30000);
    </script>
</body>
</html>";
    }
}