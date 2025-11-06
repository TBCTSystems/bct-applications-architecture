# ==============================================================================
# EstWorkflow.psm1 - EST Certificate Lifecycle Workflow Module
# ==============================================================================
# This module implements the complete EST certificate lifecycle workflow
# as a series of discrete, testable functions.
#
# Architecture: Business Logic Module
#   - Implements EST-specific workflow steps
#   - Integrates with common modules (CRL, Config, Logging, Crypto, etc.)
#   - Provides functions for workflow orchestrator to call
#   - No direct workflow orchestration (handled by WorkflowOrchestrator)
#
# Workflow Steps:
#   1. Monitor: Check certificate status and determine if action needed
#   2. Decide: Determine appropriate action (enroll, re-enroll, skip)
#   3. Execute: Perform EST protocol operations
#   4. Validate: Verify certificate installation
#
# Functions:
#   - Step-MonitorCertificate: Monitors certificate status and expiry
#   - Step-DecideAction: Determines what action to take
#   - Step-ExecuteEstProtocol: Executes EST enrollment/re-enrollment
#   - Step-ValidateDeployment: Validates certificate deployment
#   - Initialize-EstWorkflowSteps: Registers all workflow steps
#
# Usage:
#   Import-Module ./EstWorkflow.psm1
#   Import-Module ../common/WorkflowOrchestrator.psm1
#   Initialize-EstWorkflowSteps
#   Start-WorkflowLoop -Steps @("Monitor", "Decide", "Execute", "Validate")
# ==============================================================================

# NOTE: Required modules (Logger, CertificateMonitor, CrlValidator, CryptoHelper, FileOperations)
# are imported by the calling script (est-agent.ps1) before this workflow module is loaded.
# Do not import them here, as $PSScriptRoot is empty when modules are loaded via Import-Module

# ==============================================================================
# Step-MonitorCertificate
# ==============================================================================
# Monitors current certificate status, expiry, and CRL revocation status
#
# Parameters:
#   -Context: Workflow context containing config and state
#
# Returns: Hashtable with monitoring results
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
        agent_type = "est"
        operation = "certificate_check"
    }

    $certPath = $config.cert_path
    $certExists = Test-Path $certPath

    $state.CertificateStatus.Exists = $certExists

    if ($certExists) {
        Write-LogInfo "Certificate exists" -Context @{
            step = "Monitor"
            agent_type = "est"
            cert_path = $certPath
            operation = "certificate_check"
        }

        # Get certificate expiry and lifetime percentage
        $certInfo = Get-CertificateInfo -Path $certPath
        $state.CertificateStatus.ExpiryDate = $certInfo.ExpiryDate
        $state.CertificateStatus.LifetimePercentage = $certInfo.LifetimePercentage

        Write-LogInfo "Certificate expiry and lifetime status" -Context @{
            step = "Monitor"
            agent_type = "est"
            expiry_date = $certInfo.ExpiryDate.ToString("yyyy-MM-ddTHH:mm:ssZ")
            lifetime_percentage = $certInfo.LifetimePercentage
            operation = "certificate_check"
        }

        # Check CRL revocation status (if enabled)
        if ($config.crl.enabled) {
            Write-LogInfo "Checking CRL revocation status" -Context @{
                step = "Monitor"
                agent_type = "est"
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
                    Write-LogWarn "Certificate is REVOKED! Immediate re-enrollment required" -Context @{
                        step = "Monitor"
                        agent_type = "est"
                        cert_path = $certPath
                        revoked = $true
                        operation = "crl_check"
                        status = "revoked"
                    }
                } else {
                    Write-LogInfo "Certificate is not revoked" -Context @{
                        step = "Monitor"
                        agent_type = "est"
                        revoked = $false
                        operation = "crl_check"
                        status = "valid"
                    }
                }
            } else {
                Write-LogWarn "Failed to update CRL, skipping revocation check" -Context @{
                    step = "Monitor"
                    agent_type = "est"
                    crl_url = $config.crl.url
                    operation = "crl_check"
                    status = "failed"
                }
            }
        }

        # Determine if re-enrollment is required
        $renewalThreshold = $config.renewal_threshold_pct
        $state.CertificateStatus.RenewalRequired = `
            ($state.CertificateStatus.LifetimePercentage -ge $renewalThreshold) -or `
            $state.CertificateStatus.Revoked

        if ($state.CertificateStatus.RenewalRequired) {
            Write-LogInfo "Re-enrollment required" -Context @{
                step = "Monitor"
                agent_type = "est"
                renewal_threshold_pct = $renewalThreshold
                lifetime_percentage = $state.CertificateStatus.LifetimePercentage
                revoked = $state.CertificateStatus.Revoked
                operation = "renewal_check"
                status = "required"
            }
        } else {
            Write-LogInfo "Certificate is valid, no re-enrollment needed" -Context @{
                step = "Monitor"
                agent_type = "est"
                lifetime_percentage = $state.CertificateStatus.LifetimePercentage
                renewal_threshold_pct = $renewalThreshold
                operation = "renewal_check"
                status = "valid"
            }
        }
    } else {
        Write-LogInfo "Certificate does not exist, enrollment required" -Context @{
            step = "Monitor"
            agent_type = "est"
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
# Returns: Hashtable with decision (action: "enroll"|"reenroll"|"skip")
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
        AuthMode = "bootstrap"  # bootstrap or mtls
    }

    if (-not $state.CertificateStatus.Exists) {
        $decision.Action = "enroll"
        $decision.Reason = "Certificate does not exist"
        $decision.AuthMode = "bootstrap"
    }
    elseif ($state.CertificateStatus.Revoked) {
        $decision.Action = "reenroll"
        $decision.Reason = "Certificate is revoked"
        $decision.AuthMode = "bootstrap"  # Use bootstrap for revoked certs
    }
    elseif ($state.CertificateStatus.RenewalRequired) {
        $decision.Action = "reenroll"
        $decision.Reason = "Certificate lifetime threshold exceeded"
        $decision.AuthMode = "mtls"  # Use existing cert for mTLS
    }
    else {
        $decision.Action = "skip"
        $decision.Reason = "Certificate is valid and not due for re-enrollment"
    }

    Write-LogInfo "Decision made" -Context @{
        step = "Decide"
        agent_type = "est"
        action = $decision.Action
        reason = $decision.Reason
        auth_mode = $decision.AuthMode
        operation = "decision"
    }

    return $decision
}

# ==============================================================================
# Step-ExecuteEstProtocol
# ==============================================================================
# Executes EST protocol operations (enrollment or re-enrollment) using EstClient
#
# Parameters:
#   -Context: Workflow context containing config and state
#
# Returns: Hashtable with execution results
# ==============================================================================
function Step-ExecuteEstProtocol {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Context
    )

    $config = $Context.Config
    $state = $Context.State

    # Get decision from previous step (if available)
    $action = "reenroll"  # Default action
    $authMode = "bootstrap"  # Default auth mode

    if ($state.ContainsKey("LastDecision")) {
        $action = $state.LastDecision.Action
        $authMode = $state.LastDecision.AuthMode
    }

    if ($action -eq "skip") {
        Write-LogInfo "Skipping EST protocol execution" -Context @{
            step = "Execute"
            agent_type = "est"
            action = "skip"
            operation = "est_protocol"
            status = "skipped"
        }
        return @{
            Action = "skip"
            Success = $true
        }
    }

    Write-LogInfo "Executing EST protocol" -Context @{
        step = "Execute"
        agent_type = "est"
        action = $action
        auth_mode = $authMode
        operation = "est_protocol"
        status = "started"
    }

    try {
        # Determine device name (for CSR subject)
        $deviceName = if ($config.device_name) { $config.device_name } else { $config.domain_name }
        if ([string]::IsNullOrWhiteSpace($deviceName)) {
            $deviceName = "est-client-device"
        }

        # EST provisioner name (configured in OpenXPKI realm)
        $provisionerName = "default"

        if ($action -eq "enroll") {
            # Initial Enrollment using bootstrap token
            Write-LogInfo "Performing initial enrollment" -Context @{
                step = "Execute"
                agent_type = "est"
                device_name = $deviceName
                operation = "est_enrollment"
                enrollment_type = "initial"
                status = "started"
            }

            # Generate RSA key pair (2048-bit)
            $rsa = [System.Security.Cryptography.RSA]::Create(2048)
            Write-LogInfo "RSA key pair generated" -Context @{
                step = "Execute"
                agent_type = "est"
                key_size = 2048
                operation = "key_generation"
            }

            # Generate CSR
            $subjectDN = "CN=$deviceName"
            $csrPem = New-CertificateRequest -SubjectDN $subjectDN -SubjectAlternativeNames @() -RsaKey $rsa
            Write-LogInfo "CSR generated" -Context @{
                step = "Execute"
                agent_type = "est"
                subject = $subjectDN
                operation = "csr_generation"
            }

            # Get bootstrap token
            $bootstrapToken = Get-BootstrapToken -Config $config

            # Execute EST initial enrollment
            $certPem = Invoke-EstEnrollment `
                -PkiUrl $config.pki_url `
                -ProvisionerName $provisionerName `
                -CsrPem $csrPem `
                -BootstrapToken $bootstrapToken

            # Export private key
            $keyPem = Export-PrivateKey -RsaKey $rsa
            Write-LogInfo "Private key exported to PEM format" -Context @{
                step = "Execute"
                agent_type = "est"
                operation = "key_export"
            }

            # Save certificate and key
            Write-FileAtomic -Path $config.cert_path -Content $certPem
            Write-FileAtomic -Path $config.key_path -Content $keyPem

            # Set restrictive permissions (CRITICAL SECURITY)
            Set-FilePermissions -Path $config.key_path -Mode '0600'  # Owner read/write only
            Set-FilePermissions -Path $config.cert_path -Mode '0644'  # World-readable

            # Parse certificate for logging
            $tempCertFile = "/tmp/temp-cert-$(Get-Random).pem"
            Set-Content -Path $tempCertFile -Value $certPem -NoNewline
            $tempCert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2($tempCertFile)
            Remove-Item $tempCertFile -Force -ErrorAction SilentlyContinue

            Write-LogInfo "Initial enrollment successful" -Context @{
                step = "Execute"
                agent_type = "est"
                subject = $tempCert.Subject
                not_after = $tempCert.NotAfter.ToString("yyyy-MM-ddTHH:mm:ssZ")
                cert_path = $config.cert_path
                operation = "est_enrollment"
                enrollment_type = "initial"
                status = "success"
            }

            return @{
                Action = $action
                AuthMode = $authMode
                Success = $true
                CertificatePath = $config.cert_path
                KeyPath = $config.key_path
                Subject = $tempCert.Subject
                NotAfter = $tempCert.NotAfter
                Message = "Certificate successfully enrolled via EST (bootstrap)"
            }
        }
        elseif ($action -eq "reenroll") {
            # Re-enrollment using mTLS with existing certificate
            Write-LogInfo "Performing re-enrollment with key rotation" -Context @{
                step = "Execute"
                agent_type = "est"
                operation = "est_reenrollment"
                enrollment_type = "reenrollment"
                auth_mode = $authMode
                status = "started"
            }

            # Generate NEW RSA key pair (key rotation best practice)
            $newRsa = [System.Security.Cryptography.RSA]::Create(2048)
            Write-LogInfo "New RSA key pair generated" -Context @{
                step = "Execute"
                agent_type = "est"
                key_size = 2048
                operation = "key_generation"
            }

            # Get subject from existing certificate
            $existingCertInfo = Get-CertificateInfo -Path $config.cert_path
            $subjectDN = $existingCertInfo.Subject

            # Generate CSR with same subject as existing certificate
            $csrPem = New-CertificateRequest -SubjectDN $subjectDN -SubjectAlternativeNames @() -RsaKey $newRsa
            Write-LogInfo "CSR generated for re-enrollment" -Context @{
                step = "Execute"
                agent_type = "est"
                subject = $subjectDN
                operation = "csr_generation"
            }

            if ($authMode -eq "bootstrap") {
                # Use bootstrap token for re-enrollment (e.g., if cert was revoked)
                $bootstrapToken = Get-BootstrapToken -Config $config
                $newCertPem = Invoke-EstEnrollment `
                    -PkiUrl $config.pki_url `
                    -ProvisionerName $provisionerName `
                    -CsrPem $csrPem `
                    -BootstrapToken $bootstrapToken
            } else {
                # Use existing certificate for mTLS authentication
                $newCertPem = Invoke-EstReenrollment `
                    -PkiUrl $config.pki_url `
                    -ProvisionerName $provisionerName `
                    -CsrPem $csrPem `
                    -ExistingCertPath $config.cert_path `
                    -ExistingKeyPath $config.key_path
            }

            # Export new private key
            $newKeyPem = Export-PrivateKey -RsaKey $newRsa
            Write-LogInfo "New private key exported to PEM format" -Context @{
                step = "Execute"
                agent_type = "est"
                operation = "key_export"
            }

            # Atomic replacement: write to temp files first, then move
            Write-FileAtomic -Path "$($config.cert_path).new" -Content $newCertPem
            Write-FileAtomic -Path "$($config.key_path).new" -Content $newKeyPem
            Set-FilePermissions -Path "$($config.key_path).new" -Mode '0600'

            # Atomic move (overwrites old files)
            Move-Item -Path "$($config.cert_path).new" -Destination $config.cert_path -Force
            Move-Item -Path "$($config.key_path).new" -Destination $config.key_path -Force

            # Ensure final permissions are correct
            Set-FilePermissions -Path $config.key_path -Mode '0600'
            Set-FilePermissions -Path $config.cert_path -Mode '0644'

            # Parse new certificate for logging
            $tempCertFile = "/tmp/temp-cert-$(Get-Random).pem"
            Set-Content -Path $tempCertFile -Value $newCertPem -NoNewline
            $tempCert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2($tempCertFile)
            Remove-Item $tempCertFile -Force -ErrorAction SilentlyContinue

            Write-LogInfo "Re-enrollment successful" -Context @{
                step = "Execute"
                agent_type = "est"
                subject = $tempCert.Subject
                not_after = $tempCert.NotAfter.ToString("yyyy-MM-ddTHH:mm:ssZ")
                cert_path = $config.cert_path
                auth_mode = $authMode
                operation = "est_reenrollment"
                enrollment_type = "reenrollment"
                status = "success"
            }

            return @{
                Action = $action
                AuthMode = $authMode
                Success = $true
                CertificatePath = $config.cert_path
                KeyPath = $config.key_path
                Subject = $tempCert.Subject
                NotAfter = $tempCert.NotAfter
                Message = "Certificate successfully re-enrolled via EST ($authMode)"
            }
        }
        else {
            throw "Unknown action: $action"
        }
    }
    catch {
        Write-LogError "EST protocol execution failed" -Context @{
            step = "Execute"
            agent_type = "est"
            action = $action
            auth_mode = $authMode
            cert_path = $config.cert_path
            error = $_.Exception.Message
            operation = "est_protocol"
            status = "failed"
        }
        return @{
            Action = $action
            AuthMode = $authMode
            Success = $false
            CertificatePath = $config.cert_path
            Message = "EST execution failed: $($_.Exception.Message)"
            Error = $_.Exception.Message
        }
    }
}

# ==============================================================================
# Step-ValidateDeployment
# ==============================================================================
# Validates certificate deployment
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
        agent_type = "est"
        cert_path = $certPath
        key_path = $keyPath
        operation = "deployment_validation"
        status = "started"
    }

    $result = @{
        CertificateValid = $false
        KeyValid = $false
        Message = ""
    }

    # Validate certificate file exists
    if (Test-Path $certPath) {
        $result.CertificateValid = $true
        Write-LogInfo "Certificate file exists" -Context @{
            step = "Validate"
            agent_type = "est"
            cert_path = $certPath
            operation = "file_validation"
            status = "success"
        }
    } else {
        Write-LogWarn "Certificate file not found" -Context @{
            step = "Validate"
            agent_type = "est"
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
            agent_type = "est"
            key_path = $keyPath
            operation = "file_validation"
            status = "success"
        }
    } else {
        Write-LogWarn "Private key file not found" -Context @{
            step = "Validate"
            agent_type = "est"
            key_path = $keyPath
            operation = "file_validation"
            status = "failed"
        }
        $result.Message = "Private key file not found"
        return $result
    }

    # Validate certificate chain (if configured)
    # NOTE: certificate chain config not implemented yet
    # $chainPath = $config.certificate_chain.full_chain_path
    # if ($chainPath -and (Test-Path $chainPath)) {
    #     Write-Verbose "[EST:Validate] Certificate chain file exists"
    # }

    if ($result.CertificateValid -and $result.KeyValid) {
        $result.Message = "Deployment validated successfully"
    }

    return $result
}

# ==============================================================================
# Initialize-EstWorkflowSteps
# ==============================================================================
# Registers all EST workflow steps with the WorkflowOrchestrator
#
# Parameters: None
#
# Returns: None
# ==============================================================================
function Initialize-EstWorkflowSteps {
    [CmdletBinding()]
    param()

    Write-LogInfo "Initializing EST workflow steps" -Context @{
        agent_type = "est"
        operation = "workflow_init"
        status = "started"
    }

    # NOTE: WorkflowOrchestrator is already imported by est-agent.ps1 before this module loads

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
        -Description "Execute EST protocol operations" `
        -ContinueOnError $false `
        -ScriptBlock {
            param($Context)
            Step-ExecuteEstProtocol -Context $Context
        }

    # Register Validate step
    Register-WorkflowStep `
        -Name "Validate" `
        -Description "Validate deployment" `
        -ContinueOnError $true `
        -ScriptBlock {
            param($Context)
            Step-ValidateDeployment -Context $Context
        }

    Write-LogInfo "EST workflow steps registered" -Context @{
        agent_type = "est"
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
    'Step-ExecuteEstProtocol',
    'Step-ValidateDeployment',
    'Initialize-EstWorkflowSteps'
)
