<#
.SYNOPSIS
    ECA-EST Agent - Automated Client Certificate Lifecycle Management

.DESCRIPTION
    Main orchestration script for EST protocol-based client certificate lifecycle management.
    Implements infinite loop monitoring certificate status and performing automated enrollment
    and re-enrollment using the EST protocol with bootstrap token (initial) and mTLS (renewal)
    authentication.

.NOTES
    Author: ECA-EST Agent
    Version: 1.0.0
    Requires: PowerShell Core 7.0+
#>

# Exit on error
$ErrorActionPreference = 'Stop'

#region Inline Logging Functions
# Note: Logger module is imported by sub-modules (EstClient, BootstrapTokenManager, ConfigManager),
# but due to PowerShell module scoping, we define inline logging functions for the main script.

function global:Write-LogEntry {
    param(
        [Parameter(Mandatory=$true)]
        [ValidateSet('INFO','WARN','ERROR','DEBUG')]
        [string]$Severity,
        [Parameter(Mandatory=$true)]
        [string]$Message,
        [Parameter(Mandatory=$false)]
        [hashtable]$Context = @{}
    )
    $timestamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    $contextJson = if ($Context.Count -gt 0) { ", " + (($Context.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join ", ") } else { "" }
    Write-Host "[$timestamp] ${Severity}: $Message$contextJson"
}

function global:Write-LogInfo { param([Parameter(Mandatory=$true)][string]$Message, [hashtable]$Context = @{}) Write-LogEntry -Severity 'INFO' -Message $Message -Context $Context }
function global:Write-LogWarn { param([Parameter(Mandatory=$true)][string]$Message, [hashtable]$Context = @{}) Write-LogEntry -Severity 'WARN' -Message $Message -Context $Context }
function global:Write-LogError { param([Parameter(Mandatory=$true)][string]$Message, [hashtable]$Context = @{}) Write-LogEntry -Severity 'ERROR' -Message $Message -Context $Context }
function global:Write-LogDebug { param([Parameter(Mandatory=$true)][string]$Message, [hashtable]$Context = @{}) Write-LogEntry -Severity 'DEBUG' -Message $Message -Context $Context }

#endregion

#region Environment Prefix Helpers

function Add-PrefixDelimiterIfMissing {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Prefix
    )

    if ([string]::IsNullOrWhiteSpace($Prefix)) {
        return ""
    }

    if ($Prefix.EndsWith("_")) {
        return $Prefix
    }

    return "${Prefix}_"
}

function Get-AgentEnvPrefixList {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$DefaultPrefix = "EST_"
    )

    $prefixes = New-Object System.Collections.Generic.List[string]

    $explicitPrefix = $env:AGENT_ENV_PREFIX
    if (-not [string]::IsNullOrWhiteSpace($explicitPrefix)) {
        $prefixes.Add($explicitPrefix)
    }

    if ([string]::IsNullOrWhiteSpace($explicitPrefix) -and -not [string]::IsNullOrWhiteSpace($env:AGENT_NAME)) {
        $prefixes.Add((Add-PrefixDelimiterIfMissing -Prefix $env:AGENT_NAME))
    }

    if (-not [string]::IsNullOrWhiteSpace($DefaultPrefix)) {
        $prefixes.Add((Add-PrefixDelimiterIfMissing -Prefix $DefaultPrefix))
    }

    $prefixes.Add("")

    return $prefixes | Where-Object { $_ -ne $null } | Select-Object -Unique
}

#endregion

#region Module Imports

# Resolve shared module directory so the agent works both in-container (/agent/common)
# and when run directly from the repository checkout (agents/common).
$commonModuleCandidates = @()

$localCommon = Join-Path $PSScriptRoot 'common'
if (Test-Path (Join-Path $localCommon 'Logger.psm1')) {
    $commonModuleCandidates += $localCommon
}

$parentDir = Split-Path $PSScriptRoot -Parent
if (-not [string]::IsNullOrWhiteSpace($parentDir)) {
    $parentCommon = Join-Path $parentDir 'common'
    if (Test-Path (Join-Path $parentCommon 'Logger.psm1')) {
        $commonModuleCandidates += $parentCommon
    }
}

$script:CommonModuleDirectory = $commonModuleCandidates | Select-Object -First 1
if (-not $script:CommonModuleDirectory) {
    throw "EST agent: unable to locate common module directory relative to $PSScriptRoot."
}

function Import-AgentCommonModule {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ModuleFileName,

        [switch]$GlobalScope
    )

    $fullPath = Join-Path $script:CommonModuleDirectory $ModuleFileName
    if (-not (Test-Path $fullPath)) {
        throw "EST agent: common module not found at $fullPath."
    }

    $importParams = @{
        Name        = $fullPath
        Force       = $true
        ErrorAction = 'Stop'
    }

    if ($GlobalScope) {
        $importParams['Global'] = $true
    }

    Import-Module @importParams | Out-Null
}

# Import all required modules using relative paths from script directory
$modulePath = Split-Path -Parent $PSCommandPath
Write-Host "[DEBUG] Module path: $modulePath"

try {
    Write-Host "[DEBUG] Importing CryptoHelper..."
    # NOTE: Use paths relative to working directory (/agent) with explicit ./ prefix
    Import-AgentCommonModule -ModuleFileName 'CryptoHelper.psm1' -GlobalScope
    Write-Host "[DEBUG] CryptoHelper imported successfully"

    Write-Host "[DEBUG] Importing FileOperations..."
    Import-AgentCommonModule -ModuleFileName 'FileOperations.psm1' -GlobalScope
    Write-Host "[DEBUG] FileOperations imported successfully"

    Write-Host "[DEBUG] Importing CertificateMonitor..."
    Import-AgentCommonModule -ModuleFileName 'CertificateMonitor.psm1' -GlobalScope
    Write-Host "[DEBUG] CertificateMonitor imported successfully"

    Write-Host "[DEBUG] Importing ConfigManager..."
    Import-AgentCommonModule -ModuleFileName 'ConfigManager.psm1' -GlobalScope
    Write-Host "[DEBUG] ConfigManager imported successfully"

    Write-Host "[DEBUG] Importing CrlValidator..."
    Import-AgentCommonModule -ModuleFileName 'CrlValidator.psm1' -GlobalScope
    Write-Host "[DEBUG] CrlValidator imported successfully"

    Write-Host "[DEBUG] Importing EstClient..."
    Import-Module "./EstClient.psm1" -Force -Global -ErrorAction Stop
    Write-Host "[DEBUG] EstClient imported successfully"

    Write-Host "[DEBUG] Importing BootstrapTokenManager..."
    Import-Module "./BootstrapTokenManager.psm1" -Force -Global -ErrorAction Stop
    Write-Host "[DEBUG] BootstrapTokenManager imported successfully"

    Write-Host "[DEBUG] All modules imported successfully"
}
catch {
    Write-Host "[FATAL] Failed to import required modules: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "[FATAL] Stack trace: $($_.ScriptStackTrace)" -ForegroundColor Red
    exit 1
}

#endregion

#region Configuration and Initialization

$script:AgentEnvPrefixes = Get-AgentEnvPrefixList -DefaultPrefix "EST_"

# Load agent configuration from YAML (with environment variable overrides)
try {
    $config = Read-AgentConfig -ConfigFilePath '/agent/config.yaml' -EnvVarPrefixes $script:AgentEnvPrefixes
    Write-LogInfo -Message 'Agent started' -Context @{
        ConfigFile = '/agent/config.yaml'
    }
}
catch {
    Write-LogError -Message 'Failed to load agent configuration' -Context @{
        Error = $_.Exception.Message
    }
    exit 1
}

# Extract configuration values into named variables for readability
$pkiUrl = $config.pki_url
$certPath = $config.cert_path
$keyPath = $config.key_path
$deviceName = if ($config.device_name) { $config.device_name } else { $config.domain_name }
$renewalThreshold = if ($config.renewal_threshold_pct) { $config.renewal_threshold_pct } else { 75 }
$checkInterval = if ($config.check_interval_sec) { $config.check_interval_sec } else { 60 }
$provisionerName = 'est-provisioner'  # Standard EST provisioner name for step-ca

Write-LogInfo -Message 'Configuration loaded successfully' -Context @{
    PkiUrl = $pkiUrl
    CertPath = $certPath
    KeyPath = $keyPath
    DeviceName = $deviceName
    RenewalThresholdPercent = $renewalThreshold
    CheckIntervalSeconds = $checkInterval
}

# Load bootstrap authentication (token or certificate)
# Bootstrap certificate takes precedence over bootstrap token if available
$bootstrapCertPath = $env:EST_BOOTSTRAP_CERT_PATH
$bootstrapKeyPath = $env:EST_BOOTSTRAP_KEY_PATH
$bootstrapToken = ""

if (-not [string]::IsNullOrEmpty($bootstrapCertPath) -and -not [string]::IsNullOrEmpty($bootstrapKeyPath)) {
    # Bootstrap certificate authentication
    if (Test-Path $bootstrapCertPath) {
        Write-LogInfo -Message 'Bootstrap certificate authentication configured' -Context @{
            CertPath = $bootstrapCertPath
            KeyPath = $bootstrapKeyPath
        }
    }
    else {
        Write-LogWarn -Message 'Bootstrap certificate path configured but file not found, falling back to token' -Context @{
            CertPath = $bootstrapCertPath
        }
        # Fall back to token
        try {
            $bootstrapToken = Get-BootstrapToken -Config $config
            Write-LogInfo -Message 'Bootstrap token loaded (fallback)'
        }
        catch {
            Write-LogError -Message 'Failed to load bootstrap authentication (certificate missing and token unavailable)' -Context @{
                Error = $_.Exception.Message
            }
            exit 1
        }
    }
}
else {
    # Bootstrap token authentication
    try {
        $bootstrapToken = Get-BootstrapToken -Config $config
        Write-LogInfo -Message 'Bootstrap token loaded'
    }
    catch {
        Write-LogError -Message 'Failed to load bootstrap token (required for initial enrollment)' -Context @{
            Error = $_.Exception.Message
        }
        exit 1
    }
}

#endregion

#region Graceful Shutdown Handler

# Initialize shutdown flag (script-scoped for access in event handler)
$script:shutdownRequested = $false

# Register event handler for graceful shutdown (SIGTERM, SIGINT)
Register-EngineEvent -SourceIdentifier PowerShell.Exiting -Action {
    $script:shutdownRequested = $true
} | Out-Null

#endregion

#region Main Agent Loop

Write-LogInfo -Message 'Entering main certificate lifecycle loop' -Context @{
    CheckIntervalSeconds = $checkInterval
    RenewalThresholdPercent = $renewalThreshold
}

while (-not $script:shutdownRequested) {
    try {
        #region Certificate Check Phase

        $enrollmentType = $null
        $certInfo = $null
        $lifetimeElapsed = 0

        if (-not (Test-CertificateExists -Path $certPath)) {
            # Certificate file does not exist → Initial Enrollment required
            $enrollmentType = 'initial'
            Write-LogInfo -Message 'No certificate found - performing initial enrollment'
        }
        else {
            # Certificate exists → Check expiry status
            try {
                $certInfo = Get-CertificateInfo -Path $certPath
                $lifetimeElapsed = $certInfo.LifetimeElapsedPercent

                Write-LogDebug -Message 'Certificate status checked' -Context @{
                    Subject = $certInfo.Subject
                    NotBefore = $certInfo.NotBefore
                    NotAfter = $certInfo.NotAfter
                    LifetimeElapsedPercent = $lifetimeElapsed
                    DaysRemaining = $certInfo.DaysRemaining
                }

                # CRL Validation - Check if certificate is revoked
                if ($config.ContainsKey('crl') -and $config.crl.enabled) {
                    try {
                        $maxAge = if ($config.crl.max_age_hours) { $config.crl.max_age_hours } else { 24.0 }
                        $crlUpdateResult = Update-CrlCache `
                            -Url $config.crl.url `
                            -CachePath $config.crl.cache_path `
                            -MaxAgeHours $maxAge

                        if ($null -eq $crlUpdateResult.Error) {
                            Write-LogInfo -Message 'CRL cache updated' -Context @{
                                crl_age_hours = [math]::Round($crlUpdateResult.CrlAge, 2)
                                revoked_count = $crlUpdateResult.RevokedCount
                                downloaded = $crlUpdateResult.Downloaded
                            }

                            $revoked = Test-CertificateRevoked `
                                -CertificatePath $certPath `
                                -CrlPath $config.crl.cache_path

                            if ($revoked -eq $true) {
                                Write-LogWarn -Message 'Certificate is REVOKED - forcing re-enrollment' -Context @{
                                    cert_path = $certPath
                                }
                                $lifetimeElapsed = 100  # Force renewal
                            }
                            elseif ($revoked -eq $false) {
                                Write-LogInfo -Message 'Certificate is VALID (not revoked)' -Context @{
                                    cert_path = $certPath
                                }
                            }
                        }
                    }
                    catch {
                        Write-LogWarn -Message 'CRL validation failed' -Context @{
                            error = $_.Exception.Message
                        }
                    }
                }

                # Check if certificate is approaching expiration
                if ($lifetimeElapsed -gt $renewalThreshold) {
                    $enrollmentType = 're-enrollment'
                    Write-LogInfo -Message "Certificate expiring ($lifetimeElapsed% elapsed) - performing re-enrollment" -Context @{
                        Subject = $certInfo.Subject
                        LifetimeElapsedPercent = $lifetimeElapsed
                        RenewalThresholdPercent = $renewalThreshold
                        NotAfter = $certInfo.NotAfter
                    }
                }
                else {
                    # Certificate is valid and not expiring yet
                    Write-LogDebug -Message 'Certificate valid, no action needed' -Context @{
                        LifetimeElapsedPercent = $lifetimeElapsed
                        DaysRemaining = $certInfo.DaysRemaining
                    }
                }
            }
            catch {
                # Certificate file exists but is corrupted/invalid → Treat as missing
                Write-LogWarn -Message 'Certificate file exists but is invalid, treating as missing' -Context @{
                    CertPath = $certPath
                    Error = $_.Exception.Message
                }
                $enrollmentType = 'initial'
            }
        }

        #endregion

        #region Enrollment Execution Phase

        if ($enrollmentType -eq 'initial') {
            #region Initial Enrollment Workflow

            try {
                Write-LogInfo -Message 'Starting initial enrollment workflow'

                # Step 1: Generate RSA key pair
                # Re-import modules to ensure functions are available in loop scope
                Import-AgentCommonModule -ModuleFileName 'CryptoHelper.psm1'
                Import-AgentCommonModule -ModuleFileName 'FileOperations.psm1'
                $rsa = [System.Security.Cryptography.RSA]::Create(2048)
                Write-LogDebug -Message 'RSA key pair generated (2048-bit)'

                # Step 2: Generate CSR
                $subjectDN = "CN=$deviceName"
                $csrPem = New-CertificateRequest -SubjectDN $subjectDN -SubjectAlternativeNames @() -RsaKey $rsa
                Write-LogDebug -Message 'CSR generated' -Context @{
                    Subject = $subjectDN
                }

                # Step 3: Execute EST initial enrollment
                $certPem = Invoke-EstEnrollment `
                    -PkiUrl $pkiUrl `
                    -ProvisionerName $provisionerName `
                    -CsrPem $csrPem `
                    -BootstrapToken $bootstrapToken `
                    -BootstrapCertPath $bootstrapCertPath `
                    -BootstrapKeyPath $bootstrapKeyPath

                # Parse certificate to extract subject and expiry for logging
                # Write to temp file since X509Certificate2 requires file path or DER bytes
                $tempCertFile = "/tmp/temp-cert-$(Get-Random).pem"
                Set-Content -Path $tempCertFile -Value $certPem -NoNewline
                $tempCert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2($tempCertFile)
                Remove-Item $tempCertFile -Force -ErrorAction SilentlyContinue

                Write-LogInfo -Message "Certificate received: $($tempCert.Subject)" -Context @{
                    Subject = $tempCert.Subject
                    NotBefore = $tempCert.NotBefore.ToString('o')
                    NotAfter = $tempCert.NotAfter.ToString('o')
                    Issuer = $tempCert.Issuer
                    SerialNumber = $tempCert.SerialNumber
                }

                # Step 4: Export private key
                $keyPem = Export-PrivateKey -RsaKey $rsa
                Write-LogDebug -Message 'Private key exported to PEM format'

                # Step 5: Install certificate and key to volume
                Write-FileAtomic -Path $certPath -Content $certPem
                Write-FileAtomic -Path $keyPath -Content $keyPem

                # Set restrictive permissions (CRITICAL SECURITY)
                Set-FilePermissions -Path $keyPath -Mode '0600'  # Owner read/write only
                Set-FilePermissions -Path $certPath -Mode '0644'  # World-readable

                Write-LogInfo -Message 'Initial enrollment successful, certificate installed' -Context @{
                    CertPath = $certPath
                    KeyPath = $keyPath
                    ValidUntil = $tempCert.NotAfter.ToString('o')
                }
            }
            catch {
                Write-LogError -Message 'Initial enrollment failed, will retry on next cycle' -Context @{
                    Error = $_.Exception.Message
                    ErrorType = $_.Exception.GetType().FullName
                }
            }

            #endregion
        }
        elseif ($enrollmentType -eq 're-enrollment') {
            #region Re-Enrollment Workflow

            try {
                Write-LogInfo -Message 'Starting re-enrollment workflow (key rotation)'

                # Step 1: Generate NEW RSA key pair (key rotation best practice)
                # Re-import modules to ensure functions are available in loop scope
                Import-AgentCommonModule -ModuleFileName 'CryptoHelper.psm1'
                Import-AgentCommonModule -ModuleFileName 'FileOperations.psm1'
                $newRsa = [System.Security.Cryptography.RSA]::Create(2048)
                Write-LogDebug -Message 'New RSA key pair generated (2048-bit)'

                # Step 2: Generate CSR with same subject as existing certificate
                $subjectDN = $certInfo.Subject
                $csrPem = New-CertificateRequest -SubjectDN $subjectDN -SubjectAlternativeNames @() -RsaKey $newRsa
                Write-LogDebug -Message 'CSR generated for re-enrollment' -Context @{
                    Subject = $subjectDN
                }

                # Step 3: Execute EST re-enrollment (mTLS authentication with existing cert/key)
                $newCertPem = Invoke-EstReenrollment `
                    -PkiUrl $pkiUrl `
                    -ProvisionerName $provisionerName `
                    -CsrPem $csrPem `
                    -ExistingCertPath $certPath `
                    -ExistingKeyPath $keyPath

                # Parse new certificate for logging
                # Write to temp file since X509Certificate2 requires file path or DER bytes
                $tempCertFile = "/tmp/temp-cert-$(Get-Random).pem"
                Set-Content -Path $tempCertFile -Value $newCertPem -NoNewline
                $tempCert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2($tempCertFile)
                Remove-Item $tempCertFile -Force -ErrorAction SilentlyContinue

                Write-LogInfo -Message 'New certificate received' -Context @{
                    Subject = $tempCert.Subject
                    NotBefore = $tempCert.NotBefore.ToString('o')
                    NotAfter = $tempCert.NotAfter.ToString('o')
                    Issuer = $tempCert.Issuer
                    SerialNumber = $tempCert.SerialNumber
                }

                # Step 4: Export new private key
                $newKeyPem = Export-PrivateKey -RsaKey $newRsa
                Write-LogDebug -Message 'New private key exported to PEM format'

                # Step 5: Atomic replacement of certificate and key
                # Write to temporary files first
                Write-FileAtomic -Path "$certPath.new" -Content $newCertPem
                Write-FileAtomic -Path "$keyPath.new" -Content $newKeyPem
                Set-FilePermissions -Path "$keyPath.new" -Mode '0600'  # Set permissions before move

                # Atomic move (overwrites old files)
                Move-Item -Path "$certPath.new" -Destination $certPath -Force
                Move-Item -Path "$keyPath.new" -Destination $keyPath -Force

                # Ensure final permissions are correct
                Set-FilePermissions -Path $keyPath -Mode '0600'
                Set-FilePermissions -Path $certPath -Mode '0644'

                Write-LogInfo -Message 'New certificate installed' -Context @{
                    CertPath = $certPath
                    KeyPath = $keyPath
                    ValidUntil = $tempCert.NotAfter.ToString('o')
                    PreviousLifetimeElapsedPercent = $lifetimeElapsed
                }
            }
            catch {
                Write-LogError -Message 'Re-enrollment failed, will retry on next cycle' -Context @{
                    Error = $_.Exception.Message
                    ErrorType = $_.Exception.GetType().FullName
                    LifetimeElapsedPercent = $lifetimeElapsed
                }
            }

            #endregion
        }

        #endregion

        #region Sleep Phase

        Write-LogDebug -Message "Sleeping $checkInterval seconds"
        Start-Sleep -Seconds $checkInterval

        #endregion
    }
    catch {
        # Catch-all for unexpected errors in main loop
        Write-LogError -Message 'Unexpected error in main loop, continuing to next cycle' -Context @{
            Error = $_.Exception.Message
            ErrorType = $_.Exception.GetType().FullName
            StackTrace = $_.ScriptStackTrace
        }
        Start-Sleep -Seconds $checkInterval
    }
}

#endregion

#region Graceful Shutdown

Write-LogInfo -Message 'Graceful shutdown initiated'
exit 0

#endregion
