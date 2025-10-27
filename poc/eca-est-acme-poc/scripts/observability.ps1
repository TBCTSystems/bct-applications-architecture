#!/usr/bin/env pwsh
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [ValidateSet('up', 'down', 'status', 'logs', 'verify', 'demo')]
    [string]$Command,

    [switch]$WithAgents,

    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$VerifyArgs
)

$ErrorActionPreference = 'Stop'

$script:CoreServices = @('fluentd', 'loki', 'grafana')
$script:AgentServices = @('eca-acme-agent', 'eca-est-agent', 'target-server', 'target-client')
$ProjectRoot = Split-Path -Parent $PSScriptRoot
$VerifyArgs = $VerifyArgs ?? @()

function Invoke-DockerCompose {
    param(
        [string[]]$Arguments
    )

    Push-Location $ProjectRoot
    try {
        & docker compose @Arguments
    }
    finally {
        Pop-Location
    }
}

function Ensure-DockerAvailable {
    if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
        throw "Docker CLI is required. Install Docker Desktop/Engine before running this script."
    }

    try {
        docker compose version | Out-Null
    }
    catch {
        throw "Docker Compose v2 is required (bundled with recent Docker versions)."
    }
}

function Wait-ComposeServices {
    param(
        [string[]]$Services,
        [int]$TimeoutSeconds = 180
    )

    foreach ($svc in $Services) {
        Write-Host "Waiting for $svc to report running..."
        $elapsed = 0
        while ($elapsed -lt $TimeoutSeconds) {
            $containerId = Invoke-DockerCompose -Arguments @('ps', '-q', $svc) | Select-Object -First 1
            if (-not [string]::IsNullOrWhiteSpace($containerId)) {
                $status = docker inspect --format '{{.State.Status}} {{if .State.Health}}{{.State.Health.Status}}{{end}}' $containerId 2>$null
                if ($status -match 'healthy' -or $status -match 'running') {
                    Write-Host "  $svc ready ($status)"
                    break
                }
            }
            Start-Sleep -Seconds 5
            $elapsed += 5
        }
    }
}

function Get-ServiceList {
    $services = @($script:CoreServices)
    if ($WithAgents.IsPresent) {
        $services += $script:AgentServices
    }
    return $services
}

function Invoke-VerifyScript {
    $verifyScript = Join-Path $ProjectRoot 'scripts/verify-logging.ps1'
    if (-not (Test-Path $verifyScript)) {
        throw "verify-logging.ps1 not found at $verifyScript"
    }

    & $verifyScript @VerifyArgs
}

Ensure-DockerAvailable
$selectedServices = Get-ServiceList

if ($Command -eq 'demo') {
    $WithAgents = $true
}

switch ($Command) {
    'up' {
        Invoke-DockerCompose -Arguments (@('up', '-d') + $selectedServices) | Out-Null
        Wait-ComposeServices -Services $selectedServices
    }
    'down' {
        Invoke-DockerCompose -Arguments (@('rm', '-sf') + $selectedServices) | Out-Null
    }
    'status' {
        Invoke-DockerCompose -Arguments (@('ps') + $selectedServices)
    }
    'logs' {
        Invoke-DockerCompose -Arguments (@('logs', '-f') + $script:CoreServices)
    }
    'verify' {
        Invoke-VerifyScript
    }
    'demo' {
        Invoke-DockerCompose -Arguments (@('up', '-d') + $selectedServices) | Out-Null
        Wait-ComposeServices -Services $selectedServices
        Write-Host "Running log verification..."
        Invoke-VerifyScript
        Write-Host "Generating sample events..."
        Invoke-DockerCompose -Arguments @('restart', 'eca-acme-agent', 'eca-est-agent') | Out-Null
        Invoke-DockerCompose -Arguments @('exec', 'eca-acme-agent', 'touch', '/tmp/force-renew') | Out-Null
        Write-Host "Sample events generated. Force-renew triggered for ACME agent."
        Write-Host "Open Grafana at http://localhost:3000 (admin / eca-admin)"
    }
}
