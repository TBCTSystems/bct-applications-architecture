#Requires -Version 5.1

<#
.SYNOPSIS
    Logging functionality for Certificate Renewal Service
.DESCRIPTION
    Provides structured logging with file and console output
#>

class CertRenewalLogger {
    [string]$LogLevel
    [string]$LogFile
    [hashtable]$LogLevels = @{
        DEBUG = 10
        INFO = 20
        WARNING = 30
        ERROR = 40
        CRITICAL = 50
    }
    
    CertRenewalLogger([string]$Level, [string]$File) {
        $this.LogLevel = $Level.ToUpper()
        $this.LogFile = $File
        
        # Ensure log directory exists
        $logDir = Split-Path -Parent $File
        if ($logDir -and -not (Test-Path $logDir)) {
            $null = New-Item -Path $logDir -ItemType Directory -Force
        }
    }
    
    hidden [bool] ShouldLog([string]$Level) {
        $messageLevelValue = $this.LogLevels[$Level.ToUpper()]
        $configuredLevelValue = $this.LogLevels[$this.LogLevel]
        return $messageLevelValue -ge $configuredLevelValue
    }
    
    hidden [void] WriteLog([string]$Level, [string]$Message) {
        if (-not $this.ShouldLog($Level)) {
            return
        }
        
        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        $logMessage = "$timestamp - cert_renewal_service - $Level - $Message"
        
        # Write to console
        switch ($Level) {
            "DEBUG" { Write-Verbose $logMessage }
            "INFO" { Write-Host $logMessage -ForegroundColor Cyan }
            "WARNING" { Write-Warning $logMessage }
            "ERROR" { Write-Host $logMessage -ForegroundColor Red }
            "CRITICAL" { Write-Host $logMessage -ForegroundColor Magenta }
        }
        
        # Write to file
        if ($this.LogFile) {
            try {
                Add-Content -Path $this.LogFile -Value $logMessage -ErrorAction SilentlyContinue
            }
            catch {
                Write-Warning "Failed to write to log file: $_"
            }
        }
    }
    
    [void] Debug([string]$Message) {
        $this.WriteLog("DEBUG", $Message)
    }
    
    [void] Info([string]$Message) {
        $this.WriteLog("INFO", $Message)
    }
    
    [void] Warning([string]$Message) {
        $this.WriteLog("WARNING", $Message)
    }
    
    [void] Error([string]$Message) {
        $this.WriteLog("ERROR", $Message)
    }
    
    [void] Critical([string]$Message) {
        $this.WriteLog("CRITICAL", $Message)
    }
}

