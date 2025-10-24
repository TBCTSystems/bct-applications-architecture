#Requires -Version 5.1

<#
.SYNOPSIS
    Convenience launcher for PowerShell Certificate Renewal Service
.DESCRIPTION
    This script launches the PowerShell version of the certificate renewal service.
    It's a simple wrapper that forwards all parameters to the actual service script.
.PARAMETER ConfigPath
    Path to the configuration YAML file (relative to project root)
.PARAMETER Mode
    Operation mode: 'check' for single check, 'service' for continuous monitoring
.EXAMPLE
    .\Start-PowerShellService.ps1 -ConfigPath test\test-config\config.yaml -Mode check
.EXAMPLE
    .\Start-PowerShellService.ps1 -ConfigPath config\config.yaml -Mode service
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [string]$ConfigPath = "test\test-config\config.yaml",
    
    [Parameter(Mandatory=$false)]
    [ValidateSet('check', 'service')]
    [string]$Mode = 'check'
)

# Forward to the actual service script
& "$PSScriptRoot\ps-scripts\Start-CertRenewalService.ps1" -ConfigPath $ConfigPath -Mode $Mode
