# ==============================================================================
# AcmeWorkflow.psm1 - ACME Certificate Lifecycle Workflow Module
# ==============================================================================
# This module implements the complete ACME certificate lifecycle workflow
# as a series of discrete, testable functions.
#
# Architecture: Business Logic Module
#   - Implements ACME-specific workflow steps
#   - Integrates with common modules (CRL, Config, Logging, Crypto, etc.)
#   - Provides functions for workflow orchestrator to call
#   - No direct workflow orchestration (handled by WorkflowOrchestrator)
#
# Workflow Steps:
#   1. Monitor: Check certificate status and determine if action needed
#   2. Decide: Determine appropriate action (enroll, renew, skip)
#   3. Execute: Perform ACME protocol operations
#   4. Validate: Verify certificate installation and service reload
#
# Functions:
#   - Step-MonitorCertificate: Monitors certificate status and expiry
#   - Step-DecideAction: Determines what action to take
#   - Step-ExecuteAcmeProtocol: Executes ACME enrollment/renewal
#   - Step-ValidateDeployment: Validates certificate deployment
#   - Initialize-AcmeWorkflowSteps: Registers all workflow steps
#
# Usage:
#   Import-Module ./AcmeWorkflow.psm1
#   Import-Module ../common/WorkflowOrchestrator.psm1
#   Initialize-AcmeWorkflowSteps
#   Start-WorkflowLoop -Steps @("Monitor", "Decide", "Execute", "Validate")
# ==============================================================================

# NOTE: Required modules (Logger, CertificateMonitor, CrlValidator, CryptoHelper, FileOperations)
# are imported by the calling script (acme-agent.ps1) before this workflow module is loaded.
# Do not import them here, as $PSScriptRoot is empty when modules are loaded via Import-Module

# ==============================================================================
# Step-MonitorCertificate
# ==============================================================================
# Monitors current certificate status, expiry, and CRL revocation status
#
# Parameters:
#   -Context: Workflow context containing config and state
#
# Returns: None (updates context state)
# ==============================================================================
function Step-MonitorCertificate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Context
    )

    $config = $Context.Config
    $state = $Context.State

    Write-Verbose "[ACME:Monitor] Checking certificate status..."

    $certPath = $config.cert_path
    $certExists = Test-Path $certPath

    $state.CertificateStatus.Exists = $certExists

    if ($certExists) {
        Write-Verbose "[ACME:Monitor] Certificate exists at: $certPath"

        # Get certificate expiry and lifetime percentage
        $certInfo = Get-CertificateInfo -Path $certPath
        $state.CertificateStatus.ExpiryDate = $certInfo.ExpiryDate
        $state.CertificateStatus.LifetimePercentage = $certInfo.LifetimePercentage

        Write-Verbose "[ACME:Monitor] Certificate expires: $($certInfo.ExpiryDate)"
        Write-Verbose "[ACME:Monitor] Lifetime used: $($certInfo.LifetimePercentage)%"

        # Check CRL revocation status (if enabled)
        if ($config.crl.enabled) {
            Write-Verbose "[ACME:Monitor] Checking CRL revocation status..."

            # Update CRL cache
            $crlResult = Update-CrlCache `
                -Url $config.crl.url `
                -CachePath $config.crl.cache_path `
                -MaxAgeHours $config.crl.max_age_hours

            if ($crlResult.Updated -or (Test-Path $config.crl.cache_path)) {
                # Check if certificate is revoked
                $revoked = Test-CertificateRevoked `
                    -CertificatePath $certPath `
                    -CrlPath $config.crl.cache_path

                $state.CertificateStatus.Revoked = ($revoked -eq $true)

                if ($state.CertificateStatus.Revoked) {
                    Write-Warning "[ACME:Monitor] Certificate is REVOKED! Immediate renewal required."
                } else {
                    Write-Verbose "[ACME:Monitor] Certificate is not revoked"
                }
            } else {
                Write-Warning "[ACME:Monitor] Failed to update CRL, skipping revocation check"
            }
        }

        # Determine if renewal is required
        $renewalThreshold = $config.renewal_threshold_pct
        $state.CertificateStatus.RenewalRequired = `
            ($state.CertificateStatus.LifetimePercentage -ge $renewalThreshold) -or `
            $state.CertificateStatus.Revoked

        if ($state.CertificateStatus.RenewalRequired) {
            Write-Verbose "[ACME:Monitor] Renewal required (threshold: $renewalThreshold%)"
        } else {
            Write-Verbose "[ACME:Monitor] Certificate is valid, no renewal needed"
        }
    } else {
        Write-Verbose "[ACME:Monitor] Certificate does not exist, enrollment required"
        $state.CertificateStatus.RenewalRequired = $true
    }

    return @{
        CertificateExists = $certExists
        RenewalRequired = $state.CertificateStatus.RenewalRequired
        Revoked = $state.CertificateStatus.Revoked
    }
}

# ==============================================================================
# Step-DecideAction
# ==============================================================================
# Determines what action to take based on certificate status
#
# Parameters:
#   -Context: Workflow context containing config and state
#
# Returns: Hashtable with decision (action: "enroll"|"renew"|"skip")
# ==============================================================================
function Step-DecideAction {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Context
    )

    $state = $Context.State

    $decision = @{
        Action = "skip"
        Reason = ""
    }

    if (-not $state.CertificateStatus.Exists) {
        $decision.Action = "enroll"
        $decision.Reason = "Certificate does not exist"
    }
    elseif ($state.CertificateStatus.Revoked) {
        $decision.Action = "renew"
        $decision.Reason = "Certificate is revoked"
    }
    elseif ($state.CertificateStatus.RenewalRequired) {
        $decision.Action = "renew"
        $decision.Reason = "Certificate lifetime threshold exceeded"
    }
    else {
        $decision.Action = "skip"
        $decision.Reason = "Certificate is valid and not due for renewal"
    }

    Write-Verbose "[ACME:Decide] Action: $($decision.Action) - $($decision.Reason)"

    return $decision
}

# ==============================================================================
# Step-ExecuteAcmeProtocol
# ==============================================================================
# Executes ACME protocol operations (enrollment or renewal) using Posh-ACME
#
# Parameters:
#   -Context: Workflow context containing config and state
#
# Returns: Hashtable with execution results
# ==============================================================================
function Step-ExecuteAcmeProtocol {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Context
    )

    $config = $Context.Config
    $state = $Context.State

    # Get decision from previous step (if available)
    $action = "renew"  # Default action
    if ($state.ContainsKey("LastDecision")) {
        $action = $state.LastDecision.Action
    }

    if ($action -eq "skip") {
        Write-Verbose "[ACME:Execute] Skipping ACME protocol execution"
        return @{
            Action = "skip"
            Success = $true
        }
    }

    Write-Verbose "[ACME:Execute] Executing ACME protocol: $action"

    try {
        # Initialize Posh-ACME environment if not already done
        if (-not $script:PoshAcmeInitialized) {
            Write-Verbose "[ACME:Execute] Initializing Posh-ACME environment..."

            # Set up Posh-ACME state directory
            $stateDir = $env:POSHACME_HOME
            if ([string]::IsNullOrWhiteSpace($stateDir)) {
                $stateDir = "/config/poshacme"
                $env:POSHACME_HOME = $stateDir
            }

            if (-not (Test-Path -Path $stateDir)) {
                New-Item -ItemType Directory -Path $stateDir -Force | Out-Null
            }

            # Configure Posh-ACME server
            $directoryPath = "/acme/acme/directory"
            $cleanUrl = $config.pki_url.TrimEnd('/')
            $cleanPath = $directoryPath.TrimStart('/')
            $directoryUrl = "${cleanUrl}/${cleanPath}"

            Write-Verbose "[ACME:Execute] Configuring Posh-ACME server: $directoryUrl"

            $serverArgs = @{ DirectoryUrl = $directoryUrl }

            # Skip certificate check for development
            if ($config.pki_environments -and $config.pki_environments.ContainsKey($config.environment)) {
                $envConfig = $config.pki_environments[$config.environment]
                if ($envConfig.ContainsKey('skip_certificate_check') -and $envConfig.skip_certificate_check) {
                    $serverArgs.Add("SkipCertificateCheck", $true)
                    Write-Verbose "[ACME:Execute] Skipping certificate validation for development"
                }
            }

            Set-PAServer @serverArgs

            # Create or retrieve ACME account
            $account = Get-PAAccount
            if (-not $account -or $account.status -ne 'valid') {
                Write-Verbose "[ACME:Execute] Creating new Posh-ACME account..."
                $accountParams = @{ AcceptTOS = $true }
                $account = New-PAAccount @accountParams
            } else {
                Write-Verbose "[ACME:Execute] Using existing Posh-ACME account: $($account.ID)"
            }

            $script:PoshAcmeInitialized = $true
        }

        # Build New-PACertificate parameters
        $certParams = @{
            Domain = @($config.domain_name)
            Force = $true
        }

        # Set up HTTP-01 challenge handling with WebRoot plugin
        $challengeDir = "/challenge"
        if (-not (Test-Path -Path $challengeDir)) {
            New-Item -ItemType Directory -Path $challengeDir -Force | Out-Null
        }

        $certParams['Plugin'] = 'WebRoot'
        $certParams['PluginArgs'] = @{
            'WRPath' = $challengeDir
        }

        Write-Verbose "[ACME:Execute] Requesting certificate via ACME..."
        Write-Verbose "[ACME:Execute] Domain: $($config.domain_name)"
        Write-Verbose "[ACME:Execute] Challenge directory: $challengeDir"

        # Request certificate using Posh-ACME
        $paCertificate = New-PACertificate @certParams

        if (-not $paCertificate) {
            throw "Certificate request failed - no certificate returned"
        }

        Write-Verbose "[ACME:Execute] Certificate issued successfully"
        Write-Verbose "[ACME:Execute] Subject: $($paCertificate.Subject)"
        Write-Verbose "[ACME:Execute] Not After: $($paCertificate.NotAfter)"

        # Save certificate and key files
        $certContent = Get-Content -LiteralPath $paCertificate.CertFile -Raw
        $keyContent = Get-Content -LiteralPath $paCertificate.KeyFile -Raw

        # Determine which certificate content to save
        $mainCertContent = $certContent
        if ($config.ContainsKey('certificate_chain') -and $config.certificate_chain.enabled) {
            if ($config.certificate_chain.installation.install_full_chain_to_cert_path) {
                $mainCertContent = Get-Content -LiteralPath $paCertificate.FullChainFile -Raw
                Write-Verbose "[ACME:Execute] Using full chain for main certificate file"
            }
        }

        # Save private key
        Write-FileAtomic -Path $config.key_path -Content $keyContent
        Set-FilePermissions -Path $config.key_path -Mode "0600"

        # Save certificate
        Write-FileAtomic -Path $config.cert_path -Content $mainCertContent
        Set-FilePermissions -Path $config.cert_path -Mode "0644"

        Write-Verbose "[ACME:Execute] Certificate and key files saved successfully"

        # Save additional chain files if configured
        if ($config.ContainsKey('certificate_chain') -and $config.certificate_chain.enabled -and
            $config.certificate_chain.installation.create_separate_chain_files) {

            if ($config.certificate_chain.full_chain_path) {
                $fullChainContent = Get-Content -LiteralPath $paCertificate.FullChainFile -Raw
                Write-FileAtomic -Path $config.certificate_chain.full_chain_path -Content $fullChainContent
                Set-FilePermissions -Path $config.certificate_chain.full_chain_path -Mode "0644"
                Write-Verbose "[ACME:Execute] Saved full chain file"
            }

            if ($config.certificate_chain.intermediates_path -and (Test-Path $paCertificate.ChainFile)) {
                $chainContent = Get-Content -LiteralPath $paCertificate.ChainFile -Raw
                Write-FileAtomic -Path $config.certificate_chain.intermediates_path -Content $chainContent
                Set-FilePermissions -Path $config.certificate_chain.intermediates_path -Mode "0644"
                Write-Verbose "[ACME:Execute] Saved intermediates file"
            }
        }

        $result = @{
            Action = $action
            Success = $true
            CertificatePath = $config.cert_path
            KeyPath = $config.key_path
            Subject = $paCertificate.Subject
            NotAfter = $paCertificate.NotAfter
            Message = "Certificate successfully enrolled/renewed via ACME"
        }

        Write-Verbose "[ACME:Execute] ACME protocol execution completed successfully"
        return $result
    }
    catch {
        Write-Error "[ACME:Execute] ACME protocol execution failed: $_"
        return @{
            Action = $action
            Success = $false
            CertificatePath = $config.cert_path
            Message = "ACME execution failed: $($_.Exception.Message)"
            Error = $_.Exception.Message
        }
    }
}

# ==============================================================================
# Step-ValidateDeployment
# ==============================================================================
# Validates certificate deployment and triggers service reload
#
# Parameters:
#   -Context: Workflow context containing config and state
#
# Returns: Hashtable with validation results
# ==============================================================================
function Step-ValidateDeployment {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Context
    )

    $config = $Context.Config
    $certPath = $config.cert_path
    $keyPath = $config.key_path

    Write-Verbose "[ACME:Validate] Validating certificate deployment..."

    $result = @{
        CertificateValid = $false
        KeyValid = $false
        ServiceReloaded = $false
        Message = ""
    }

    # Validate certificate file exists
    if (Test-Path $certPath) {
        $result.CertificateValid = $true
        Write-Verbose "[ACME:Validate] Certificate file exists"
    } else {
        Write-Warning "[ACME:Validate] Certificate file not found: $certPath"
        $result.Message = "Certificate file not found"
        return $result
    }

    # Validate private key file exists
    if (Test-Path $keyPath) {
        $result.KeyValid = $true
        Write-Verbose "[ACME:Validate] Private key file exists"
    } else {
        Write-Warning "[ACME:Validate] Private key file not found: $keyPath"
        $result.Message = "Private key file not found"
        return $result
    }

    # Trigger service reload (if configured)
    # NOTE: service_reload config not implemented yet
    # if ($config.service_reload.enabled) {
    #     Write-Verbose "[ACME:Validate] Triggering service reload..."
    #     try {
    #         # This would integrate with ServiceReloadController module
    #         $result.ServiceReloaded = $true
    #         Write-Verbose "[ACME:Validate] Service reload triggered successfully"
    #     }
    #     catch {
    #         Write-Warning "[ACME:Validate] Service reload failed: $_"
    #         $result.Message = "Service reload failed"
    #     }
    # }

    if ($result.CertificateValid -and $result.KeyValid) {
        $result.Message = "Deployment validated successfully"
    }

    return $result
}

# ==============================================================================
# Initialize-AcmeWorkflowSteps
# ==============================================================================
# Registers all ACME workflow steps with the WorkflowOrchestrator
#
# Parameters: None
#
# Returns: None
# ==============================================================================
function Initialize-AcmeWorkflowSteps {
    [CmdletBinding()]
    param()

    Write-Verbose "[ACME:Init] Initializing ACME workflow steps..."

    # NOTE: WorkflowOrchestrator is already imported by acme-agent.ps1 before this module loads

    # Register Monitor step
    Register-WorkflowStep `
        -Name "Monitor" `
        -Description "Monitor certificate status and expiry" `
        -ContinueOnError $true `
        -ScriptBlock {
            param($Context)
            Step-MonitorCertificate -Context $Context
        }

    # Register Decide step
    Register-WorkflowStep `
        -Name "Decide" `
        -Description "Determine action based on certificate status" `
        -ContinueOnError $false `
        -ScriptBlock {
            param($Context)
            $decision = Step-DecideAction -Context $Context
            $Context.State.LastDecision = $decision
            return $decision
        }

    # Register Execute step
    Register-WorkflowStep `
        -Name "Execute" `
        -Description "Execute ACME protocol operations" `
        -ContinueOnError $false `
        -ScriptBlock {
            param($Context)
            Step-ExecuteAcmeProtocol -Context $Context
        }

    # Register Validate step
    Register-WorkflowStep `
        -Name "Validate" `
        -Description "Validate deployment and trigger service reload" `
        -ContinueOnError $true `
        -ScriptBlock {
            param($Context)
            Step-ValidateDeployment -Context $Context
        }

    Write-Verbose "[ACME:Init] ACME workflow steps registered"
}

# ==============================================================================
# Export module functions
# ==============================================================================
Export-ModuleMember -Function @(
    'Step-MonitorCertificate',
    'Step-DecideAction',
    'Step-ExecuteAcmeProtocol',
    'Step-ValidateDeployment',
    'Initialize-AcmeWorkflowSteps'
)
