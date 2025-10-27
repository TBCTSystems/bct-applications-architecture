<#
.SYNOPSIS
    PowerShell module for triggering NGINX configuration reload in Docker containers.

.DESCRIPTION
    ServiceReloadController.psm1 provides service reload functionality for the ECA-ACME agent.
    This module implements zero-downtime NGINX configuration reload by executing docker exec
    commands to send SIGHUP signals to NGINX master processes.

    The module is used after certificate installation to activate new server certificates
    without dropping active connections or causing service interruption.

    Key capabilities:
    - Execute `docker exec {container} nginx -s reload` with validation
    - Capture and parse stderr output for detailed error diagnostics
    - Enforce configurable timeout to prevent hanging on failed reloads
    - Distinguish between container errors, NGINX errors, and timeout conditions
    - Provide structured logging of all reload attempts and outcomes

.NOTES
    Module Name: ServiceReloadController
    Author: ECA Project
    Requires: PowerShell Core 7.0+
    Dependencies:
        - agents/common/Logger.psm1 (structured logging)
        - Docker CLI available in PATH
        - Docker socket access (/var/run/docker.sock mounted in container)

    Security Considerations:
    - Requires privileged Docker socket access for exec operations
    - Container name parameter validated to prevent command injection
    - Only executes predefined NGINX reload command (no arbitrary commands)

    Process Signaling Pattern:
    - NGINX reload uses SIGHUP signal for graceful reload
    - New worker processes spawn with updated configuration
    - Old worker processes drain connections before termination
    - Zero-downtime certificate rotation enabled by this pattern

.LINK
    Documentation: docs/ARCHITECTURE.md (Process Signaling Pattern)
    Sequence Diagram: docs/diagrams/acme_renewal_sequence.mmd
    Architecture: ECA-ACME Agent Responsibilities

.EXAMPLE
    Import-Module ./agents/acme/ServiceReloadController.psm1
    $success = Invoke-NginxReload
    if ($success) {
        Write-Host "NGINX reloaded successfully"
    }

.EXAMPLE
    # Custom container name and timeout
    $success = Invoke-NginxReload -ContainerName "custom-nginx" -TimeoutSeconds 30
    if (-not $success) {
        Write-Host "NGINX reload failed - check logs for details"
    }
#>

#Requires -Version 7.0

# NOTE: Dependencies (Logger) are imported by the calling script
# Removing these imports to avoid module scope isolation issues

# ============================================================================
# PUBLIC FUNCTIONS
# ============================================================================

function Invoke-NginxReload {
    <#
    .SYNOPSIS
        Triggers NGINX configuration reload in a Docker container.

    .DESCRIPTION
        Executes `docker exec {container} nginx -s reload` command to send SIGHUP
        signal to NGINX master process, triggering graceful configuration reload.

        The function validates the reload succeeded by checking exit code and
        parsing stderr output for error details. Supports configurable timeout
        to prevent hanging on failed reload operations.

        Return value indicates success (true) or failure (false). All outcomes
        are logged with structured context for operational monitoring.

    .PARAMETER ContainerName
        Name of the Docker container running NGINX. Defaults to "target-server".
        Must match the container name in docker-compose.yml configuration.

    .PARAMETER TimeoutSeconds
        Maximum time to wait for reload command completion, in seconds.
        Range: 1-300 seconds. Default: 10 seconds.

        If timeout is exceeded, the docker process is terminated and the
        function returns false with timeout error logged.

    .OUTPUTS
        System.Boolean - Returns $true if reload succeeded (exit code 0),
                        $false for any failure condition.

    .EXAMPLE
        $success = Invoke-NginxReload
        # Uses default container "target-server" and 10-second timeout

    .EXAMPLE
        $success = Invoke-NginxReload -ContainerName "web-server" -TimeoutSeconds 30
        # Custom container name with extended timeout

    .EXAMPLE
        if (Invoke-NginxReload) {
            Write-LogInfo "Certificate activated successfully"
        } else {
            Write-LogError "Certificate installed but not activated - manual intervention required"
        }

    .NOTES
        Error Conditions Detected:
        - Container not found: Docker returns "No such container" error
        - NGINX validation failed: Exit code 1 with configuration errors in stderr
        - Timeout exceeded: Process did not complete within TimeoutSeconds
        - Docker command failed: Docker CLI not available or socket inaccessible

        Logging Output:
        - Success: INFO level with container name
        - Failure: ERROR level with exit code, stderr message, and full context
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $false)]
        [ValidateNotNullOrEmpty()]
        [string]$ContainerName = "eca-target-server",

        [Parameter(Mandatory = $false)]
        [ValidateRange(1, 300)]
        [int]$TimeoutSeconds = 10
    )

    # Temporary file for stderr capture
    $stderrFile = $null

    try {
        # Create temporary file for stderr output
        $stderrFile = [System.IO.Path]::GetTempFileName()

        # Build docker exec command arguments
        $dockerArgs = @(
            "exec",
            $ContainerName,
            "nginx",
            "-s",
            "reload"
        )

        # Start docker process with output redirection
        Write-LogDebug -Message "Starting NGINX reload" -Context @{
            container = $ContainerName
            timeout_seconds = $TimeoutSeconds
        }

        $process = Start-Process `
            -FilePath "docker" `
            -ArgumentList $dockerArgs `
            -NoNewWindow `
            -PassThru `
            -RedirectStandardError $stderrFile `
            -ErrorAction Stop

        # Wait for process completion with timeout
        $completed = $process.WaitForExit($TimeoutSeconds * 1000)

        if (-not $completed) {
            # Timeout occurred - kill the process
            try {
                $process.Kill()
            }
            catch {
                # Process may have already exited - ignore kill errors
                Out-Null
            }

            Write-LogError -Message "NGINX reload timed out" -Context @{
                container = $ContainerName
                timeout_seconds = $TimeoutSeconds
            }

            return $false
        }

        # Get exit code
        $exitCode = $process.ExitCode

        # Read stderr output
        $stderrContent = ""
        if (Test-Path $stderrFile) {
            $stderrContent = Get-Content -Path $stderrFile -Raw -ErrorAction SilentlyContinue
            if ($null -eq $stderrContent) {
                $stderrContent = ""
            }
            $stderrContent = $stderrContent.Trim()
        }

        # Evaluate success
        if ($exitCode -eq 0) {
            # Reload successful
            Write-LogInfo -Message "NGINX reload successful" -Context @{
                container = $ContainerName
            }
            return $true
        }
        else {
            # Reload failed - categorize error type
            $errorType = "unknown"
            $errorMessage = $stderrContent

            if ($stderrContent -match "No such container") {
                $errorType = "container_not_found"
            }
            elseif ($stderrContent -match "nginx") {
                $errorType = "nginx_validation_failed"
            }
            elseif ($stderrContent -match "docker") {
                $errorType = "docker_exec_failed"
            }

            Write-LogError -Message "NGINX reload failed" -Context @{
                container = $ContainerName
                exit_code = $exitCode
                error_type = $errorType
                stderr = $errorMessage
            }

            return $false
        }
    }
    catch {
        # Unexpected error (e.g., docker command not found, permission denied)
        Write-LogError -Message "NGINX reload error" -Context @{
            container = $ContainerName
            error = $_.Exception.Message
            error_type = "exception"
        }

        return $false
    }
    finally {
        # Cleanup temporary file
        if ($null -ne $stderrFile -and (Test-Path $stderrFile)) {
            try {
                Remove-Item -Path $stderrFile -Force -ErrorAction SilentlyContinue
            }
            catch {
                # Ignore cleanup errors - file may already be deleted
                Out-Null
            }
        }
    }
}

# Export only the public function
Export-ModuleMember -Function Invoke-NginxReload
