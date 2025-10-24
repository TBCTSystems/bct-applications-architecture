#Requires -Version 5.1

<#
.SYNOPSIS
    Step CA Client
.DESCRIPTION
    Handles communication with Step CA for certificate operations
#>

class StepCAClient {
    [object]$Config
    [CertRenewalLogger]$Logger
    [string]$StepCLI = "step"
    
    StepCAClient([object]$StepCAConfig, [CertRenewalLogger]$Logger) {
        $this.Config = $StepCAConfig
        $this.Logger = $Logger
        
        # Find step CLI
        $stepPath = Get-Command step -ErrorAction SilentlyContinue
        if ($stepPath) {
            $this.StepCLI = $stepPath.Source
            $this.Logger.Info("Found step CLI at: $($this.StepCLI)")
        } else {
            $this.Logger.Warning("step CLI not found in PATH")
        }
    }
    
    [bool] BootstrapCA() {
        $this.Logger.Info("Bootstrapping Step CA configuration")
        
        try {
            $args = @(
                "ca", "bootstrap",
                "--ca-url", $this.Config.ca_url,
                "--fingerprint", $this.Config.ca_fingerprint,
                "--force"
            )
            
            $this.Logger.Debug("Running step command: $($this.StepCLI) $($args -join ' ')")
            
            $output = & $this.StepCLI @args 2>&1
            
            if ($LASTEXITCODE -eq 0) {
                $this.Logger.Info("Successfully bootstrapped CA configuration")
                return $true
            } else {
                $this.Logger.Error("Bootstrap failed: $output")
                return $false
            }
        }
        catch {
            $this.Logger.Error("Exception during bootstrap: $_")
            return $false
        }
    }
    
    [object] GetCAInfo() {
        $this.Logger.Debug("Getting CA information")
        
        try {
            $this.Logger.Debug("Running step command: $($this.StepCLI) ca health")
            
            $output = & $this.StepCLI ca health 2>&1
            
            if ($LASTEXITCODE -eq 0) {
                return @{
                    status = "healthy"
                    protocol = $this.Config.protocol
                    message = "ok"
                }
            } else {
                $this.Logger.Error("CA health check failed: $output")
                return $null
            }
        }
        catch {
            $this.Logger.Error("Exception getting CA info: $_")
            return $null
        }
    }
    
    [bool] RenewCertificate([object]$CertConfig) {
        $this.Logger.Info("Renewing certificate: $($CertConfig.name)")
        
        try {
            # Create backup of current certificate
            if (Test-Path $CertConfig.cert_path) {
                $backupPath = "$($CertConfig.cert_path).bak"
                Copy-Item $CertConfig.cert_path $backupPath -Force
                $this.Logger.Debug("Created backup of current certificate")
            }
            
            # Try to renew using existing certificate
            $args = @(
                "ca", "renew",
                $CertConfig.cert_path,
                $CertConfig.key_path,
                "--force"
            )
            
            $this.Logger.Debug("Running step command: $($this.StepCLI) $($args -join ' ')")
            
            $output = & $this.StepCLI @args 2>&1
            
            if ($LASTEXITCODE -eq 0) {
                $this.Logger.Info("Successfully renewed certificate: $($CertConfig.name)")
                return $true
            } else {
                # Renewal failed, try to request a new certificate
                $this.Logger.Warning("Renewal failed, trying fresh certificate request: $output")
                return $this.RequestNewCertificate($CertConfig)
            }
        }
        catch {
            $this.Logger.Error("Exception renewing certificate: $_")
            return $false
        }
    }
    
    [bool] RequestNewCertificate([object]$CertConfig) {
        $this.Logger.Info("Requesting new certificate for: $($CertConfig.subject)")
        
        try {
            # Get provisioner token
            $token = $this.GetProvisionerToken($CertConfig)
            if (-not $token) {
                $this.Logger.Error("Failed to get provisioner token")
                return $false
            }
            
            # Build certificate request command
            $args = @(
                "ca", "certificate",
                $CertConfig.subject,
                $CertConfig.cert_path,
                $CertConfig.key_path,
                "--token", $token,
                "--force"
            )
            
            $this.Logger.Debug("Running step command: $($this.StepCLI) $($args -join ' ')")
            
            $output = & $this.StepCLI @args 2>&1
            
            if ($LASTEXITCODE -eq 0) {
                $this.Logger.Info("Successfully obtained certificate for $($CertConfig.subject)")
                return $true
            } else {
                $this.Logger.Error("Certificate request failed: $output")
                return $false
            }
        }
        catch {
            $this.Logger.Error("Exception requesting new certificate: $_")
            return $false
        }
    }
    
    [string] GetProvisionerToken([object]$CertConfig) {
        $this.Logger.Debug("Getting provisioner token for subject: $($CertConfig.subject)")
        
        try {
            # Create temporary password file
            $tempPasswordFile = Join-Path $env:TEMP "temp_password_$([guid]::NewGuid()).txt"
            Set-Content -Path $tempPasswordFile -Value $this.Config.provisioner_password -NoNewline
            
            $this.Logger.Debug("Using temporary password file: $tempPasswordFile")
            
            # Build token command
            $args = @(
                "ca", "token",
                $CertConfig.subject,
                "--provisioner", $this.Config.provisioner_name,
                "--password-file", $tempPasswordFile
            )
            
            # Add SANs if provided
            if ($CertConfig.sans -and $CertConfig.sans.Count -gt 0) {
                foreach ($san in $CertConfig.sans) {
                    $args += "--san"
                    $args += $san
                }
            }
            
            $this.Logger.Debug("Running step command: $($this.StepCLI) $($args -join ' ')")
            
            $output = & $this.StepCLI @args 2>&1
            
            # Clean up password file
            Remove-Item $tempPasswordFile -ErrorAction SilentlyContinue
            
            # Filter output to get only the token (string), not error records (stderr messages)
            $token = $output | Where-Object { $_ -is [string] } | Select-Object -First 1
            
            if ($LASTEXITCODE -eq 0 -and $token) {
                $this.Logger.Debug("Successfully obtained provisioner token")
                return $token
            } else {
                $errorMsg = $output | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] } | Select-Object -First 1
                $this.Logger.Error("Failed to get provisioner token: $errorMsg")
                return $null
            }
        }
        catch {
            $this.Logger.Error("Exception getting provisioner token: $_")
            return $null
        }
    }
    
    [bool] VerifyCertificate([string]$CertPath, [string]$RootCertPath) {
        $this.Logger.Debug("Verifying certificate: $CertPath")
        
        try {
            $args = @(
                "certificate", "verify",
                $CertPath,
                "--roots", $RootCertPath
            )
            
            $this.Logger.Debug("Running step command: $($this.StepCLI) $($args -join ' ')")
            
            $output = & $this.StepCLI @args 2>&1
            
            if ($LASTEXITCODE -eq 0) {
                $this.Logger.Debug("Certificate verification successful")
                return $true
            } else {
                $this.Logger.Warning("Certificate verification failed: $output")
                return $false
            }
        }
        catch {
            $this.Logger.Error("Exception verifying certificate: $_")
            return $false
        }
    }
}

