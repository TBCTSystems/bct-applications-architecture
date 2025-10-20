# Complete Certificate Renewal Service Startup Guide

## 🚀 Quick Start - Start the Renewal Loop

### **Option 1: Single PowerShell Window (Recommended for Testing)**

```powershell
# 1. Start Step CA server in background
Start-Process powershell -ArgumentList "-NoExit", "-Command", ".\start-step-ca.ps1"

# 2. Wait a moment for Step CA to start
Start-Sleep -Seconds 5

# 3. Check Step CA status
.\start-step-ca.ps1 -Status

# 4. Start certificate renewal daemon
.\start-renewal-service.ps1 daemon
```

### **Option 2: Two PowerShell Windows (Easier to Monitor)**

**Window 1 - Step CA Server:**
```powershell
.\start-step-ca.ps1
```
*Keep this window open - Step CA server will run here*

**Window 2 - Certificate Renewal Service:**
```powershell
.\start-renewal-service.ps1 daemon
```
*This runs the continuous renewal loop*

### **Option 3: Docker Approach (Alternative)**

```powershell
# Start Step CA in Docker
cd test
docker-compose -f docker-compose.test.yml up -d step-ca-test

# Wait for startup
Start-Sleep -Seconds 10

# Check if ready
docker logs step-ca-test

# Start renewal service
cd ..
.\start-renewal-service.ps1 daemon
```

## 📋 Available Commands

### **Step CA Server Management**
```powershell
.\start-step-ca.ps1           # Start Step CA server
.\start-step-ca.ps1 -Status   # Check if Step CA is running
.\start-step-ca.ps1 -Stop     # Stop Step CA server
```

### **Certificate Renewal Service**
```powershell
# Continuous renewal loop (recommended)
.\start-renewal-service.ps1 daemon

# One-time certificate check
.\start-renewal-service.ps1 check

# Check certificate status only
.\start-renewal-service.ps1 status

# Renew specific certificate
.\start-renewal-service.ps1 renew -CertificateName "test-expiring-soon"

# Show help
.\start-renewal-service.ps1 help
```

## 🧪 Testing Scenarios

### **Test 1: Status Check**
```powershell
# Shows current status of all test certificates
.\start-renewal-service.ps1 status
```

**Expected Output:**
```
Certificate Status Report
=========================
• test-expiring-soon: NEEDS RENEWAL (expires in 2 days)
• test-web-server: NEEDS RENEWAL (expires in 10 days)
• test-client-auth: NEEDS RENEWAL (expires in 7 days)
• test-api-server: OK (expires in 20 days)
• test-valid-long: OK (expires in 60 days)
• test-already-expired: EXPIRED (needs immediate renewal)
```

### **Test 2: Single Check**
```powershell
# Runs one renewal cycle
.\start-renewal-service.ps1 check
```

**Expected Behavior:**
- ✅ Identifies certificates needing renewal
- ✅ Attempts to renew them via Step CA
- ✅ Verifies renewed certificates
- ✅ Reports success/failure

### **Test 3: Continuous Daemon**
```powershell
# Runs continuous renewal loop
.\start-renewal-service.ps1 daemon
```

**Expected Behavior:**
- 🔄 Checks certificates every 2 minutes (test config)
- 🔄 Automatically renews certificates approaching expiration
- 📝 Logs all activity to `test/logs/cert_renewal_test.log`
- ⏹️ Stops gracefully with Ctrl+C

### **Test 4: Manual Renewal**
```powershell
# Force renewal of specific certificate
.\start-renewal-service.ps1 renew -CertificateName "test-expiring-soon"
```

## 🔧 Configuration

### **Test vs Production**
```powershell
# Test mode (default) - fast intervals, debug logging
.\start-renewal-service.ps1 daemon

# Production mode - normal intervals
.\start-renewal-service.ps1 daemon -Production
```

### **Key Configuration Differences**

| Setting | Test | Production |
|---------|------|------------|
| Check Interval | 2 minutes | 30 minutes |
| Renewal Threshold | 5 days | 30 days |
| Emergency Threshold | 1 day | 7 days |
| Log Level | DEBUG | INFO |
| Log File | test/logs/ | logs/ |

## 🚨 Troubleshooting

### **Step CA Won't Start**
```powershell
# Check if port 9000 is in use
netstat -an | findstr ":9000"

# Verify Step CA configuration
Get-ChildItem test\step-ca\config\

# Check password file
Get-Content test\step-ca\secrets\password
```

### **Certificate Renewal Fails**
```powershell
# Check Step CA connectivity
.\start-step-ca.ps1 -Status

# Verify configuration
Get-Content test\test-config\config.yaml

# Check Step CLI is available
step version
```

### **Certificates Not Found**
```powershell
# Verify dummy certificates exist
Get-ChildItem test\dummy-certs\

# Regenerate if needed
python test\generate_dummy_certs.py
```

## 📊 Monitoring

### **Real-time Monitoring**
```powershell
# Watch log file in real-time
Get-Content test\logs\cert_renewal_test.log -Wait
```

### **Status Dashboard**
```powershell
# Create simple status script
while ($true) {
    Clear-Host
    Write-Host "Certificate Renewal Dashboard - $(Get-Date)" -ForegroundColor Green
    Write-Host "=" * 50
    .\start-renewal-service.ps1 status
    Start-Sleep -Seconds 30
}
```

## 🎯 Production Deployment

When ready for production:

1. **Update Configuration**: Modify `config/config.yaml` with real certificates
2. **Install as Service**: Use provided systemd/Windows service files
3. **Set Production Intervals**: Longer check intervals (30+ minutes)
4. **Configure Monitoring**: Set up alerts for renewal failures
5. **Backup Strategy**: Implement certificate backup and recovery

## 🔗 Related Files

- `main.py` - Main CLI interface
- `src/renewal_service.py` - Core renewal logic
- `src/certificate_monitor.py` - Certificate monitoring
- `src/step_ca_client.py` - Step CA integration
- `test/test-config/config.yaml` - Test configuration
- `test/dummy-certs/` - Test certificates