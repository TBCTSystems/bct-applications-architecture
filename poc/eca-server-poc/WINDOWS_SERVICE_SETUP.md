# EdgeCertAgent Windows Service Setup Guide

This guide explains how to install and configure the EdgeCertAgent as a Windows Service for automated certificate management.

## Prerequisites

- .NET 8 SDK installed
- Administrator privileges
- Step CA running (Docker or standalone)
- Cloudflare API token and Zone ID

## Step 1: Install Step CA Root Certificate

Before installing the service, you must install the Step CA root certificate into the Windows Trusted Root Certificate Store so Windows trusts certificates issued by your Step CA.

```powershell
# Run as Administrator
$cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2("c:\Projects\bct-applications-architecture\poc\eca-server-poc\stepca\step\certs\root_ca.crt")
$store = New-Object System.Security.Cryptography.X509Certificates.X509Store("Root","LocalMachine")
$store.Open("ReadWrite")
$store.Add($cert)
$store.Close()
Write-Host "Step CA root certificate installed successfully!"
```

## Step 2: Configure Settings

Edit `EdgeCertAgent.WindowsService\appsettings.json`:

```json
{
  "ServiceSettings": {
    "StepCaUrl": "https://localca.example.com:9443/acme/acme/directory",
    "Domains": [
      "yourdomain.example.com"
    ],
    "ValidityDays": 30,
    "RenewalThreshold": 0.75,
    "CertificateOutputPath": "C:\\EdgeCertAgent\\Certificates",
    "AccountEmail": "admin@example.com",
    "Insecure": false,
    "CheckIntervalHours": 24,
    "CloudflareApiToken": "your-cloudflare-api-token",
    "CloudflareZoneId": "your-cloudflare-zone-id"
  }
}
```

**Key settings:**
- `StepCaUrl`: Your Step CA ACME directory endpoint
- `Domains`: List of domains to manage certificates for
- `CheckIntervalHours`: How often to check certificates (24 = once per day)
- `RenewalThreshold`: Renew when certificate reaches this percentage of lifetime (0.75 = 75%)
- `Insecure`: Set to `false` for secure SSL validation (recommended after installing root cert)

## Step 3: Publish the Service

```powershell
cd "c:\Projects\bct-applications-architecture\poc\eca-server-poc\EdgeCertAgent.WindowsService"
dotnet publish -c Release -r win-x64 --self-contained -o "C:\EdgeCertAgent"
```

This creates a self-contained executable at `C:\EdgeCertAgent\EdgeCertAgent.WindowsService.exe`.

## Step 4: Create Windows Service

```powershell
# Run as Administrator
sc create "EdgeCertAgent" binPath="C:\EdgeCertAgent\EdgeCertAgent.WindowsService.exe" start=auto
```

## Step 5: Start the Service

```powershell
Start-Service EdgeCertAgent
```

## Step 6: Verify Service is Running

```powershell
Get-Service EdgeCertAgent
```

Should show:
```
Status   Name               DisplayName
------   ----               -----------
Running  EdgeCertAgent      EdgeCertAgent
```

## Step 7: Check Certificates

Wait about 1-2 minutes, then check if certificates were created:

```powershell
Get-ChildItem "C:\EdgeCertAgent\Certificates" -Recurse
```

You should see for each domain:
- `account.pem` - ACME account key (ES256)
- `cert.pem` - SSL certificate
- `key.pem` - Private key (RS256)
- `ca.pem` - CA certificate chain

## Managing the Service

### Stop the service
```powershell
Stop-Service EdgeCertAgent
```

### Restart the service
```powershell
Restart-Service EdgeCertAgent
```

### Check service status
```powershell
Get-Service EdgeCertAgent
```

### View service logs
```powershell
Get-WinEvent -FilterHashtable @{LogName='Application'; ProviderName='*EdgeCertAgent*'} -MaxEvents 10
```

### Uninstall the service
```powershell
Stop-Service EdgeCertAgent
sc delete "EdgeCertAgent"
```

## Reinstalling After Updates

If you make code changes and need to reinstall:

```powershell
# 1. Stop and delete the service
Stop-Service EdgeCertAgent
sc delete "EdgeCertAgent"

# 2. Republish
cd "c:\Projects\bct-applications-architecture\poc\eca-server-poc\EdgeCertAgent.WindowsService"
dotnet publish -c Release -r win-x64 --self-contained -o "C:\EdgeCertAgent"

# 3. Recreate and start
sc create "EdgeCertAgent" binPath="C:\EdgeCertAgent\EdgeCertAgent.WindowsService.exe" start=auto
Start-Service EdgeCertAgent
```

## Troubleshooting

### Service won't start
- Check Event Viewer: `Get-WinEvent -FilterHashtable @{LogName='Application'} -MaxEvents 20`
- Verify `appsettings.json` exists in `C:\EdgeCertAgent\`
- Ensure Step CA is running and accessible

### SSL Certificate Validation Errors
- Verify Step CA root certificate is installed in Windows Trusted Root Certificate Store
- Run: `Get-ChildItem -Path Cert:\LocalMachine\Root | Where-Object {$_.Subject -like "*Local CA*"}`
- If not found, reinstall the root certificate (Step 1)

### Certificates not being created
- Check Cloudflare API token has DNS edit permissions
- Verify Zone ID is correct
- Check DNS propagation (service waits 30 seconds)
- Review service logs for specific errors

### Force certificate renewal for testing
```powershell
# Delete existing certificates
Remove-Item "C:\EdgeCertAgent\Certificates\*\cert.pem", "C:\EdgeCertAgent\Certificates\*\key.pem" -Force

# Restart service to trigger renewal
Restart-Service EdgeCertAgent

# Wait 1-2 minutes and check
Get-ChildItem "C:\EdgeCertAgent\Certificates" -Recurse
```

## Certificate Renewal Behavior

- Service checks certificates on startup (immediately)
- Then checks every `CheckIntervalHours` (default: 24 hours)
- Renews certificate when it reaches `RenewalThreshold` of its lifetime (default: 75%)
- For 30-day certificates with 75% threshold, renewal happens at 22.5 days
- Uses DNS-01 challenge with Cloudflare for validation

## Security Considerations

1. **Protect Cloudflare API Token**: Store securely, limit to DNS edit permissions only
2. **Certificate Storage**: Files in `C:\EdgeCertAgent\Certificates\` contain private keys
3. **Service Account**: Consider running service under dedicated service account (not SYSTEM)
4. **Root Certificate**: Only install Step CA root certificate if you control the CA
5. **Insecure Mode**: Never use `"Insecure": true` in production environments
