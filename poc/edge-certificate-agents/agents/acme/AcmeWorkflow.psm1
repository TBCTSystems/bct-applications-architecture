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

    Write-LogInfo "Checking certificate status" -Context @{
        step = "Monitor"
        agent_type = "acme"
        operation = "certificate_check"
    }

    $certPath = $config.cert_path
    $certExists = Test-Path $certPath

    $state.CertificateStatus.Exists = $certExists

    if ($certExists) {
        Write-LogInfo "Certificate exists" -Context @{
            step = "Monitor"
            agent_type = "acme"
            cert_path = $certPath
            operation = "certificate_check"
        }

        # Get certificate expiry and lifetime percentage
        $certInfo = Get-CertificateInfo -Path $certPath
        $state.CertificateStatus.ExpiryDate = $certInfo.NotAfter
        $state.CertificateStatus.LifetimePercentage = $certInfo.LifetimeElapsedPercent

        Write-LogInfo "Certificate inventory status" -Context @{
            step = "Monitor"
            agent_type = "acme"
            cert_subject = $certInfo.Subject
            cert_thumbprint = $certInfo.Thumbprint
            cert_serial = $certInfo.SerialNumber
            expiry_date = $certInfo.NotAfter.ToString("yyyy-MM-ddTHH:mm:ssZ")
            lifetime_percentage = $certInfo.LifetimeElapsedPercent
            days_remaining = $certInfo.DaysRemaining
            operation = "certificate_inventory"
        }

        # Check CRL revocation status (if enabled)
        if ($config.crl.enabled) {
            Write-LogInfo "Checking CRL revocation status" -Context @{
                step = "Monitor"
                agent_type = "acme"
                crl_url = $config.crl.url
                operation = "crl_check"
            }

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
                    Write-LogWarn "Certificate is REVOKED! Immediate renewal required" -Context @{
                        step = "Monitor"
                        agent_type = "acme"
                        cert_path = $certPath
                        revoked = $true
                        operation = "crl_check"
                        status = "revoked"
                    }
                } else {
                    Write-LogInfo "Certificate is not revoked" -Context @{
                        step = "Monitor"
                        agent_type = "acme"
                        revoked = $false
                        operation = "crl_check"
                        status = "valid"
                    }
                }
            } else {
                Write-LogWarn "Failed to update CRL, skipping revocation check" -Context @{
                    step = "Monitor"
                    agent_type = "acme"
                    crl_url = $config.crl.url
                    operation = "crl_check"
                    status = "failed"
                }
            }
        }

        # Determine if renewal is required
        $renewalThreshold = $config.renewal_threshold_pct
        $state.CertificateStatus.RenewalRequired = `
            ($state.CertificateStatus.LifetimePercentage -ge $renewalThreshold) -or `
            $state.CertificateStatus.Revoked

        if ($state.CertificateStatus.RenewalRequired) {
            Write-LogInfo "Renewal required" -Context @{
                step = "Monitor"
                agent_type = "acme"
                renewal_threshold_pct = $renewalThreshold
                lifetime_percentage = $state.CertificateStatus.LifetimePercentage
                revoked = $state.CertificateStatus.Revoked
                operation = "renewal_check"
                status = "required"
            }
        } else {
            Write-LogInfo "Certificate is valid, no renewal needed" -Context @{
                step = "Monitor"
                agent_type = "acme"
                lifetime_percentage = $state.CertificateStatus.LifetimePercentage
                renewal_threshold_pct = $renewalThreshold
                operation = "renewal_check"
                status = "valid"
            }
        }
    } else {
        Write-LogInfo "Certificate does not exist, enrollment required" -Context @{
            step = "Monitor"
            agent_type = "acme"
            cert_path = $certPath
            operation = "certificate_check"
            status = "missing"
        }
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

    Write-LogInfo "Decision made" -Context @{
        step = "Decide"
        agent_type = "acme"
        action = $decision.Action
        reason = $decision.Reason
        operation = "decision"
    }

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
        Write-LogInfo "Skipping ACME protocol execution" -Context @{
            step = "Execute"
            agent_type = "acme"
            action = "skip"
            operation = "acme_protocol"
            status = "skipped"
        }
        return @{
            Action = "skip"
            Success = $true
        }
    }

    Write-LogInfo "Executing ACME protocol" -Context @{
        step = "Execute"
        agent_type = "acme"
        action = $action
        operation = "acme_protocol"
        status = "started"
    }

    try {
        # Initialize Posh-ACME environment if not already done
        if (-not $script:PoshAcmeInitialized) {
            Write-LogInfo "Initializing Posh-ACME environment" -Context @{
                step = "Execute"
                agent_type = "acme"
                operation = "poshacme_init"
            }

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

            Write-LogInfo "Configuring Posh-ACME server" -Context @{
                step = "Execute"
                agent_type = "acme"
                directory_url = $directoryUrl
                operation = "poshacme_config"
            }

            $serverArgs = @{ DirectoryUrl = $directoryUrl }

            # Skip certificate check for development
            if ($config.pki_environments -and $config.pki_environments.ContainsKey($config.environment)) {
                $envConfig = $config.pki_environments[$config.environment]
                if ($envConfig.ContainsKey('skip_certificate_check') -and $envConfig.skip_certificate_check) {
                    $serverArgs.Add("SkipCertificateCheck", $true)
                    Write-LogInfo "Skipping certificate validation for development" -Context @{
                        step = "Execute"
                        agent_type = "acme"
                        environment = $config.environment
                        operation = "poshacme_config"
                    }
                }
            }

            Set-PAServer @serverArgs

            # Create or retrieve ACME account
            $account = Get-PAAccount
            if (-not $account -or $account.status -ne 'valid') {
                Write-LogInfo "Creating new Posh-ACME account" -Context @{
                    step = "Execute"
                    agent_type = "acme"
                    operation = "acme_account"
                    status = "creating"
                }
                $accountParams = @{ AcceptTOS = $true }
                $account = New-PAAccount @accountParams
            } else {
                Write-LogInfo "Using existing Posh-ACME account" -Context @{
                    step = "Execute"
                    agent_type = "acme"
                    account_id = $account.ID
                    operation = "acme_account"
                    status = "existing"
                }
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

        Write-LogInfo "Requesting certificate via ACME" -Context @{
            step = "Execute"
            agent_type = "acme"
            domain = $config.domain_name
            challenge_dir = $challengeDir
            challenge_type = "http-01"
            operation = "certificate_request"
            status = "started"
        }

        # Request certificate using Posh-ACME
        $paCertificate = New-PACertificate @certParams

        if (-not $paCertificate) {
            throw "Certificate request failed - no certificate returned"
        }

        Write-LogInfo "Certificate issued successfully" -Context @{
            step = "Execute"
            agent_type = "acme"
            subject = $paCertificate.Subject
            not_after = $paCertificate.NotAfter.ToString("yyyy-MM-ddTHH:mm:ssZ")
            operation = "certificate_request"
            status = "success"
        }

        # Save certificate and key files
        $certContent = Get-Content -LiteralPath $paCertificate.CertFile -Raw
        $keyContent = Get-Content -LiteralPath $paCertificate.KeyFile -Raw

        # Determine which certificate content to save
        $mainCertContent = $certContent
        if ($config.ContainsKey('certificate_chain') -and $config.certificate_chain.enabled) {
            if ($config.certificate_chain.installation.install_full_chain_to_cert_path) {
                $mainCertContent = Get-Content -LiteralPath $paCertificate.FullChainFile -Raw
                Write-LogInfo "Using full chain for main certificate file" -Context @{
                    step = "Execute"
                    agent_type = "acme"
                    operation = "certificate_save"
                    chain_type = "full"
                }
            }
        }

        # Save private key
        Write-FileAtomic -Path $config.key_path -Content $keyContent
        Set-FilePermissions -Path $config.key_path -Mode "0600"

        # Save certificate
        Write-FileAtomic -Path $config.cert_path -Content $mainCertContent
        Set-FilePermissions -Path $config.cert_path -Mode "0644"

        Write-LogInfo "Certificate and key files saved successfully" -Context @{
            step = "Execute"
            agent_type = "acme"
            cert_path = $config.cert_path
            key_path = $config.key_path
            operation = "certificate_save"
            status = "success"
        }

        # Save additional chain files if configured
        if ($config.ContainsKey('certificate_chain') -and $config.certificate_chain.enabled -and
            $config.certificate_chain.installation.create_separate_chain_files) {

            if ($config.certificate_chain.full_chain_path) {
                $fullChainContent = Get-Content -LiteralPath $paCertificate.FullChainFile -Raw
                Write-FileAtomic -Path $config.certificate_chain.full_chain_path -Content $fullChainContent
                Set-FilePermissions -Path $config.certificate_chain.full_chain_path -Mode "0644"
                Write-LogInfo "Saved full chain file" -Context @{
                    step = "Execute"
                    agent_type = "acme"
                    full_chain_path = $config.certificate_chain.full_chain_path
                    operation = "certificate_save"
                    chain_type = "full"
                }
            }

            if ($config.certificate_chain.intermediates_path -and (Test-Path $paCertificate.ChainFile)) {
                $chainContent = Get-Content -LiteralPath $paCertificate.ChainFile -Raw
                Write-FileAtomic -Path $config.certificate_chain.intermediates_path -Content $chainContent
                Set-FilePermissions -Path $config.certificate_chain.intermediates_path -Mode "0644"
                Write-LogInfo "Saved intermediates file" -Context @{
                    step = "Execute"
                    agent_type = "acme"
                    intermediates_path = $config.certificate_chain.intermediates_path
                    operation = "certificate_save"
                    chain_type = "intermediates"
                }
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

        Write-LogInfo "ACME protocol execution completed successfully" -Context @{
            step = "Execute"
            agent_type = "acme"
            action = $action
            cert_path = $config.cert_path
            subject = $paCertificate.Subject
            operation = "acme_protocol"
            status = "success"
        }
        return $result
    }
    catch {
        Write-LogError "ACME protocol execution failed" -Context @{
            step = "Execute"
            agent_type = "acme"
            action = $action
            cert_path = $config.cert_path
            error = $_.Exception.Message
            operation = "acme_protocol"
            status = "failed"
        }
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

    Write-LogInfo "Validating certificate deployment" -Context @{
        step = "Validate"
        agent_type = "acme"
        cert_path = $certPath
        key_path = $keyPath
        operation = "deployment_validation"
        status = "started"
    }

    $result = @{
        CertificateValid = $false
        KeyValid = $false
        ServiceReloaded = $false
        Message = ""
    }

    # Validate certificate file exists
    if (Test-Path $certPath) {
        $result.CertificateValid = $true
        Write-LogInfo "Certificate file exists" -Context @{
            step = "Validate"
            agent_type = "acme"
            cert_path = $certPath
            operation = "file_validation"
            status = "success"
        }
    } else {
        Write-LogWarn "Certificate file not found" -Context @{
            step = "Validate"
            agent_type = "acme"
            cert_path = $certPath
            operation = "file_validation"
            status = "failed"
        }
        $result.Message = "Certificate file not found"
        return $result
    }

    # Validate private key file exists
    if (Test-Path $keyPath) {
        $result.KeyValid = $true
        Write-LogInfo "Private key file exists" -Context @{
            step = "Validate"
            agent_type = "acme"
            key_path = $keyPath
            operation = "file_validation"
            status = "success"
        }
    } else {
        Write-LogWarn "Private key file not found" -Context @{
            step = "Validate"
            agent_type = "acme"
            key_path = $keyPath
            operation = "file_validation"
            status = "failed"
        }
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

    Write-LogInfo "Initializing ACME workflow steps" -Context @{
        agent_type = "acme"
        operation = "workflow_init"
        status = "started"
    }

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

    Write-LogInfo "ACME workflow steps registered" -Context @{
        agent_type = "acme"
        operation = "workflow_init"
        status = "completed"
        steps_registered = 4
    }
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
