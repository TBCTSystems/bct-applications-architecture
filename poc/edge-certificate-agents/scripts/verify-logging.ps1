<#
.SYNOPSIS
    ECA Logging Verification Script (PowerShell)

.DESCRIPTION
    Verifies that the observability stack is working correctly
    by testing each component of the logging pipeline.

    This is the PowerShell version for Windows developers.

.PARAMETER Verbose
    Show detailed output including API responses

.PARAMETER Quiet
    Suppress non-error output (only show results)

.PARAMETER Help
    Show help message

.EXAMPLE
    .\scripts\verify-logging.ps1
    Run all tests with normal output

.EXAMPLE
    .\scripts\verify-logging.ps1 -Verbose
    Run with detailed verbose output

.EXAMPLE
    .\scripts\verify-logging.ps1 -Quiet
    Run quietly, only show pass/fail

.NOTES
    Exit Codes:
      0 - All tests passed
      1 - One or more tests failed
      2 - Script error or missing dependencies
#>

[CmdletBinding()]
param(
    [switch]$Quiet,
    [switch]$Help
)

# ============================================
# Configuration
# ============================================

$ErrorActionPreference = "Stop"
$ScriptDir = $PSScriptRoot
$ProjectDir = Split-Path -Parent $ScriptDir

# Test counters
$script:FailedTests = 0
$script:PassedTests = 0

# ============================================
# Helper Functions
# ============================================

function Write-Header {
    param([string]$Message)

    if (-not $Quiet) {
        Write-Host ""
        Write-Host ("=" * 59) -ForegroundColor Blue
        Write-Host $Message -ForegroundColor Blue
        Write-Host ("=" * 59) -ForegroundColor Blue
    }
}

function Write-TestHeader {
    param([string]$Message)

    if (-not $Quiet) {
        Write-Host ""
        Write-Host "▶ $Message" -ForegroundColor Yellow
    }
}

function Write-Success {
    param([string]$Message)

    Write-Host "✓ $Message" -ForegroundColor Green
    $script:PassedTests++
}

function Write-Failure {
    param([string]$Message)

    Write-Host "✗ $Message" -ForegroundColor Red
    $script:FailedTests++
}

function Write-Details {
    param([string]$Message)

    if ($VerbosePreference -eq 'Continue') {
        Write-Host "  $Message"
    }
}

function Show-Usage {
    $usage = @"
ECA Logging Verification Script (PowerShell)

Usage: .\scripts\verify-logging.ps1 [OPTIONS]

Options:
  -Verbose    Show detailed output including API responses
  -Quiet      Suppress non-error output (only show results)
  -Help       Show this help message

Exit Codes:
  0 - All tests passed
  1 - One or more tests failed
  2 - Script error or missing dependencies

Examples:
  .\scripts\verify-logging.ps1             # Run all tests with normal output
  .\scripts\verify-logging.ps1 -Verbose    # Run with verbose output
  .\scripts\verify-logging.ps1 -Quiet      # Run quietly, only show pass/fail

"@
    Write-Host $usage
}

# ============================================
# Dependency Checks
# ============================================

function Test-Dependencies {
    Write-Header "Checking Dependencies"

    $requiredCommands = @("docker", "curl")
    $missing = @()

    foreach ($cmd in $requiredCommands) {
        $found = Get-Command $cmd -ErrorAction SilentlyContinue
        if (-not $found) {
            $missing += $cmd
            Write-Failure "Missing dependency: $cmd"
        } else {
            Write-Details "Found: $cmd ($($found.Source))"
        }
    }

    if ($missing.Count -gt 0) {
        Write-Host ""
        Write-Host "Error: Missing required dependencies: $($missing -join ', ')" -ForegroundColor Red
        Write-Host "Please install missing tools and try again."
        exit 2
    }

    Write-Success "All dependencies present"
}

# ============================================
# Container Health Checks
# ============================================

function Test-ContainerRunning {
    param([string]$ContainerName)

    try {
        $status = docker inspect -f '{{.State.Status}}' $ContainerName 2>$null
        return $status -eq "running"
    } catch {
        return $false
    }
}

function Test-ContainerHealth {
    param([string]$ContainerName)

    try {
        $health = docker inspect -f '{{.State.Health.Status}}' $ContainerName 2>$null
        return ($health -eq "healthy") -or ($health -eq "none")
    } catch {
        return $false
    }
}

function Test-FluentdContainer {
    Write-TestHeader "Test 1: FluentD Container Status"

    if (Test-ContainerRunning "eca-fluentd") {
        Write-Details "Container is running"

        # Check logs for worker started
        $logs = docker logs eca-fluentd 2>&1 | Out-String
        if ($logs -match "fluentd worker is now running") {
            Write-Success "FluentD container is running and worker started"
        } else {
            Write-Failure "FluentD container running but worker not started"
            if ($VerbosePreference -eq 'Continue') {
                Write-Host "Recent logs:"
                (docker logs --tail 20 eca-fluentd 2>&1) | ForEach-Object { Write-Host "  $_" }
            }
        }
    } else {
        Write-Failure "FluentD container is not running"
    }
}

function Test-LokiContainer {
    Write-TestHeader "Test 2: Loki Container Status"

    if (Test-ContainerRunning "eca-loki") {
        Write-Details "Container is running"

        if (Test-ContainerHealth "eca-loki") {
            Write-Success "Loki container is running and healthy"
        } else {
            Write-Failure "Loki container running but not healthy"
        }
    } else {
        Write-Failure "Loki container is not running"
    }
}

function Test-GrafanaContainer {
    Write-TestHeader "Test 3: Grafana Container Status"

    if (Test-ContainerRunning "eca-grafana") {
        Write-Details "Container is running"

        if (Test-ContainerHealth "eca-grafana") {
            Write-Success "Grafana container is running and healthy"
        } else {
            Write-Failure "Grafana container running but not healthy"
        }
    } else {
        Write-Failure "Grafana container is not running"
    }
}

# ============================================
# Service Health Checks
# ============================================

function Test-FluentdHealth {
    Write-TestHeader "Test 4: FluentD Health Endpoint"

    try {
        $response = Invoke-WebRequest -Uri "http://localhost:24220/api/plugins.json" -UseBasicParsing -ErrorAction Stop

        if ($response.StatusCode -eq 200) {
            $body = $response.Content | ConvertFrom-Json
            $pluginCount = $body.plugins.Count
            Write-Details "HTTP $($response.StatusCode) - Found $pluginCount plugins"
            Write-Success "FluentD monitoring endpoint is responding"

            if ($VerbosePreference -eq 'Continue') {
                Write-Host "  Plugins:"
                $body.plugins | ForEach-Object { Write-Host "    - $($_.type): $($_.plugin_id)" }
            }
        }
    } catch {
        Write-Failure "FluentD monitoring endpoint not responding ($($_.Exception.Message))"
    }
}

function Test-LokiHealth {
    Write-TestHeader "Test 5: Loki Health Endpoint"

    try {
        $response = Invoke-WebRequest -Uri "http://localhost:3100/ready" -UseBasicParsing -ErrorAction Stop

        if ($response.Content -eq "ready") {
            Write-Success "Loki is ready and accepting queries"
        } else {
            Write-Failure "Loki is not ready (response: '$($response.Content)')"
        }
    } catch {
        Write-Failure "Loki health endpoint not responding ($($_.Exception.Message))"
    }
}

function Test-GrafanaHealth {
    Write-TestHeader "Test 6: Grafana Health API"

    try {
        $response = Invoke-RestMethod -Uri "http://localhost:3000/api/health" -Method Get -ErrorAction Stop

        if ($response.database -eq "ok") {
            Write-Details "Version: $($response.version), Database: $($response.database)"
            Write-Success "Grafana is healthy and database is connected"
        } else {
            Write-Failure "Grafana health check failed"
            if ($VerbosePreference -eq 'Continue') {
                Write-Host "  Response: $($response | ConvertTo-Json)"
            }
        }
    } catch {
        Write-Failure "Grafana health endpoint not responding ($($_.Exception.Message))"
    }
}

# ============================================
# Log Flow Tests
# ============================================

function Test-AgentContainers {
    Write-TestHeader "Test 7: Agent Containers Running"

    $agents = @("eca-acme-agent", "eca-est-agent")
    $allRunning = $true

    foreach ($agent in $agents) {
        if (Test-ContainerRunning $agent) {
            Write-Details "$agent is running"
        } else {
            Write-Details "$agent is NOT running"
            $allRunning = $false
        }
    }

    if ($allRunning) {
        Write-Success "All agent containers are running"
    } else {
        Write-Failure "One or more agent containers are not running"
    }
}

function Test-LokiHasLogs {
    Write-TestHeader "Test 8: Loki Contains Logs"

    try {
        # Query for ACME logs
        $acmeUri = "http://localhost:3100/loki/api/v1/query?query={agent_type=`"acme`"}&limit=10"
        $acmeResponse = Invoke-RestMethod -Uri $acmeUri -Method Get -ErrorAction Stop
        $acmeCount = $acmeResponse.data.result.Count

        # Query for EST logs
        $estUri = "http://localhost:3100/loki/api/v1/query?query={agent_type=`"est`"}&limit=10"
        $estResponse = Invoke-RestMethod -Uri $estUri -Method Get -ErrorAction Stop
        $estCount = $estResponse.data.result.Count

        Write-Details "ACME logs found: $acmeCount stream(s)"
        Write-Details "EST logs found: $estCount stream(s)"

        if (($acmeCount -gt 0) -and ($estCount -gt 0)) {
            Write-Success "Loki contains logs from both agents"
        } elseif (($acmeCount -gt 0) -or ($estCount -gt 0)) {
            Write-Failure "Loki contains logs from only one agent (ACME: $acmeCount, EST: $estCount)"
        } else {
            Write-Failure "Loki contains no logs from agents"
        }
    } catch {
        Write-Failure "Failed to query Loki for logs ($($_.Exception.Message))"
    }
}

function Test-LogLabels {
    Write-TestHeader "Test 9: Log Labels and Structure"

    try {
        $uri = "http://localhost:3100/loki/api/v1/query?query={agent_type=~`"acme|est`"}&limit=1"
        $response = Invoke-RestMethod -Uri $uri -Method Get -ErrorAction Stop

        if ($response.data.result.Count -gt 0) {
            $labels = $response.data.result[0].stream

            Write-Details "Sample log labels found"
            if ($VerbosePreference -eq 'Continue') {
                $labels | ConvertTo-Json | ForEach-Object { Write-Host "    $_" }
            }

            if (($labels.agent_type) -and ($labels.container_name)) {
                Write-Success "Logs have proper labels (agent_type: $($labels.agent_type), container: $($labels.container_name))"
            } else {
                Write-Failure "Logs missing expected labels"
            }
        } else {
            Write-Failure "No logs found to verify labels"
        }
    } catch {
        Write-Failure "Failed to query log labels ($($_.Exception.Message))"
    }
}

# ============================================
# End-to-End Test
# ============================================

function Test-LogGeneration {
    Write-TestHeader "Test 10: End-to-End Log Flow (Generate & Verify)"

    try {
        Write-Details "Restarting ACME agent to generate logs..."
        docker restart eca-acme-agent | Out-Null

        Write-Details "Waiting 15 seconds for logs to propagate..."
        Start-Sleep -Seconds 15

        # Query for startup logs
        $uri = "http://localhost:3100/loki/api/v1/query?query={agent_type=`"acme`"}|=`"started`"&limit=5"
        $response = Invoke-RestMethod -Uri $uri -Method Get -ErrorAction Stop

        if ($response.data.result.Count -gt 0) {
            $latestLog = $response.data.result[0].values[-1][1]
            $truncated = if ($latestLog.Length -gt 100) { $latestLog.Substring(0, 100) + "..." } else { $latestLog }
            Write-Details "Latest log: $truncated"
            Write-Success "End-to-end log flow verified (logs generated and retrieved)"
        } else {
            Write-Failure "No startup logs found after agent restart"

            # Debugging info
            Write-Details "Checking if agent is logging at all..."
            $debugUri = "http://localhost:3100/loki/api/v1/query?query={agent_type=`"acme`"}&limit=1"
            $debugResponse = Invoke-RestMethod -Uri $debugUri -Method Get -ErrorAction SilentlyContinue

            if ($debugResponse.data.result.Count -gt 0) {
                Write-Details "Agent is logging, but no recent startup logs found"
            } else {
                Write-Details "No logs from ACME agent at all - check FluentD configuration"
            }
        }
    } catch {
        Write-Failure "Failed to test log generation ($($_.Exception.Message))"
    }
}

# ============================================
# Grafana Integration Tests
# ============================================

function Test-GrafanaDatasource {
    Write-TestHeader "Test 11: Grafana Loki Datasource"

    try {
        $cred = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("admin:eca-admin"))
        $headers = @{ Authorization = "Basic $cred" }

        $response = Invoke-RestMethod -Uri "http://localhost:3000/api/datasources/name/Loki" -Headers $headers -Method Get -ErrorAction Stop

        if ($response.type -eq "loki") {
            Write-Details "Datasource URL: $($response.url)"
            Write-Success "Grafana Loki datasource is configured"
        } else {
            Write-Failure "Grafana Loki datasource not found or misconfigured"
            if ($VerbosePreference -eq 'Continue') {
                Write-Host "  Response: $($response | ConvertTo-Json)"
            }
        }
    } catch {
        Write-Failure "Failed to query Grafana datasource ($($_.Exception.Message))"
    }
}

function Test-GrafanaDashboards {
    Write-TestHeader "Test 12: Grafana Dashboards Loaded"

    try {
        $cred = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("admin:eca-admin"))
        $headers = @{ Authorization = "Basic $cred" }

        $response = Invoke-RestMethod -Uri "http://localhost:3000/api/search?type=dash-db" -Headers $headers -Method Get -ErrorAction Stop

        $dashboardCount = $response.Count

        if ($dashboardCount -ge 3) {
            Write-Details "Found $dashboardCount dashboards"

            if ($VerbosePreference -eq 'Continue') {
                Write-Host "  Dashboards:"
                $response | ForEach-Object { Write-Host "    - $($_.title)" }
            }

            # Check for ECA-specific dashboards
            $ecaCount = ($response | Where-Object { $_.title -match "ECA" }).Count

            if ($ecaCount -ge 3) {
                Write-Success "All expected ECA dashboards are loaded"
            } else {
                Write-Failure "Expected at least 3 ECA dashboards, found $ecaCount"
            }
        } else {
            Write-Failure "Expected at least 3 dashboards, found $dashboardCount"
        }
    } catch {
        Write-Failure "Failed to query Grafana dashboards ($($_.Exception.Message))"
    }
}

# ============================================
# Performance Tests
# ============================================

function Test-ResourceUsage {
    Write-TestHeader "Test 13: Resource Usage Check"

    $containers = @("eca-fluentd", "eca-loki", "eca-grafana")
    $warning = $false

    foreach ($container in $containers) {
        if (Test-ContainerRunning $container) {
            try {
                $stats = docker stats --no-stream --format "{{.MemUsage}}" $container 2>$null
                $mem = ($stats -split '/')[0].Trim()

                Write-Details "$container : $mem"

                # Check if memory usage is concerning (>1GB)
                if ($mem -match '(\d+\.?\d*)([GMK]iB)') {
                    $value = [double]$matches[1]
                    $unit = $matches[2]

                    $memMB = switch ($unit) {
                        "GiB" { $value * 1024 }
                        "MiB" { $value }
                        "KiB" { $value / 1024 }
                    }

                    if ($memMB -gt 1000) {
                        $warning = $true
                    }
                }
            } catch {
                Write-Details "$container : Unable to get stats"
            }
        }
    }

    if ($warning) {
        Write-Failure "One or more services using >1GB memory (may be normal, check thresholds)"
    } else {
        Write-Success "All observability services within expected memory usage"
    }
}

# ============================================
# Buffer and Reliability Tests
# ============================================

function Test-FluentdBuffer {
    Write-TestHeader "Test 14: FluentD Buffer Configuration"

    try {
        $null = docker exec eca-fluentd ls /var/log/fluentd/buffer 2>$null

        if ($LASTEXITCODE -eq 0) {
            $bufferFiles = docker exec eca-fluentd find /var/log/fluentd/buffer -type f 2>$null
            $fileCount = if ($bufferFiles) { ($bufferFiles | Measure-Object -Line).Lines } else { 0 }

            Write-Details "Buffer directory exists, $fileCount file(s) currently buffered"
            Write-Success "FluentD buffer is configured and accessible"

            if ($fileCount -gt 100) {
                Write-Details "Warning: Large number of buffer files may indicate Loki connectivity issues"
            }
        } else {
            Write-Failure "FluentD buffer directory not accessible"
        }
    } catch {
        Write-Failure "Failed to check FluentD buffer ($($_.Exception.Message))"
    }
}

# ============================================
# Main Execution
# ============================================

function Main {
    if ($Help) {
        Show-Usage
        exit 0
    }

    # Start tests
    Write-Header "ECA Observability Stack Verification"
    if (-not $Quiet) {
        Write-Host "Testing logging infrastructure: FluentD → Loki → Grafana"
    }

    # Run all tests
    Test-Dependencies

    Write-Header "Container Health Checks"
    Test-FluentdContainer
    Test-LokiContainer
    Test-GrafanaContainer

    Write-Header "Service Health Endpoints"
    Test-FluentdHealth
    Test-LokiHealth
    Test-GrafanaHealth

    Write-Header "Log Flow Verification"
    Test-AgentContainers
    Test-LokiHasLogs
    Test-LogLabels
    Test-LogGeneration

    Write-Header "Grafana Integration"
    Test-GrafanaDatasource
    Test-GrafanaDashboards

    Write-Header "Performance & Reliability"
    Test-ResourceUsage
    Test-FluentdBuffer

    # Summary
    Write-Header "Test Summary"
    $totalTests = $script:PassedTests + $script:FailedTests

    Write-Host "Total Tests: $totalTests"
    Write-Host "Passed: $script:PassedTests" -ForegroundColor Green
    Write-Host "Failed: $script:FailedTests" -ForegroundColor Red

    if ($script:FailedTests -eq 0) {
        Write-Host ""
        Write-Host "✓ All tests passed! Logging system is fully operational." -ForegroundColor Green
        Write-Host "Access Grafana at: " -NoNewline
        Write-Host "http://localhost:3000" -ForegroundColor Blue -NoNewline
        Write-Host " (admin/eca-admin)"
        exit 0
    } else {
        Write-Host ""
        Write-Host "✗ Some tests failed. Please review the output above." -ForegroundColor Red
        Write-Host "For troubleshooting, see: " -NoNewline
        Write-Host "OBSERVABILITY_QUICKSTART.md" -ForegroundColor Blue
        exit 1
    }
}

# Run main function
Main
