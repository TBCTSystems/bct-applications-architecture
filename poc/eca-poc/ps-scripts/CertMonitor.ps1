#Requires -Version 5.1

<#
.SYNOPSIS
    Certificate Monitor
.DESCRIPTION
    Monitors certificates and determines renewal requirements
#>

class CertMonitor {
    [CertRenewalLogger]$Logger
    [object]$StepCAConfig
    [object]$ServiceConfig
    [CRLManager]$CRLManager
    
    CertMonitor([CertRenewalLogger]$Logger, [object]$StepCAConfig, [object]$ServiceConfig, [CRLManager]$CRLManager) {
        $this.Logger = $Logger
        $this.StepCAConfig = $StepCAConfig
        $this.ServiceConfig = $ServiceConfig
        $this.CRLManager = $CRLManager
    }
    
    [array] CheckAllCertificates([array]$CertificateConfigs) {
        $this.Logger.Info("Checking $($CertificateConfigs.Count) certificates for expiry")
        $statuses = @()
        
        foreach ($certConfig in $CertificateConfigs) {
            $this.Logger.Debug("Checking certificate: $($certConfig.name)")
            $status = $this.CheckCertificate($certConfig)
            $statuses += $status
            
            # Log certificate status
            if ($status.is_revoked) {
                $this.Logger.Warning("Certificate '$($status.name)' is REVOKED and needs immediate renewal")
            }
            elseif ($status.is_invalid) {
                $this.Logger.Error("Certificate '$($status.name)' is INVALID: $($status.error_message)")
            }
            elseif ($status.needs_renewal) {
                $this.Logger.Warning("Certificate '$($status.name)' needs $($status.renewal_reason.ToUpper()) renewal ($([math]::Round($status.remaining_lifetime_percent, 1))% remaining, threshold: $($status.renewal_threshold_percent)%)")
            }
            else {
                $this.Logger.Info("Certificate '$($status.name)' is valid ($([math]::Round($status.remaining_lifetime_percent, 1))% remaining, threshold: $($status.renewal_threshold_percent)%)")
            }
        }
        
        return $statuses
    }
    
    [object] CheckCertificate([object]$CertConfig) {
        $status = [PSCustomObject]@{
            name = $certConfig.name
            cert_path = $certConfig.cert_path
            is_valid = $false
            is_invalid = $false
            is_revoked = $false
            needs_renewal = $false
            renewal_reason = "unknown"
            renewal_threshold_percent = $this.GetEffectiveRenewalThreshold($certConfig)
            remaining_lifetime_percent = 0.0
            days_until_expiry = 0
            expiry_date = $null
            error_message = $null
        }
        
        try {
            # Check if certificate file exists
            if (-not (Test-Path $certConfig.cert_path)) {
                $status.is_invalid = $true
                $status.needs_renewal = $true
                $status.renewal_reason = "missing"
                $status.error_message = "Certificate file not found"
                return $status
            }
            
            # Load and check certificate expiry
            $expiryInfo = $this.CheckCertificateExpiry($certConfig.cert_path, $status.renewal_threshold_percent)
            
            $status.expiry_date = $expiryInfo.expires_at
            $status.days_until_expiry = $expiryInfo.days_until_expiry
            $status.needs_renewal = $expiryInfo.needs_renewal
            $status.renewal_reason = $expiryInfo.renewal_reason
            $status.remaining_lifetime_percent = $expiryInfo.remaining_lifetime_percent
            
            # Check CRL revocation status
            $status.is_revoked = $this.CheckRevocationStatus($certConfig)
            
            if ($status.is_revoked) {
                $status.needs_renewal = $true
                $status.renewal_reason = "revoked"
            }
            
            # Mark as valid if not expired/revoked/invalid
            if (-not $status.needs_renewal -and -not $status.is_invalid -and -not $status.is_revoked) {
                $status.is_valid = $true
            }
        }
        catch {
            $status.is_invalid = $true
            $status.needs_renewal = $true
            $status.error_message = $_.Exception.Message
            $this.Logger.Error("Error checking certificate $($certConfig.name): $_")
        }
        
        return $status
    }
    
    [object] CheckCertificateExpiry([string]$CertPath, [double]$RenewalThresholdPercent) {
        try {
            $cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2($CertPath)
            
            $now = Get-Date
            $notBefore = $cert.NotBefore
            $notAfter = $cert.NotAfter
            
            # Calculate time until expiry
            $timeUntilExpiry = $notAfter - $now
            $secondsRemaining = $timeUntilExpiry.TotalSeconds
            
            # Calculate total lifetime
            $totalLifetime = $notAfter - $notBefore
            $totalLifetimeSeconds = $totalLifetime.TotalSeconds
            
            # Calculate days for display
            $daysUntilExpiry = [math]::Floor($secondsRemaining / 86400)
            
            # Calculate remaining lifetime as percentage using seconds
            $remainingLifetimePercent = if ($totalLifetimeSeconds -gt 0) {
                ($secondsRemaining / $totalLifetimeSeconds) * 100
            } else {
                0.0
            }
            
            # Determine if renewal is needed
            $needsRenewal = $remainingLifetimePercent -le $RenewalThresholdPercent
            
            # Determine renewal urgency
            $renewalReason = if ($remainingLifetimePercent -le 0) {
                "expired"
            }
            elseif ($remainingLifetimePercent -le 10) {
                "emergency"
            }
            elseif ($remainingLifetimePercent -lt $RenewalThresholdPercent) {
                "normal"
            }
            elseif ($remainingLifetimePercent -le $RenewalThresholdPercent) {
                # Edge case: exactly at threshold
                "normal"
            }
            else {
                "valid"
            }
            
            return [PSCustomObject]@{
                expires_at = $notAfter
                days_until_expiry = $daysUntilExpiry
                needs_renewal = $needsRenewal
                renewal_reason = $renewalReason
                remaining_lifetime_percent = $remainingLifetimePercent
            }
        }
        catch {
            $this.Logger.Error("Failed to check certificate expiry: $_")
            throw
        }
    }
    
    [bool] CheckRevocationStatus([object]$CertConfig) {
        $this.Logger.Debug("Checking revocation status for certificate: $($CertConfig.name)")
        
        # Check configured CRL URLs
        $crlUrls = @()
        
        if ($this.StepCAConfig.crl_urls) {
            $crlUrls += $this.StepCAConfig.crl_urls
        }
        
        if ($crlUrls.Count -eq 0) {
            $this.Logger.Debug("No CRL distribution points found in certificate")
            return $false
        }
        
        $this.Logger.Debug("Checking certificate revocation against $($crlUrls.Count) CRL sources")
        return $this.CRLManager.CheckCertificateRevocation($CertConfig.cert_path, $crlUrls)
    }
    
    [double] GetEffectiveRenewalThreshold([object]$CertConfig) {
        # Use certificate-specific threshold if provided
        if ($null -ne $CertConfig.renewal_threshold_percent) {
            return [double]$CertConfig.renewal_threshold_percent
        }
        
        # Use service default
        if ($null -ne $this.ServiceConfig.renewal_threshold_percent) {
            return [double]$this.ServiceConfig.renewal_threshold_percent
        }
        
        # Fallback to hardcoded default
        return 33.0
    }
}

