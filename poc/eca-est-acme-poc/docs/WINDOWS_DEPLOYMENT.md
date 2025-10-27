# Windows Deployment Guide

**Last Updated:** 2025-10-26
**Target:** Windows Server 2019/2022, Windows 10/11 Pro
**Status:** Production Ready

---

## Table of Contents

1. [Overview](#overview)
2. [Prerequisites](#prerequisites)
3. [PowerShell 7 Installation](#powershell-7-installation)
4. [Agent Deployment](#agent-deployment)
5. [Windows Service Configuration](#windows-service-configuration)
6. [Environment Variable Prefixing](#environment-variable-prefixing)
7. [Testing & Validation](#testing--validation)
8. [Troubleshooting](#troubleshooting)

---

## Overview

The ECA agents (ACME and EST) run as PowerShell Core 7.x scripts and can be deployed on Windows in two modes:

1. **Interactive Mode:** Run agents from PowerShell console (development/testing)
2. **Service Mode:** Run agents as Windows Services (production)

This guide covers production deployment with Windows Services, including critical configuration for multi-agent scenarios where environment variable namespacing prevents collisions.

---

## Prerequisites

### System Requirements

- **OS:** Windows Server 2019/2022 or Windows 10/11 Pro
- **RAM:** 4GB minimum, 8GB recommended
- **Disk:** 10GB free space
- **Network:** Outbound HTTPS (443, 9000, 8443) to PKI infrastructure

### Required Software

| Component | Minimum Version | Installation |
|-----------|----------------|--------------|
| PowerShell Core | 7.0+ | See [PowerShell 7 Installation](#powershell-7-installation) |
| Pester | 5.0+ | `Install-Module -Name Pester -MinimumVersion 5.0 -Force` |
| powershell-yaml | Latest | `Install-Module -Name powershell-yaml -Force` |
| Git | 2.x+ | https://git-scm.com/download/win |

---

## PowerShell 7 Installation

### Option 1: Winget (Windows 10 1809+/Windows Server 2022+)

```powershell
# Install PowerShell 7 (LTS)
winget install --id Microsoft.PowerShell --source winget

# Verify installation
pwsh --version
# Expected: PowerShell 7.4.x or later
```

### Option 2: MSI Installer (All Windows Versions)

1. Download latest PowerShell 7 MSI:
   - **64-bit:** https://aka.ms/powershell-release?tag=stable
   - **32-bit:** https://github.com/PowerShell/PowerShell/releases (select appropriate architecture)

2. Run installer with defaults:
   ```cmd
   msiexec.exe /package PowerShell-7.4.x-win-x64.msi /quiet ADD_EXPLORER_CONTEXT_MENU_OPENPOWERSHELL=1 ADD_FILE_CONTEXT_MENU_RUNPOWERSHELL=1 REGISTER_MANIFEST=1 USE_MU=1 ENABLE_MU=1
   ```

3. Verify installation:
   ```powershell
   pwsh -Command '$PSVersionTable'
   ```

### Option 3: Chocolatey

```powershell
# Install Chocolatey if not present
Set-ExecutionPolicy Bypass -Scope Process -Force
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))

# Install PowerShell 7
choco install powershell-core -y

# Verify
pwsh --version
```

---

## Agent Deployment

### 1. Clone Repository

```powershell
# Create deployment directory
New-Item -ItemType Directory -Path "C:\ECA" -Force
Set-Location "C:\ECA"

# Clone repository
git clone <repository-url> .
```

### 2. Install PowerShell Modules

```powershell
# Run as Administrator
pwsh -Command "Install-Module -Name Pester -MinimumVersion 5.0 -Force -Scope AllUsers"
pwsh -Command "Install-Module -Name powershell-yaml -Force -Scope AllUsers"
```

### 3. Configure Agent Settings

#### ACME Agent Configuration

Edit `C:\ECA\agents\acme\config.yaml`:

```yaml
pki_url: https://pki.contoso.com:9000
cert_path: C:\certs\acme\server.crt
key_path: C:\certs\acme\server.key
domain_name: web-server-01.contoso.com
renewal_threshold_pct: 75
check_interval_sec: 60
```

#### EST Agent Configuration

Edit `C:\ECA\agents\est\config.yaml`:

```yaml
pki_url: https://pki.contoso.com:9000
cert_path: C:\certs\est\client.crt
key_path: C:\certs\est\client.key
device_name: client-device-001
renewal_threshold_pct: 75
check_interval_sec: 60
# bootstrap_token: PROVIDE_VIA_ENVIRONMENT_VARIABLE
```

**Security Note:** Never store `bootstrap_token` in YAML files. Always use environment variables.

### 4. Create Certificate Directories

```powershell
# Create directories with appropriate permissions
New-Item -ItemType Directory -Path "C:\certs\acme" -Force
New-Item -ItemType Directory -Path "C:\certs\est" -Force

# Set permissions (Administrators and SYSTEM only)
$acl = Get-Acl "C:\certs"
$acl.SetAccessRuleProtection($true, $false)
$adminRule = New-Object System.Security.AccessControl.FileSystemAccessRule("Administrators", "FullControl", "ContainerInherit,ObjectInherit", "None", "Allow")
$systemRule = New-Object System.Security.AccessControl.FileSystemAccessRule("SYSTEM", "FullControl", "ContainerInherit,ObjectInherit", "None", "Allow")
$acl.AddAccessRule($adminRule)
$acl.AddAccessRule($systemRule)
Set-Acl "C:\certs" $acl
```

---

## Windows Service Configuration

### Architecture: One Service Per Agent

**Critical:** Each agent runs as a separate Windows Service to ensure:
- Independent lifecycle management
- Isolated failure domains
- Dedicated environment variable namespaces
- Service-specific monitoring

### Service Creation Scripts

#### ACME Agent Service

Save as `C:\ECA\install-acme-service.ps1`:

```powershell
#Requires -Version 7.0
#Requires -RunAsAdministrator

param(
    [string]$ServiceName = "ECA-ACME-Agent",
    [string]$DisplayName = "ECA ACME Certificate Agent",
    [string]$Description = "Automated certificate management using ACME protocol",
    [string]$AgentPath = "C:\ECA\agents\acme\agent.ps1",
    [string]$PwshPath = "C:\Program Files\PowerShell\7\pwsh.exe"
)

# Verify PowerShell 7 exists
if (-not (Test-Path $PwshPath)) {
    throw "PowerShell 7 not found at: $PwshPath"
}

# Verify agent script exists
if (-not (Test-Path $AgentPath)) {
    throw "Agent script not found at: $AgentPath"
}

# Remove existing service if present
$existingService = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
if ($existingService) {
    Write-Host "Removing existing service: $ServiceName"
    Stop-Service -Name $ServiceName -Force -ErrorAction SilentlyContinue
    sc.exe delete $ServiceName
    Start-Sleep -Seconds 2
}

# Create Windows Service using NSSM (recommended) or sc.exe
# Option 1: Using sc.exe (built-in, more complex)
$serviceBinary = "`"$PwshPath`" -NoProfile -ExecutionPolicy Bypass -File `"$AgentPath`""

sc.exe create $ServiceName `
    binPath= "$serviceBinary" `
    DisplayName= "$DisplayName" `
    start= auto `
    obj= "LocalSystem"

sc.exe description $ServiceName "$Description"

# Configure service recovery options (restart on failure)
sc.exe failure $ServiceName reset= 86400 actions= restart/60000/restart/60000/restart/60000

Write-Host "✓ Service '$ServiceName' created successfully"
Write-Host "  To start: Start-Service -Name '$ServiceName'"
Write-Host "  To check logs: Get-EventLog -LogName Application -Source '$ServiceName' -Newest 10"
```

#### EST Agent Service

Save as `C:\ECA\install-est-service.ps1` (same structure, change parameters):

```powershell
#Requires -Version 7.0
#Requires -RunAsAdministrator

param(
    [string]$ServiceName = "ECA-EST-Agent",
    [string]$DisplayName = "ECA EST Certificate Agent",
    [string]$Description = "Automated client certificate enrollment using EST protocol",
    [string]$AgentPath = "C:\ECA\agents\est\agent.ps1",
    [string]$PwshPath = "C:\Program Files\PowerShell\7\pwsh.exe"
)

# [Same implementation as ACME service above]
```

### Install Services

```powershell
# Run as Administrator
cd C:\ECA

# Install ACME service
.\install-acme-service.ps1

# Install EST service
.\install-est-service.ps1

# Verify installation
Get-Service ECA-*
```

**Expected Output:**
```
Status   Name               DisplayName
------   ----               -----------
Stopped  ECA-ACME-Agent     ECA ACME Certificate Agent
Stopped  ECA-EST-Agent      ECA EST Certificate Agent
```

---

## Environment Variable Prefixing

### Why Prefixing is Critical

Windows Services often share the **System** environment variable scope. Without prefixing, multiple agents would conflict:

**Problem (no prefixing):**
```powershell
# Both services read PKI_URL
$env:PKI_URL = "https://acme-pki:9000"  # ACME needs this
$env:PKI_URL = "https://est-pki:8443"   # EST overwrites it! 💥
```

**Solution (with prefixing):**
```powershell
# Each service reads its own prefixed variables
$env:ACME_PKI_URL = "https://acme-pki:9000"
$env:EST_PKI_URL = "https://est-pki:8443"
```

### Set Environment Variables for Services

Use `sc.exe` or Registry to set service-specific environment variables:

#### ACME Agent Environment

```powershell
# Set at System level for ACME service
[System.Environment]::SetEnvironmentVariable("AGENT_ENV_PREFIX", "ACME_", "Machine")
[System.Environment]::SetEnvironmentVariable("ACME_PKI_URL", "https://pki.contoso.com:9000", "Machine")
[System.Environment]::SetEnvironmentVariable("ACME_DOMAIN_NAME", "web-server-01.contoso.com", "Machine")
[System.Environment]::SetEnvironmentVariable("ACME_AGENT_ID", "acme-agent-web-01", "Machine")
```

#### EST Agent Environment

```powershell
# Set at System level for EST service
[System.Environment]::SetEnvironmentVariable("AGENT_ENV_PREFIX", "EST_", "Machine")
[System.Environment]::SetEnvironmentVariable("EST_PKI_URL", "https://pki.contoso.com:9000", "Machine")
[System.Environment]::SetEnvironmentVariable("EST_DEVICE_NAME", "client-device-001", "Machine")
[System.Environment]::SetEnvironmentVariable("EST_BOOTSTRAP_TOKEN", "your-secure-token-here", "Machine")
[System.Environment]::SetEnvironmentVariable("EST_AGENT_ID", "est-agent-client-001", "Machine")
```

**Security Note:** Encrypt bootstrap tokens or use Windows Credential Manager for production.

### Verify Environment Configuration

```powershell
# Check System environment variables
Get-ChildItem Env: | Where-Object { $_.Name -like "*ACME*" -or $_.Name -like "*EST*" }
```

**Expected Output:**
```
Name                           Value
----                           -----
AGENT_ENV_PREFIX               ACME_
ACME_PKI_URL                   https://pki.contoso.com:9000
ACME_DOMAIN_NAME               web-server-01.contoso.com
ACME_AGENT_ID                  acme-agent-web-01
EST_PKI_URL                    https://pki.contoso.com:9000
EST_DEVICE_NAME                client-device-001
EST_BOOTSTRAP_TOKEN            ***REDACTED***
EST_AGENT_ID                   est-agent-client-001
```

---

## Testing & Validation

### 1. Test Agent Locally (Before Service)

```powershell
# Test ACME agent
cd C:\ECA\agents\acme
$env:AGENT_ENV_PREFIX = "ACME_"
pwsh -File .\agent.ps1

# Observe logs (Ctrl+C to stop)

# Test EST agent
cd C:\ECA\agents\est
$env:AGENT_ENV_PREFIX = "EST_"
$env:EST_BOOTSTRAP_TOKEN = "your-token"
pwsh -File .\agent.ps1

# Observe logs (Ctrl+C to stop)
```

### 2. Start Services

```powershell
# Start ACME service
Start-Service -Name "ECA-ACME-Agent"

# Start EST service
Start-Service -Name "ECA-EST-Agent"

# Check status
Get-Service ECA-*
```

**Expected Output:**
```
Status   Name               DisplayName
------   ----               -----------
Running  ECA-ACME-Agent     ECA ACME Certificate Agent
Running  ECA-EST-Agent      ECA EST Certificate Agent
```

### 3. Monitor Service Logs

```powershell
# View recent ACME agent logs
Get-EventLog -LogName Application -Source "ECA-ACME-Agent" -Newest 10

# View recent EST agent logs
Get-EventLog -LogName Application -Source "ECA-EST-Agent" -Newest 10

# Tail logs in real-time (PowerShell 7 required)
Get-EventLog -LogName Application -Source "ECA-ACME-Agent" -Newest 1 -After (Get-Date).AddSeconds(-5) | Select-Object TimeGenerated, Message
```

### 4. Verify Certificate Generation

```powershell
# Check ACME certificate
Get-Item C:\certs\acme\server.crt | Select-Object Name, Length, LastWriteTime

# Check EST certificate
Get-Item C:\certs\est\client.crt | Select-Object Name, Length, LastWriteTime

# View certificate details
$cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2("C:\certs\acme\server.crt")
$cert | Select-Object Subject, Issuer, NotBefore, NotAfter
```

---

## Troubleshooting

### Issue: Service Fails to Start

**Symptoms:**
```
Start-Service : Service 'ECA-ACME-Agent' cannot be started due to the following error: Cannot start service...
```

**Solution:**
```powershell
# Check service status
sc.exe query "ECA-ACME-Agent"

# View service configuration
sc.exe qc "ECA-ACME-Agent"

# Check Event Log for errors
Get-EventLog -LogName Application -Source "ECA-ACME-Agent" -EntryType Error -Newest 5

# Test agent script manually
pwsh -NoProfile -ExecutionPolicy Bypass -File "C:\ECA\agents\acme\agent.ps1"
```

---

### Issue: Environment Variables Not Applied

**Symptoms:**
- Agent logs: "Configuration validation failed: Required field 'pki_url' is missing"
- Environment variables visible in PowerShell but not in service

**Solution:**
```powershell
# Services inherit environment from System scope, not User
# Verify variables are set at Machine level
[System.Environment]::GetEnvironmentVariable("ACME_PKI_URL", "Machine")

# If null, re-set at Machine level
[System.Environment]::SetEnvironmentVariable("ACME_PKI_URL", "https://pki.contoso.com:9000", "Machine")

# Restart service to pick up changes
Restart-Service -Name "ECA-ACME-Agent"
```

---

### Issue: Certificate Files Not Created

**Symptoms:**
- Service running but no .crt/.key files in C:\certs

**Solution:**
```powershell
# Check agent logs for errors
Get-EventLog -LogName Application -Source "ECA-ACME-Agent" -Newest 20 | Where-Object { $_.EntryType -eq "Error" }

# Verify PKI connectivity
Test-NetConnection -ComputerName pki.contoso.com -Port 9000

# Check permissions on cert directory
Get-Acl C:\certs\acme | Format-List

# Manually trigger renewal (if agent is stuck)
Restart-Service -Name "ECA-ACME-Agent"
```

---

### Issue: Multiple Agents Conflicting

**Symptoms:**
- ACME agent uses EST config or vice versa
- Logs show wrong `agent_type`

**Solution:**
```powershell
# Verify each service has correct AGENT_ENV_PREFIX
Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\ECA-ACME-Agent" -Name Environment
Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\ECA-EST-Agent" -Name Environment

# Set per-service environment (Windows Server 2019+)
# Option 1: Use registry
$acmeEnv = @("AGENT_ENV_PREFIX=ACME_")
Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\ECA-ACME-Agent" -Name Environment -Value $acmeEnv

# Option 2: Use NSSM (recommended for complex scenarios)
# Download NSSM: https://nssm.cc/download
nssm set ECA-ACME-Agent AppEnvironmentExtra AGENT_ENV_PREFIX=ACME_
nssm set ECA-EST-Agent AppEnvironmentExtra AGENT_ENV_PREFIX=EST_

# Restart services
Restart-Service ECA-*
```

---

## Production Best Practices

### 1. Monitoring

- **Event Logs:** Monitor Application log for ERROR entries from ECA services
- **Certificate Expiry:** Set up scheduled task to check certificate expiry daily
- **Service Health:** Use System Center or custom PowerShell to alert on service failures

Example scheduled task:
```powershell
# Check-ECA-Health.ps1
$acmeService = Get-Service "ECA-ACME-Agent"
$estService = Get-Service "ECA-EST-Agent"

if ($acmeService.Status -ne "Running" -or $estService.Status -ne "Running") {
    Write-EventLog -LogName Application -Source "ECA-Monitor" -EntryType Error -EventId 1001 -Message "ECA service(s) not running"
    # Send email/alert
}
```

### 2. Security

- **Least Privilege:** Run services as dedicated service accounts (not LocalSystem) in production
- **Credential Protection:** Use Windows Credential Manager or Azure Key Vault for bootstrap tokens
- **Certificate Storage:** Enable EFS encryption on C:\certs
- **Audit Logging:** Enable file access auditing on certificate directories

### 3. Backup & Recovery

```powershell
# Backup configuration and certificates
$backupPath = "C:\ECA-Backup-$(Get-Date -Format 'yyyyMMdd')"
New-Item -ItemType Directory -Path $backupPath -Force

Copy-Item -Path "C:\ECA\agents" -Destination "$backupPath\agents" -Recurse
Copy-Item -Path "C:\certs" -Destination "$backupPath\certs" -Recurse

# Export service configuration
sc.exe qc "ECA-ACME-Agent" > "$backupPath\acme-service-config.txt"
sc.exe qc "ECA-EST-Agent" > "$backupPath\est-service-config.txt"
```

---

## Related Documentation

- [HANDOVER.md](../HANDOVER.md) - Complete project handover
- [ROADMAP.md](../ROADMAP.md) - Development roadmap
- [README.md](../README.md) - Quick start guide
- [TESTING_QUICKSTART.md](../TESTING_QUICKSTART.md) - Testing guide

---

**Questions?** Open an issue at `<repository-url>/issues` or consult the troubleshooting guide above.
