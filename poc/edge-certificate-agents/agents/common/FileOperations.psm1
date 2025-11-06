<#
.SYNOPSIS
    PowerShell module providing secure atomic file operations and permission management.

.DESCRIPTION
    FileOperations.psm1 provides cross-platform file operations required for secure
    certificate and private key management. This module ensures data integrity through
    atomic file writes and enforces proper Unix file permissions to protect sensitive
    cryptographic material.

    Key capabilities:
    - Atomic file writes (temp file + atomic rename pattern)
    - Cross-platform permission management (Unix chmod, Windows icacls)
    - Permission validation for security compliance
    - Graceful error handling with automatic cleanup

    Atomic file writes prevent partial writes that could leave the system in an
    inconsistent state. The standard Unix pattern of write-to-temp-then-rename is
    used because filesystem rename operations are atomic at the kernel level.

    File permissions are security-critical for private keys, which must be readable
    only by the owner (mode 0600) to prevent unauthorized access. Certificate files
    use mode 0644 (owner read/write, others read-only) to allow target services to
    read them.

.NOTES
    Module Name: FileOperations
    Author: ECA Project
    Requires: PowerShell Core 7.0+
    Dependencies: None (uses built-in cmdlets and native OS commands)

    Security Considerations:
    - Private keys MUST be set to 0600 immediately after creation
    - Atomic writes prevent partial file corruption
    - Temp files inherit permissions from parent directory
    - All file operations include comprehensive error handling
    - Failed writes automatically clean up temporary files

    Cross-Platform Compatibility:
    - Tested on Linux (Alpine 3.19 in Docker)
    - Uses OS detection via $IsLinux, $IsWindows, $IsMacOS
    - Linux/macOS: Uses chmod for permission management
    - Windows: Uses icacls for ACL-based permission management
    - No platform-specific dependencies beyond native OS commands

.LINK
    Architecture: docs/02_Architecture_Overview.md
    Security: docs/05_Operational_Architecture.md (Section 3.8.3)

.EXAMPLE
    Import-Module ./agents/common/FileOperations.psm1
    Write-FileAtomic -Path "/certs/server/cert.pem" -Content $certificatePem

.EXAMPLE
    Set-FilePermissions -Path "/certs/server/key.pem" -Mode "0600"
    $valid = Test-FilePermissions -Path "/certs/server/key.pem" -ExpectedMode "0600"
#>

#Requires -Version 7.0

# ============================================================================
# PUBLIC FUNCTIONS
# ============================================================================

<#
.SYNOPSIS
    Writes content to a file atomically to prevent partial writes.

.DESCRIPTION
    Implements the atomic file write pattern using write-to-temp-then-rename strategy.
    This ensures that either the file write completes successfully or fails completely,
    with no possibility of partial writes that could corrupt data or leave the system
    in an inconsistent state.

    The atomic write pattern:
    1. Generate unique temporary filename (target.tmp.PID)
    2. Write full content to temporary file
    3. Verify temp file was created successfully
    4. Atomically rename temp file to target path (rename is atomic in Unix)
    5. On any error, delete temp file and propagate exception

    This pattern is essential for certificate management where partial writes could
    cause services to fail to start or create security vulnerabilities.

.PARAMETER Path
    Absolute or relative path to the target file. If the file exists, it will be
    atomically replaced. If it doesn't exist, it will be created.

.PARAMETER Content
    The content to write to the file. Can be string or byte array.

.EXAMPLE
    Write-FileAtomic -Path "/certs/server/cert.pem" -Content $certificatePem
    # Writes certificate atomically, preventing partial writes

.EXAMPLE
    $privateKeyPem = New-RSAKeyPair
    Write-FileAtomic -Path "/certs/server/key.pem" -Content $privateKeyPem
    Set-FilePermissions -Path "/certs/server/key.pem" -Mode "0600"
    # Write private key atomically, then set secure permissions

.NOTES
    - Rename operation is atomic at filesystem level (POSIX and Windows)
    - Temp file uses .tmp.PID suffix to avoid collisions
    - Parent directory must exist and be writable
    - On error, temp file is automatically deleted in finally block
    - Move-Item -Force used to ensure atomic rename even if target exists
#>
function Write-FileAtomic {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string]$Path,

        [Parameter(Mandatory = $true, Position = 1)]
        [ValidateNotNull()]
        [object]$Content
    )

    # Generate unique temp filename using process ID
    $tempPath = "$Path.tmp.$PID"

    try {
        # Write content to temporary file
        Set-Content -Path $tempPath -Value $Content -NoNewline -ErrorAction Stop

        # Verify temp file was created
        if (-not (Test-Path -Path $tempPath -PathType Leaf)) {
            throw "Temporary file was not created: $tempPath"
        }

        # Atomically rename temp file to target path
        # Move-Item with -Force replaces existing file atomically
        Move-Item -Path $tempPath -Destination $Path -Force -ErrorAction Stop
    }
    catch {
        throw "Failed to write file atomically to '$Path': $($_.Exception.Message)"
    }
    finally {
        # Clean up temp file if it still exists (error occurred before rename)
        if (Test-Path -Path $tempPath -PathType Leaf) {
            try {
                Remove-Item -Path $tempPath -Force -ErrorAction Stop
            }
            catch {
                # Log cleanup failure but don't throw (original error is more important)
                Write-Warning "Failed to clean up temporary file '$tempPath': $($_.Exception.Message)"
            }
        }
    }
}

<#
.SYNOPSIS
    Sets file permissions using platform-appropriate commands.

.DESCRIPTION
    Sets file permissions in a cross-platform manner using native OS commands:
    - Linux/macOS: Uses chmod with Unix octal permission modes
    - Windows: Uses icacls with Windows ACL syntax

    Common permission modes:
    - 0600: Owner read/write only (private keys)
    - 0644: Owner read/write, group/others read (certificates)
    - 0400: Owner read-only (read-only secrets)
    - 0700: Owner read/write/execute (directories)

    Security Note: Private keys MUST be set to 0600 to prevent unauthorized access.
    This is a critical security requirement for PKI operations.

.PARAMETER Path
    Absolute or relative path to the file. File must exist.

.PARAMETER Mode
    Permission mode as a string in Unix octal format (e.g., "0600", "0644").
    On Windows, the mode is interpreted and mapped to equivalent ACL permissions.

.EXAMPLE
    Set-FilePermissions -Path "/certs/server/key.pem" -Mode "0600"
    # Set private key to owner-only read/write (security critical)

.EXAMPLE
    Set-FilePermissions -Path "/certs/server/cert.pem" -Mode "0644"
    # Set certificate to owner read/write, others read-only

.NOTES
    - File must exist before calling this function
    - On Linux/macOS: Uses chmod command
    - On Windows: Uses icacls command with ACL syntax
    - Windows ACLs don't map 1:1 to Unix modes (best effort approximation)
    - 0600 on Windows: Remove inheritance, grant owner read/write only
    - 0644 on Windows: Remove inheritance, grant owner read/write, users read
#>
function Set-FilePermissions {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string]$Path,

        [Parameter(Mandatory = $true, Position = 1)]
        [ValidateNotNullOrEmpty()]
        [ValidatePattern('^0?[0-7]{3}$')]
        [string]$Mode
    )

    try {
        # Verify file exists
        if (-not (Test-Path -Path $Path -PathType Leaf)) {
            throw "File not found: $Path"
        }

        # Detect operating system and use appropriate command
        if ($IsLinux -or $IsMacOS) {
            # Unix-like: Use chmod with octal mode
            $chmodResult = & chmod $Mode $Path 2>&1

            if ($LASTEXITCODE -ne 0) {
                throw "chmod failed with exit code $LASTEXITCODE`: $chmodResult"
            }
        }
        elseif ($IsWindows) {
            # Windows: Map Unix mode to icacls ACL syntax
            # This is a simplified mapping for common modes

            # Get current user for ACL grants
            $currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name

            # Remove inheritance first (equivalent to starting fresh)
            $icaclsRemoveInheritance = & icacls $Path /inheritance:r 2>&1
            if ($LASTEXITCODE -ne 0) {
                throw "icacls inheritance removal failed: $icaclsRemoveInheritance"
            }

            # Map mode to Windows permissions
            switch -Regex ($Mode) {
                '^0?600$' {
                    # Owner read/write only (private key mode)
                    $icaclsResult = & icacls $Path /grant:r "${currentUser}:(R,W)" 2>&1
                }
                '^0?644$' {
                    # Owner read/write, others read
                    $icaclsResult = & icacls $Path /grant:r "${currentUser}:(R,W)" /grant "Users:(R)" 2>&1
                }
                '^0?400$' {
                    # Owner read-only
                    $icaclsResult = & icacls $Path /grant:r "${currentUser}:(R)" 2>&1
                }
                default {
                    # Generic fallback: owner full control
                    $icaclsResult = & icacls $Path /grant:r "${currentUser}:(F)" 2>&1
                }
            }

            if ($LASTEXITCODE -ne 0) {
                throw "icacls permission grant failed: $icaclsResult"
            }
        }
        else {
            throw "Unsupported operating system (not Linux, macOS, or Windows)"
        }
    }
    catch {
        throw "Failed to set permissions on '$Path' to mode '$Mode': $($_.Exception.Message)"
    }
}

<#
.SYNOPSIS
    Validates that a file has the expected permissions.

.DESCRIPTION
    Checks whether a file's current permissions match the expected permission mode.
    Returns a boolean result for easy integration into validation workflows.

    On Unix-like systems, reads permissions using stat command and compares octal mode.
    On Windows, validates ACL permissions using icacls output or Get-Acl cmdlet.

    This function is used to verify that security-critical files (private keys) have
    been configured with proper permissions before proceeding with operations.

.PARAMETER Path
    Absolute or relative path to the file to validate. File must exist.

.PARAMETER ExpectedMode
    Expected permission mode as a string in Unix octal format (e.g., "0600", "0644").

.OUTPUTS
    System.Boolean
    - $true: File permissions match expected mode
    - $false: File permissions do not match expected mode

.EXAMPLE
    $valid = Test-FilePermissions -Path "/certs/server/key.pem" -ExpectedMode "0600"
    if (-not $valid) {
        throw "Private key permissions validation failed"
    }

.EXAMPLE
    if (Test-FilePermissions -Path "/certs/server/cert.pem" -ExpectedMode "0644") {
        Write-Host "Certificate permissions are correct"
    }

.NOTES
    - File must exist before calling this function
    - Linux/macOS: Uses stat -c %a to get octal permissions
    - Windows: Uses Get-Acl to compare ACL entries (approximate match)
    - Returns boolean for simple pass/fail validation
    - Does not throw exceptions (returns false on error for safety)
#>
function Test-FilePermissions {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string]$Path,

        [Parameter(Mandatory = $true, Position = 1)]
        [ValidateNotNullOrEmpty()]
        [ValidatePattern('^0?[0-7]{3}$')]
        [string]$ExpectedMode
    )

    try {
        # Verify file exists
        if (-not (Test-Path -Path $Path -PathType Leaf)) {
            Write-Warning "File not found: $Path"
            return $false
        }

        # Normalize expected mode (remove leading zero if present)
        $normalizedExpected = $ExpectedMode -replace '^0', ''

        # Detect operating system and use appropriate validation
        if ($IsLinux -or $IsMacOS) {
            # Unix-like: Use stat to get octal permissions
            $statResult = & stat -c '%a' $Path 2>&1

            if ($LASTEXITCODE -ne 0) {
                Write-Warning "stat command failed on '$Path': $statResult"
                return $false
            }

            # Compare actual vs expected (both normalized without leading zero)
            $actualMode = $statResult.Trim()
            return $actualMode -eq $normalizedExpected
        }
        elseif ($IsWindows) {
            # Windows: Use Get-Acl to validate permissions (approximate match)
            # This is a simplified check since Windows ACLs are more complex than Unix modes

            $acl = Get-Acl -Path $Path -ErrorAction Stop
            $currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name

            # Check based on expected mode
            switch -Regex ($ExpectedMode) {
                '^0?600$' {
                    # Owner read/write only - verify only owner has access
                    $ownerAccess = $acl.Access | Where-Object {
                        $_.IdentityReference.Value -eq $currentUser -and
                        $_.FileSystemRights -match 'Read.*Write' -and
                        $_.AccessControlType -eq 'Allow'
                    }

                    # Ensure no other users have access (simplified check)
                    $otherAccess = $acl.Access | Where-Object {
                        $_.IdentityReference.Value -ne $currentUser -and
                        $_.AccessControlType -eq 'Allow'
                    }

                    return ($null -ne $ownerAccess -and $null -eq $otherAccess)
                }
                '^0?644$' {
                    # Owner read/write, others read - verify owner has read/write
                    $ownerAccess = $acl.Access | Where-Object {
                        $_.IdentityReference.Value -eq $currentUser -and
                        $_.FileSystemRights -match 'Read.*Write' -and
                        $_.AccessControlType -eq 'Allow'
                    }

                    return ($null -ne $ownerAccess)
                }
                '^0?400$' {
                    # Owner read-only
                    $ownerAccess = $acl.Access | Where-Object {
                        $_.IdentityReference.Value -eq $currentUser -and
                        $_.FileSystemRights -match 'Read' -and
                        -not ($_.FileSystemRights -match 'Write') -and
                        $_.AccessControlType -eq 'Allow'
                    }

                    return ($null -ne $ownerAccess)
                }
                default {
                    # Unknown mode - cannot validate on Windows
                    Write-Warning "Cannot validate mode '$ExpectedMode' on Windows (unsupported mode)"
                    return $false
                }
            }
        }
        else {
            Write-Warning "Unsupported operating system (not Linux, macOS, or Windows)"
            return $false
        }
    }
    catch {
        Write-Warning "Failed to validate permissions on '$Path': $($_.Exception.Message)"
        return $false
    }
}

# ============================================================================
# MODULE EXPORTS
# ============================================================================

# Export only public functions
Export-ModuleMember -Function @(
    'Write-FileAtomic',
    'Set-FilePermissions',
    'Test-FilePermissions'
)
