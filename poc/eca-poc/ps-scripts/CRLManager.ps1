#Requires -Version 5.1

<#
.SYNOPSIS
    CRL (Certificate Revocation List) Manager
.DESCRIPTION
    Manages downloading, caching, and checking certificate revocation status
#>

class CRLManager {
    [object]$Config
    [CertRenewalLogger]$Logger
    [hashtable]$CRLCache = @{}
    [hashtable]$LastDownloadTime = @{}
    [int]$CacheTimeoutSeconds = 60
    
    CRLManager([object]$StepCAConfig, [CertRenewalLogger]$Logger) {
        $this.Config = $StepCAConfig
        $this.Logger = $Logger
        
        # Create CRL cache directory
        if (-not (Test-Path $this.Config.crl_cache_dir)) {
            $null = New-Item -Path $this.Config.crl_cache_dir -ItemType Directory -Force
        }
    }
    
    [object] DownloadCRL([string]$Url) {
        $this.Logger.Debug("Downloading CRL from: $Url")
        
        try {
            # Check PowerShell version for SSL handling
            $psVersion = (Get-Variable -Name PSVersionTable -ValueOnly).PSVersion.Major
            $this.Logger.Debug("PowerShell version: $psVersion")
            
            if ($psVersion -ge 6) {
                # PowerShell 6+: Use Invoke-WebRequest with -SkipCertificateCheck
                $this.Logger.Debug("Using PowerShell Core HTTP client with SkipCertificateCheck")
                $this.Logger.Debug("Timeout: $($this.Config.crl_timeout_seconds) seconds")
                
                # Try/catch specifically for the web request to get better error details
                try {
                    # Call directly without splatting to avoid class method issues
                    $response = Invoke-WebRequest -Uri $Url -TimeoutSec $this.Config.crl_timeout_seconds -UseBasicParsing -SkipCertificateCheck
                    $this.Logger.Debug("Web request completed successfully")
                } catch {
                    $this.Logger.Debug("Web request exception type: $($_.Exception.GetType().FullName)")
                    $this.Logger.Debug("Web request exception message: $($_.Exception.Message)")
                    throw
                }
                
                if ($response.StatusCode -eq 200 -and $response.Content.Length -gt 0) {
                    $this.Logger.Info("Successfully downloaded CRL from $Url ($($response.Content.Length) bytes)")
                    return $response.Content
                } else {
                    $this.Logger.Warning("Empty CRL response from $Url")
                    return $null
                }
            } else {
                # PowerShell 5.1: Use ServicePointManager callback
                $this.Logger.Debug("Using Windows PowerShell HTTP client")
                
                $originalCallback = [System.Net.ServicePointManager]::ServerCertificateValidationCallback
                $originalTls = [System.Net.ServicePointManager]::SecurityProtocol
                
                try {
                    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
                    [System.Net.ServicePointManager]::ServerCertificateValidationCallback = { $true }
                    
                    $webClient = New-Object System.Net.WebClient
                    $webClient.Headers.Add("User-Agent", "CertRenewalService/1.0")
                    
                    $crlBytes = $webClient.DownloadData($Url)
                    
                    if ($crlBytes -and $crlBytes.Length -gt 0) {
                        $this.Logger.Info("Successfully downloaded CRL from $Url ($($crlBytes.Length) bytes)")
                        return $crlBytes
                    } else {
                        $this.Logger.Warning("Empty CRL response from $Url")
                        return $null
                    }
                } finally {
                    [System.Net.ServicePointManager]::ServerCertificateValidationCallback = $originalCallback
                    [System.Net.ServicePointManager]::SecurityProtocol = $originalTls
                }
            }
        }
        catch {
            $this.Logger.Error("Failed to download CRL from ${Url}: $_")
            return $null
        }
    }
    
    [string] GetCRLFilePath([string]$Url) {
        # Create a hash of the URL for the filename
        $hash = [System.Security.Cryptography.SHA256]::Create()
        $hashBytes = $hash.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($Url))
        $hashString = [System.BitConverter]::ToString($hashBytes).Replace("-", "").Substring(0, 16).ToLower()
        
        $uri = [System.Uri]$Url
        $hostname = if ($uri.Host) { $uri.Host } else { "unknown" }
        $filename = "${hostname}_${hashString}.crl"
        
        return Join-Path $this.Config.crl_cache_dir $filename
    }
    
    [bool] SaveCRLToFile([byte[]]$CRLData, [string]$FilePath) {
        try {
            $dir = Split-Path -Parent $FilePath
            if ($dir -and -not (Test-Path $dir)) {
                $null = New-Item -Path $dir -ItemType Directory -Force
            }
            
            [System.IO.File]::WriteAllBytes($FilePath, $CRLData)
            $this.Logger.Debug("Saved CRL to $FilePath")
            return $true
        }
        catch {
            $this.Logger.Error("Failed to save CRL to ${FilePath}: $_")
            return $false
        }
    }
    
    [object] LoadCRLFromFile([string]$FilePath) {
        try {
            if (-not (Test-Path $FilePath)) {
                return $null
            }
            
            $crlData = [System.IO.File]::ReadAllBytes($FilePath)
            return $crlData
        }
        catch {
            $this.Logger.Error("Error loading CRL from ${FilePath}: $_")
            return $null
        }
    }
    
    [object] RefreshCRL([string]$Url) {
        $filePath = $this.GetCRLFilePath($Url)
        $now = Get-Date
        
        # Check if we recently downloaded this CRL (within cache timeout)
        if ($this.LastDownloadTime.ContainsKey($Url)) {
            $timeSinceDownload = ($now - $this.LastDownloadTime[$Url]).TotalSeconds
            if ($timeSinceDownload -lt $this.CacheTimeoutSeconds) {
                if ($this.CRLCache.ContainsKey($Url)) {
                    $this.Logger.Debug("Using recently downloaded CRL for $Url (downloaded $([math]::Round($timeSinceDownload))s ago)")
                    return $this.CRLCache[$Url]
                }
            }
        }
        
        # Try to download the latest CRL
        $this.Logger.Debug("Attempting to download latest CRL from $Url")
        $crlData = $this.DownloadCRL($Url)
        
        if ($null -eq $crlData) {
            # Fallback to cached version if download fails
            $this.Logger.Warning("CRL download failed, trying cached version for $Url")
            
            # Try in-memory cache first
            if ($this.CRLCache.ContainsKey($Url)) {
                $this.Logger.Info("Using in-memory cached CRL for $Url")
                return $this.CRLCache[$Url]
            }
            
            # Try loading from cached file
            $crlData = $this.LoadCRLFromFile($filePath)
            if ($null -ne $crlData) {
                $this.Logger.Info("Loaded CRL from cached file for $Url")
                $this.CRLCache[$Url] = $crlData
                return $crlData
            }
            
            $this.Logger.Error("No cached CRL available for $Url")
            return $null
        }
        
        # Successfully downloaded CRL - update download time
        $this.LastDownloadTime[$Url] = $now
        
        # Save to file
        if (-not $this.SaveCRLToFile($crlData, $filePath)) {
            $this.Logger.Warning("Failed to cache CRL for $Url")
        }
        
        # Cache the CRL data
        $this.CRLCache[$Url] = $crlData
        $this.Logger.Info("Successfully refreshed CRL for $Url")
        
        return $crlData
    }
    
    [bool] CheckCertificateRevocation([string]$CertPath, [array]$CRLUrls) {
        if (-not $this.Config.crl_enabled) {
            $this.Logger.Debug("CRL checking is disabled")
            return $false
        }
        
        if ($CRLUrls.Count -eq 0) {
            $this.Logger.Warning("No CRL URLs available for revocation checking")
            return $false
        }
        
        try {
            # Load the certificate
            $cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2($CertPath)
            $serialNumber = $cert.SerialNumber
            
            $this.Logger.Debug("Checking certificate revocation against $($CRLUrls.Count) CRL sources")
            
            foreach ($crlUrl in $CRLUrls) {
                $crlData = $this.RefreshCRL($crlUrl)
                if ($null -eq $crlData) {
                    $this.Logger.Warning("Could not load CRL from $crlUrl")
                    continue
                }
                
                # Parse CRL and check for revocation
                # Note: Native PowerShell/.NET doesn't have great CRL parsing
                # For production, consider using OpenSSL or step CLI
                if ($this.IsCertificateInCRL($serialNumber, $crlData)) {
                    $this.Logger.Warning("Certificate is REVOKED: Serial $serialNumber")
                    return $true
                }
                
                $this.Logger.Debug("Certificate not found in CRL from $crlUrl")
            }
            
            $this.Logger.Debug("Certificate revocation check passed - not found in any CRL")
            return $false
        }
        catch {
            $this.Logger.Error("Error checking certificate revocation: $_")
            return $false
        }
    }
    
    hidden [bool] IsCertificateInCRL([string]$SerialNumber, [byte[]]$CRLData) {
        # This is a simplified check - for production use step CLI or OpenSSL
        try {
            # Use step CLI to parse CRL if available
            $tempCrlFile = Join-Path $env:TEMP "temp_crl_$([guid]::NewGuid()).crl"
            [System.IO.File]::WriteAllBytes($tempCrlFile, $CRLData)
            
            # Try to use step CLI to inspect CRL
            if (Get-Command step -ErrorAction SilentlyContinue) {
                $crlInfo = & step crl inspect $tempCrlFile --format json 2>$null | ConvertFrom-Json
                Remove-Item $tempCrlFile -ErrorAction SilentlyContinue
                
                if ($crlInfo.revoked_certificates) {
                    foreach ($revokedCert in $crlInfo.revoked_certificates) {
                        if ($revokedCert.serial_number -eq $SerialNumber) {
                            return $true
                        }
                    }
                }
            }
            else {
                Remove-Item $tempCrlFile -ErrorAction SilentlyContinue
                $this.Logger.Debug("step CLI not available for CRL parsing")
            }
            
            return $false
        }
        catch {
            $this.Logger.Debug("Error parsing CRL: $_")
            return $false
        }
    }
}

