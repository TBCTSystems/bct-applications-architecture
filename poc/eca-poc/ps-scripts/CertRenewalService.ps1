#Requires -Version 5.1

<#
.SYNOPSIS
    Certificate Renewal Service - PowerShell Implementation
.DESCRIPTION
    Main service script for automatic certificate renewal using Step CA.
    This is a PowerShell port of the Python renewal service.
.NOTES
    Author: Certificate Renewal Service
    Version: 1.0.0
#>

# Note: This script defines the CertificateRenewalService class
# It should be loaded AFTER the dependency classes are loaded
# See Start-CertRenewalService.ps1 for proper loading order

class CertificateRenewalService {
    [object]$Config
    [CertRenewalLogger]$Logger
    [CertMonitor]$Monitor
    [StepCAClient]$StepClient
    [CRLManager]$CRLManager
    [bool]$Running = $false
    
    CertificateRenewalService([string]$ConfigFile) {
        # Load configuration
        $this.Config = Get-CertRenewalConfig -ConfigPath $ConfigFile
        
        # Initialize logger
        $this.Logger = [CertRenewalLogger]::new(
            $this.Config.log_level,
            $this.Config.log_file
        )
        
        # Initialize components
        $this.StepClient = [StepCAClient]::new($this.Config.step_ca, $this.Logger)
        $this.CRLManager = [CRLManager]::new($this.Config.step_ca, $this.Logger)
        $this.Monitor = [CertMonitor]::new($this.Logger, $this.Config.step_ca, $this.Config, $this.CRLManager)
    }
    
    [bool] Initialize() {
        $this.Logger.Info("Initializing Certificate Renewal Service")
        
        # Create necessary directories
        $null = New-Item -Path $this.Config.cert_storage_path -ItemType Directory -Force -ErrorAction SilentlyContinue
        $logDir = Split-Path -Parent $this.Config.log_file
        $null = New-Item -Path $logDir -ItemType Directory -Force -ErrorAction SilentlyContinue
        
        # Bootstrap Step CA if needed
        if (-not $this.StepClient.BootstrapCA()) {
            $this.Logger.Error("Failed to bootstrap Step CA configuration")
            return $false
        }
        
        # Verify CA connectivity
        $caInfo = $this.StepClient.GetCAInfo()
        if ($null -eq $caInfo) {
            $this.Logger.Error("Cannot connect to Step CA")
            return $false
        }
        
        $this.Logger.Info("Step CA connection verified: $($caInfo | ConvertTo-Json -Compress)")
        
        # Validate certificate configurations
        if ($this.Config.certificates.Count -eq 0) {
            $this.Logger.Warning("No certificates configured for monitoring")
        }
        
        foreach ($certConfig in $this.Config.certificates) {
            # Ensure certificate directories exist
            $certDir = Split-Path -Parent $certConfig.cert_path
            $keyDir = Split-Path -Parent $certConfig.key_path
            
            $null = New-Item -Path $certDir -ItemType Directory -Force -ErrorAction SilentlyContinue
            $null = New-Item -Path $keyDir -ItemType Directory -Force -ErrorAction SilentlyContinue
        }
        
        $this.Logger.Info("Service initialization completed successfully")
        return $true
    }
    
    [array] CheckAndRenewCertificates() {
        $this.Logger.Info("Starting certificate check and renewal cycle")
        
        # Check certificate statuses
        $statuses = $this.Monitor.CheckAllCertificates($this.Config.certificates)
        
        # Count certificates by status
        $needsRenewal = @($statuses | Where-Object { $_.needs_renewal }).Count
        $invalid = @($statuses | Where-Object { $_.is_invalid }).Count
        $revoked = @($statuses | Where-Object { $_.is_revoked }).Count
        
        $this.Logger.Info("Certificate check complete: $($statuses.Count) total, $needsRenewal need renewal, $invalid invalid, $revoked revoked")
        
        # Process certificates that need renewal
        $renewalResults = @()
        foreach ($status in $statuses) {
            if ($status.needs_renewal) {
                $certConfig = $this.Config.certificates | Where-Object { $_.name -eq $status.name } | Select-Object -First 1
                
                if ($certConfig) {
                    $this.Logger.Info("Attempting to renew certificate: $($status.name)")
                    
                    try {
                        if ($this.StepClient.RenewCertificate($certConfig)) {
                            $this.Logger.Info("Successfully renewed certificate: $($status.name)")
                            
                            # Verify the renewed certificate
                            if ($this.StepClient.VerifyCertificate($certConfig.cert_path, $this.Config.step_ca.root_cert_path)) {
                                $this.Logger.Info("Renewed certificate verified: $($status.name)")
                            } else {
                                $this.Logger.Warning("Renewed certificate verification failed: $($status.name)")
                            }
                            
                            $renewalResults += @{
                                name = $status.name
                                success = $true
                                message = "Certificate renewed successfully"
                            }
                        } else {
                            $this.Logger.Error("Failed to renew certificate: $($status.name)")
                            $renewalResults += @{
                                name = $status.name
                                success = $false
                                message = "Certificate renewal failed"
                            }
                        }
                    }
                    catch {
                        $this.Logger.Error("Exception while renewing certificate $($status.name): $_")
                        $renewalResults += @{
                            name = $status.name
                            success = $false
                            message = "Exception: $_"
                        }
                    }
                }
            }
        }
        
        $successCount = @($renewalResults | Where-Object { $_.success }).Count
        $this.Logger.Info("Renewal cycle completed: $successCount/$($renewalResults.Count) certificates renewed successfully")
        
        return $statuses
    }
    
    [void] RunOnce() {
        if (-not $this.Initialize()) {
            $this.Logger.Error("Service initialization failed, cannot proceed")
            return
        }
        
        $this.CheckAndRenewCertificates()
    }
    
    [void] RunContinuous() {
        if (-not $this.Initialize()) {
            $this.Logger.Error("Service initialization failed, cannot start service")
            return
        }
        
        $this.Running = $true
        $this.Logger.Info("Starting continuous renewal service with check interval: $($this.Config.check_interval_minutes) minutes")
        
        while ($this.Running) {
            try {
                $this.CheckAndRenewCertificates()
                
                if ($this.Running) {
                    $sleepSeconds = $this.Config.check_interval_minutes * 60
                    $this.Logger.Info("Sleeping for $($this.Config.check_interval_minutes) minutes until next check")
                    Start-Sleep -Seconds $sleepSeconds
                }
            }
            catch {
                $this.Logger.Error("Error in renewal cycle: $_")
                $this.Logger.Info("Waiting 60 seconds before retry...")
                Start-Sleep -Seconds 60
            }
        }
        
        $this.Logger.Info("Service stopped")
    }
    
    [void] Stop() {
        $this.Logger.Info("Stopping service...")
        $this.Running = $false
    }
}

# Export the class
