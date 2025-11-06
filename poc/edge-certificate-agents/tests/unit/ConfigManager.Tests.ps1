<#
.SYNOPSIS
    Pester tests for ConfigManager environment variable overrides.
#>

#Requires -Version 7.0
#Requires -Modules Pester

BeforeAll {
    $modulePath = "$PSScriptRoot/../../agents/common/ConfigManager.psm1"
    Import-Module $modulePath -Force

    if (-not (Get-Command ConvertFrom-Yaml -ErrorAction SilentlyContinue)) {
        function global:ConvertFrom-Yaml {
            param(
                [Parameter(Mandatory = $true)]
                [string]$Yaml
            )

            $result = @{}
            foreach ($line in $Yaml -split "`n") {
                if ($line -match '^\s*([^:#]+):\s*(.+)$') {
                    $key = $matches[1].Trim()
                    $value = $matches[2].Trim().Trim('"')
                    $result[$key] = $value
                }
            }

            return [PSCustomObject]$result
        }
    }
}

AfterAll {
    Remove-Module ConfigManager -Force -ErrorAction SilentlyContinue
}

Describe "Read-AgentConfig Environment Overrides" {
    BeforeAll {
        Mock -ModuleName ConfigManager -CommandName Invoke-SchemaValidation -MockWith { param([hashtable]$Config, [string]$SchemaPath) }
    }

    AfterEach {
        Remove-Item Env:ACME_PKI_URL -ErrorAction SilentlyContinue
        Remove-Item Env:EST_DEVICE_NAME -ErrorAction SilentlyContinue
    }

    It "prefers prefixed environment variables when prefix is provided" {
        $configPath = Join-Path $TestDrive "config.yaml"
        @"
pki_url: https://default
cert_path: /certs/server/server.crt
key_path: /certs/server/server.key
domain_name: target-server
"@ | Set-Content -Path $configPath

        $env:ACME_PKI_URL = "https://override"

        $config = Read-AgentConfig -ConfigFilePath $configPath -EnvVarPrefixes @("ACME_")

        $config.pki_url | Should -Be "https://override"
    }

    It "maps device_name using prefixed environment variables" {
        $configPath = Join-Path $TestDrive "config-device.yaml"
        @"
pki_url: https://default
cert_path: /certs/client/client.crt
key_path: /certs/client/client.key
domain_name: client-default
device_name: client-device-001
"@ | Set-Content -Path $configPath

        $env:EST_DEVICE_NAME = "est-demo-device-42"

        $config = Read-AgentConfig -ConfigFilePath $configPath -EnvVarPrefixes @("EST_")

        $config.device_name | Should -Be "est-demo-device-42"
    }
}
