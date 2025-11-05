#Requires -Version 7.0

function Resolve-CommonModuleDirectory {
    $candidates = @()

    $localCommon = Join-Path $PSScriptRoot 'common'
    if (Test-Path (Join-Path $localCommon 'Logger.psm1')) {
        $candidates += $localCommon
    }

    $parentDir = Split-Path -Path $PSScriptRoot -Parent
    if (-not [string]::IsNullOrWhiteSpace($parentDir)) {
        $siblingCommon = Join-Path $parentDir 'common'
        if (Test-Path (Join-Path $siblingCommon 'Logger.psm1')) {
            $candidates += $siblingCommon
        }
    }

    $resolved = $candidates | Select-Object -First 1
    if (-not $resolved) {
        throw "JWK agent: unable to locate common module directory."
    }

    return $resolved
}

function Import-ServiceReloadModule {
    $candidatePaths = @()

    $candidatePaths += Join-Path $PSScriptRoot 'ServiceReloadController.psm1'

    $parentDir = Split-Path -Path $PSScriptRoot -Parent
    if (-not [string]::IsNullOrWhiteSpace($parentDir)) {
        $acmeDir = Join-Path $parentDir 'acme'
        $candidatePaths += Join-Path $acmeDir 'ServiceReloadController.psm1'
    }

    foreach ($path in $candidatePaths) {
        if (Test-Path $path) {
            Import-Module $path -Force -Global
            return
        }
    }

    throw "JWK agent: unable to locate ServiceReloadController.psm1."
}

$script:CommonModuleDirectory = Resolve-CommonModuleDirectory

Import-Module (Join-Path $script:CommonModuleDirectory 'Logger.psm1') -Force -Global
Import-Module (Join-Path $script:CommonModuleDirectory 'ConfigManager.psm1') -Force -Global
Import-Module (Join-Path $script:CommonModuleDirectory 'CertificateMonitor.psm1') -Force -Global
Import-Module (Join-Path $script:CommonModuleDirectory 'FileOperations.psm1') -Force -Global
Import-Module (Join-Path $script:CommonModuleDirectory 'CrlValidator.psm1') -Force -Global
Import-ServiceReloadModule

try {
    Import-Module Posh-ACME -Force -Global
} catch {
    Write-Host "[ERROR] Failed to import Posh-ACME: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

function Convert-Base64UrlToBytes {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Value
    )

    $padded = $Value.Replace('-', '+').Replace('_', '/')
    switch ($Value.Length % 4) {
        2 { $padded += '==' }
        3 { $padded += '=' }
        0 { }
        default { $padded += '===' }
    }

    return [Convert]::FromBase64String($padded)
}

function Convert-JwkToPem {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$JwkPath
    )

    if (-not (Test-Path -Path $JwkPath -PathType Leaf)) {
        throw "JWK private key not found at '$JwkPath'."
    }

    $jwkJson = Get-Content -Path $JwkPath -Raw
    if ([string]::IsNullOrWhiteSpace($jwkJson)) {
        throw "JWK file '$JwkPath' is empty."
    }

    $jwk = $jwkJson | ConvertFrom-Json
    if (-not $jwk) {
        throw "Failed to parse JWK file '$JwkPath'."
    }

    $kty = ([string]$jwk.kty).ToUpperInvariant()
    $curveName = if ($jwk.PSObject.Properties.Name -contains 'crv') { [string]$jwk.crv } else { $null }
    $derBytes = $null
    $label = $null

    if ($kty -eq 'EC') {
        if (-not ($jwk.crv -and $jwk.x -and $jwk.y -and $jwk.d)) {
            throw "EC JWK must include crv, x, y, and d fields."
        }

        $normalizedCurve = ([string]$curveName).ToUpperInvariant()
        $curve = switch ($normalizedCurve) {
            'P-256' { [System.Security.Cryptography.ECCurve]::CreateFromFriendlyName('nistP256') }
            'P-384' { [System.Security.Cryptography.ECCurve]::CreateFromFriendlyName('nistP384') }
            'P-521' { [System.Security.Cryptography.ECCurve]::CreateFromFriendlyName('nistP521') }
            default { throw "Unsupported EC curve '$($jwk.crv)' in JWK." }
        }

        $parameters = [System.Security.Cryptography.ECParameters]::new()
        $parameters.Curve = $curve
        $parameters.D = Convert-Base64UrlToBytes -Value $jwk.d
        $parameters.Q = [System.Security.Cryptography.ECPoint]::new()
        $parameters.Q.X = Convert-Base64UrlToBytes -Value $jwk.x
        $parameters.Q.Y = Convert-Base64UrlToBytes -Value $jwk.y

        $ecdsa = [System.Security.Cryptography.ECDsa]::Create()
        try {
            $ecdsa.ImportParameters($parameters)
            $derBytes = $ecdsa.ExportECPrivateKey()
        } finally {
            $ecdsa.Dispose()
        }

        $label = 'EC PRIVATE KEY'
    }
    elseif ($kty -eq 'RSA') {
        $required = 'n','e','d','p','q','dp','dq','qi'
        foreach ($field in $required) {
            if (-not $jwk.PSObject.Properties.Name.Contains($field)) {
                throw "RSA JWK missing required field '$field'."
            }
        }

        $parameters = [System.Security.Cryptography.RSAParameters]::new()
        $parameters.Modulus  = Convert-Base64UrlToBytes -Value $jwk.n
        $parameters.Exponent = Convert-Base64UrlToBytes -Value $jwk.e
        $parameters.D        = Convert-Base64UrlToBytes -Value $jwk.d
        $parameters.P        = Convert-Base64UrlToBytes -Value $jwk.p
        $parameters.Q        = Convert-Base64UrlToBytes -Value $jwk.q
        $parameters.DP       = Convert-Base64UrlToBytes -Value $jwk.dp
        $parameters.DQ       = Convert-Base64UrlToBytes -Value $jwk.dq
        $parameters.InverseQ = Convert-Base64UrlToBytes -Value $jwk.qi

        $rsa = [System.Security.Cryptography.RSA]::Create()
        try {
            $rsa.ImportParameters($parameters)
            $derBytes = $rsa.ExportRSAPrivateKey()
        } finally {
            $rsa.Dispose()
        }

        $label = 'RSA PRIVATE KEY'
    }
    else {
        throw "Unsupported JWK key type '$kty'."
    }

    $base64 = [Convert]::ToBase64String($derBytes)
    $builder = New-Object System.Text.StringBuilder
    [void]$builder.AppendLine("-----BEGIN $label-----")
    for ($offset = 0; $offset -lt $base64.Length; $offset += 64) {
        $length = [Math]::Min(64, $base64.Length - $offset)
        [void]$builder.AppendLine($base64.Substring($offset, $length))
    }
    [void]$builder.AppendLine("-----END $label-----")

    return $builder.ToString()
}

function New-JwkPemFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$JwkPath
    )

    $pem = Convert-JwkToPem -JwkPath $JwkPath
    $tempPath = Join-Path ([System.IO.Path]::GetTempPath()) (([System.IO.Path]::GetRandomFileName()) + '.pem')
    Set-Content -Path $tempPath -Value $pem -NoNewline
    try {
        Set-FilePermissions -Path $tempPath -Mode '0600'
    } catch {
        Write-LogWarn -Message "Unable to set permissions on temporary PEM file" -Context @{ path = $tempPath; error = $_.Exception.Message }
    }

    return $tempPath
}

function Get-EffectivePkiSettings {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][hashtable]$Config
    )

    $settings = [ordered]@{
        url = $Config.pki_url
        skip_certificate_check = $false
        timeout_seconds = 30
    }

    if ($Config.ContainsKey('pki_environments')) {
        $envName = if ($Config.ContainsKey('environment') -and -not [string]::IsNullOrWhiteSpace($Config.environment)) { $Config.environment } else { 'development' }
        $envMap = $Config.pki_environments

        if ($envMap -isnot [System.Collections.IDictionary]) {
            $converted = @{}
            $envMap.PSObject.Properties | ForEach-Object { $converted[$_.Name] = $_.Value }
            $envMap = $converted
        }

        if ($envMap.ContainsKey($envName)) {
            $envSettings = $envMap[$envName]
            if ($envSettings -is [System.Collections.IDictionary]) {
                foreach ($key in $envSettings.Keys) {
                    $settings[$key] = $envSettings[$key]
                }
            } else {
                foreach ($prop in $envSettings.PSObject.Properties) {
                    $settings[$prop.Name] = $prop.Value
                }
            }
        }
    }

    return $settings
}

function Initialize-PoshAcmeEnvironment {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][hashtable]$Config,
        [Parameter(Mandatory = $true)][hashtable]$PkiSettings
    )

    $stateDir = $env:POSHACME_HOME
    if ([string]::IsNullOrWhiteSpace($stateDir)) {
        $stateDir = '/posh-acme-state'
        $env:POSHACME_HOME = $stateDir
    }

    if (-not (Test-Path -Path $stateDir -PathType Container)) {
        New-Item -ItemType Directory -Path $stateDir -Force | Out-Null
        try {
            Set-FilePermissions -Path $stateDir -Mode '0700'
        } catch {
            Write-LogWarn -Message "Failed to set permissions on Posh-ACME state directory" -Context @{ path = $stateDir; error = $_.Exception.Message }
        }
    }

    $directoryUrl = ($PkiSettings.url.TrimEnd('/')) + '/' + ($Config.acme_directory_path.TrimStart('/'))
    $params = @{ DirectoryUrl = $directoryUrl }
    if ($PkiSettings.ContainsKey('skip_certificate_check') -and $PkiSettings.skip_certificate_check) {
        $params['SkipCertificateCheck'] = $true
    }

    Write-LogInfo -Message "Configuring Posh-ACME server" -Context @{ directory_url = $directoryUrl }
    Set-PAServer @params | Out-Null
}

function Save-CertificateFiles {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$PACertificate,
        [Parameter(Mandatory = $true)][hashtable]$Config
    )

    try {
        Write-LogInfo -Message "Saving certificate and key files" -Context @{ cert_path = $Config.cert_path; key_path = $Config.key_path }

        $certContent = Get-Content -LiteralPath $PACertificate.CertFile -Raw
        $keyContent = Get-Content -LiteralPath $PACertificate.KeyFile -Raw

        $mainCertContent = $certContent
        $chainConfig = $null
        if ($Config.ContainsKey('certificate_chain')) {
            $chainConfig = $Config.certificate_chain
        }

        if ($chainConfig -and $chainConfig.enabled) {
            $installationConfig = $chainConfig.installation
            if ($installationConfig -and $installationConfig.install_full_chain_to_cert_path) {
                $mainCertContent = Get-Content -LiteralPath $PACertificate.FullChainFile -Raw
                Write-LogDebug -Message "Using full chain for main certificate file"
            }
        }

        Write-FileAtomic -Path $Config.key_path -Content $keyContent
        Set-FilePermissions -Path $Config.key_path -Mode '0600'

        Write-FileAtomic -Path $Config.cert_path -Content $mainCertContent
        Set-FilePermissions -Path $Config.cert_path -Mode '0644'

        if ($chainConfig -and $chainConfig.enabled -and $chainConfig.installation -and $chainConfig.installation.create_separate_chain_files) {
            if ($chainConfig.full_chain_path) {
                $fullChainContent = Get-Content -LiteralPath $PACertificate.FullChainFile -Raw
                Write-FileAtomic -Path $chainConfig.full_chain_path -Content $fullChainContent
                Set-FilePermissions -Path $chainConfig.full_chain_path -Mode '0644'
                Write-LogDebug -Message "Saved full chain file" -Context @{ path = $chainConfig.full_chain_path }
            }

            if ($chainConfig.intermediates_path -and (Test-Path $PACertificate.ChainFile)) {
                $chainContent = Get-Content -LiteralPath $PACertificate.ChainFile -Raw
                Write-FileAtomic -Path $chainConfig.intermediates_path -Content $chainContent
                Set-FilePermissions -Path $chainConfig.intermediates_path -Mode '0644'
                Write-LogDebug -Message "Saved intermediates file" -Context @{ path = $chainConfig.intermediates_path }
            }
        }

        Write-LogInfo -Message "Certificate and key files saved" -Context @{ cert_path = $Config.cert_path; key_path = $Config.key_path }
        return $true
    }
    catch {
        Write-LogError -Message "Failed to save certificate files" -Context @{ error = $_.Exception.Message; cert_path = $Config.cert_path; key_path = $Config.key_path }
        return $false
    }
}

function Test-CertificateAgainstCrl {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][hashtable]$Config,
        [Parameter(Mandatory = $true)][string]$CertPath
    )

    $result = @{
        CrlEnabled   = $false
        CrlChecked   = $false
        Revoked      = $false
        CrlAge       = -1.0
        RevokedCount = 0
        Error        = $null
    }

    try {
        if (-not $Config.ContainsKey('crl') -or -not $Config.crl.enabled) {
            Write-LogDebug -Message "CRL validation disabled in configuration"
            return $result
        }

        $result.CrlEnabled = $true

        if (-not $Config.crl.url -or -not $Config.crl.cache_path) {
            Write-LogWarn -Message "CRL enabled but url/cache_path not configured"
            return $result
        }

        $maxAge = if ($Config.crl.max_age_hours) { [double]$Config.crl.max_age_hours } else { 24.0 }
        $updateResult = Update-CrlCache -Url $Config.crl.url -CachePath $Config.crl.cache_path -MaxAgeHours $maxAge

        $result.CrlAge = $updateResult.CrlAge
        $result.RevokedCount = $updateResult.RevokedCount

        if ($null -ne $updateResult.Error) {
            Write-LogWarn -Message "CRL cache update returned error" -Context @{ error = $updateResult.Error; cache_path = $Config.crl.cache_path }
            $result.Error = $updateResult.Error
            return $result
        }

        Write-LogInfo -Message "CRL cache refreshed" -Context @{ crl_age_hours = [math]::Round($updateResult.CrlAge, 2); revoked_entries = $updateResult.RevokedCount; downloaded = $updateResult.Downloaded }

        if (-not (Test-Path -Path $CertPath -PathType Leaf)) {
            Write-LogDebug -Message "Certificate path missing, skipping CRL validation" -Context @{ cert_path = $CertPath }
            return $result
        }

        $revoked = Test-CertificateRevoked -CertificatePath $CertPath -CrlPath $Config.crl.cache_path
        $result.CrlChecked = $true

        if ($null -eq $revoked) {
            Write-LogWarn -Message "CRL validation inconclusive" -Context @{ cert_path = $CertPath }
            $result.Error = "CRL validation inconclusive"
            return $result
        }

        $result.Revoked = [bool]$revoked

        if ($result.Revoked) {
            Write-LogWarn -Message "Certificate is revoked according to CRL" -Context @{ cert_path = $CertPath }
        } else {
            Write-LogInfo -Message "Certificate is valid according to CRL" -Context @{ cert_path = $CertPath }
        }

        return $result
    }
    catch {
        Write-LogError -Message "CRL validation threw exception" -Context @{ error = $_.Exception.Message; cert_path = $CertPath }
        $result.Error = $_.Exception.Message
        return $result
    }
}

function Get-CertificateKeyLengthOption {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][hashtable]$Config
    )

    $type = 'rsa'
    if ($Config.ContainsKey('acme_certificate_key_type') -and -not [string]::IsNullOrWhiteSpace($Config.acme_certificate_key_type)) {
        $type = ([string]$Config.acme_certificate_key_type).ToLowerInvariant()
    }

    $size = $null
    if ($Config.ContainsKey('acme_certificate_key_size') -and $Config.acme_certificate_key_size) {
        try {
            $size = [int]$Config.acme_certificate_key_size
        } catch {
            $size = $null
        }
    }

    switch ($type) {
        'ec' {
            switch ($size) {
                384 { return 'ec-384' }
                default { return 'ec-256' }
            }
        }
        default {
            switch ($size) {
                4096 { return '4096' }
                3072 { return '3072' }
                2048 { return '2048' }
                default { return '2048' }
            }
        }
    }
}

function Ensure-ChallengeDirectory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Path
    )

    if ([string]::IsNullOrWhiteSpace($Path)) {
        throw "Challenge directory path is not configured."
    }

    if (-not (Test-Path -Path $Path -PathType Container)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
        try { Set-FilePermissions -Path $Path -Mode '0755' } catch { }
    }

    $acmeRoot = Join-Path $Path '.well-known'
    $challengePath = Join-Path $acmeRoot 'acme-challenge'

    if (-not (Test-Path -Path $acmeRoot -PathType Container)) {
        New-Item -ItemType Directory -Path $acmeRoot -Force | Out-Null
        try { Set-FilePermissions -Path $acmeRoot -Mode '0755' } catch { }
    }

    if (-not (Test-Path -Path $challengePath -PathType Container)) {
        New-Item -ItemType Directory -Path $challengePath -Force | Out-Null
        try { Set-FilePermissions -Path $challengePath -Mode '0755' } catch { }
    }

    return $Path
}

function Ensure-JwkAccount {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][hashtable]$Config
    )

    $existing = $null
    try {
        $existing = Get-PAAccount
    } catch {
        $existing = $null
    }

    if ($existing -and $existing.status -eq 'valid') {
        try { Set-PAAccount -ID $existing.id | Out-Null } catch { }
        Write-LogInfo -Message "Using existing ACME account" -Context @{ account_id = $existing.id }
        return $existing
    }

    if (-not $Config.ContainsKey('jwk_private_key_path') -or [string]::IsNullOrWhiteSpace($Config.jwk_private_key_path)) {
        throw "Configuration 'jwk_private_key_path' is required for the JWK agent."
    }

    $pemPath = $null
    try {
        $pemPath = New-JwkPemFile -JwkPath $Config.jwk_private_key_path

        try {
            $existing = New-PAAccount -KeyFile $pemPath -OnlyReturnExisting -ErrorAction Stop
            if ($existing) {
                Set-PAAccount -ID $existing.id | Out-Null
                Write-LogInfo -Message "Recovered existing JWK ACME account" -Context @{ account_id = $existing.id }
                return $existing
            }
        } catch {
            Write-LogDebug -Message "No existing JWK account found" -Context @{ error = $_.Exception.Message }
        }

        $accountParams = @{ KeyFile = $pemPath; AcceptTOS = $true }
        if ($Config.ContainsKey('acme_account_contact_email') -and -not [string]::IsNullOrWhiteSpace($Config.acme_account_contact_email)) {
            $accountParams['Contact'] = $Config.acme_account_contact_email
        }
        if ($Config.ContainsKey('jwk_key_id') -and -not [string]::IsNullOrWhiteSpace($Config.jwk_key_id)) {
            $accountParams['ID'] = $Config.jwk_key_id
        }

        $account = New-PAAccount @accountParams
        Set-PAAccount -ID $account.id | Out-Null

        Write-LogInfo -Message "Created new JWK-backed ACME account" -Context @{ account_id = $account.id }
        return $account
    }
    finally {
        if ($pemPath -and (Test-Path $pemPath)) {
            Remove-Item -Path $pemPath -Force -ErrorAction SilentlyContinue
        }
    }
}

function Invoke-CertificateRenewal {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][hashtable]$Config
    )

    try {
        Write-LogInfo -Message "Certificate renewal started" -Context @{ domain = $Config.domain_name }

        $challengeDir = if ($Config.ContainsKey('challenge_directory') -and -not [string]::IsNullOrWhiteSpace($Config.challenge_directory)) {
            [string]$Config.challenge_directory
        } else {
            '/challenge'
        }

        $effectiveChallengeDir = Ensure-ChallengeDirectory -Path $challengeDir
        $keyLength = Get-CertificateKeyLengthOption -Config $Config

        $certificateParams = @{
            Domain        = $Config.domain_name
            Force         = $true
            Plugin        = 'WebRoot'
            PluginArgs    = @{ WRPath = @($effectiveChallengeDir) }
            CertKeyLength = $keyLength
        }

        Write-LogInfo -Message "Submitting ACME order" -Context @{
            domain             = $Config.domain_name
            challenge_directory = $effectiveChallengeDir
            key_length          = $keyLength
        }

        $paCertificate = New-PACertificate @certificateParams

        if ($paCertificate -is [System.Array]) {
            $paCertificate = $paCertificate | Select-Object -First 1
        }

        if (-not $paCertificate) {
            throw "New-PACertificate did not return certificate metadata."
        }

        $notAfter = $null
        if ($paCertificate.PSObject.Properties.Name -contains 'NotAfter') {
            $notAfter = $paCertificate.NotAfter
        }

        $subjectValue = if ($paCertificate.PSObject.Properties.Name -contains 'Subject' -and $paCertificate.Subject) {
            $paCertificate.Subject
        } else {
            $Config.domain_name
        }

        Write-LogInfo -Message "Certificate issued" -Context @{
            subject   = $subjectValue
            not_after = if ($notAfter) { $notAfter.ToString('u') } else { '' }
        }

        if (-not (Save-CertificateFiles -PACertificate $paCertificate -Config $Config)) {
            throw "Failed to persist certificate files."
        }

        $reloadParams = @{}
        if ($Config.ContainsKey('service_reload_container_name') -and -not [string]::IsNullOrWhiteSpace($Config.service_reload_container_name)) {
            $reloadParams['ContainerName'] = $Config.service_reload_container_name
        }
        if ($Config.ContainsKey('service_reload_timeout_seconds') -and $Config.service_reload_timeout_seconds -gt 0) {
            $reloadParams['TimeoutSeconds'] = $Config.service_reload_timeout_seconds
        }

        if (Invoke-NginxReload @reloadParams) {
            Write-LogInfo -Message "Service reload succeeded" -Context @{ container = $reloadParams.ContainerName }
        } else {
            Write-LogWarn -Message "Service reload failed - manual intervention may be required"
        }

        Write-LogInfo -Message "Certificate renewal completed" -Context @{ domain = $Config.domain_name; cert_path = $Config.cert_path }
        return $true
    }
    catch {
        Write-LogError -Message "Certificate renewal failed" -Context @{ error = $_.Exception.Message; stack_trace = $_.ScriptStackTrace }
        return $false
    }
}

function Start-JwkAgent {
    if (-not (Get-Command -Name Write-LogInfo -ErrorAction SilentlyContinue)) {
        Import-Module (Join-Path $script:CommonModuleDirectory 'Logger.psm1') -Force -Global
    }

    if (-not (Get-Command -Name Write-LogInfo -ErrorAction SilentlyContinue)) {
        throw "JWK agent: Logger module failed to load; Write-LogInfo unavailable."
    }

    Write-LogInfo -Message "JWK certificate agent starting" -Context @{ powershell_version = $PSVersionTable.PSVersion.ToString() }

    $config = Read-AgentConfig -ConfigFilePath '/agent/config.yaml'
    $pkiSettings = Get-EffectivePkiSettings -Config $config
    Initialize-PoshAcmeEnvironment -Config $config -PkiSettings $pkiSettings
    $null = Ensure-JwkAccount -Config $config

    $checkInterval = if ($config.ContainsKey('check_interval_sec')) { [int]$config.check_interval_sec } else { 60 }
    if ($checkInterval -lt 1) { $checkInterval = 60 }

    while ($true) {
        try {
            $certExists = Test-CertificateExists -Path $config.cert_path
            $needsRenewal = -not $certExists
            $lifetimeElapsedPercent = 0

            if ($certExists) {
                $certInfo = Get-CertificateInfo -Path $config.cert_path
                $lifetimeElapsedPercent = $certInfo.LifetimeElapsedPercent

                Write-LogInfo -Message "Certificate check" -Context @{
                    cert_path = $config.cert_path
                    lifetime_elapsed_pct = $lifetimeElapsedPercent
                    threshold_pct = $config.renewal_threshold_pct
                    not_after = $certInfo.NotAfter.ToString('u')
                }

                if ($lifetimeElapsedPercent -gt $config.renewal_threshold_pct) {
                    $needsRenewal = $true
                }

                $crlResult = Test-CertificateAgainstCrl -Config $config -CertPath $config.cert_path
                if ($crlResult.CrlEnabled -and $crlResult.CrlChecked -and $crlResult.Revoked) {
                    Write-LogWarn -Message "Renewal triggered because certificate is revoked"
                    $needsRenewal = $true
                }
            } else {
                Write-LogInfo -Message "Certificate not found; initial issuance required"
            }

            $forceFile = '/tmp/force-renew'
            if (Test-Path -Path $forceFile) {
                $needsRenewal = $true
                Write-LogInfo -Message "Force-renewal triggered" -Context @{ trigger_file = $forceFile }
                Remove-Item -Path $forceFile -Force -ErrorAction SilentlyContinue
            }

            if ($needsRenewal) {
                if (Invoke-CertificateRenewal -Config $config) {
                    Write-LogInfo -Message "Certificate renewal succeeded"
                } else {
                    Write-LogWarn -Message "Certificate renewal failed - will retry next cycle"
                }
            } else {
                Write-LogDebug -Message "Certificate renewal not required"
            }
        }
        catch {
            Write-LogError -Message "Main loop iteration failed" -Context @{ error = $_.Exception.Message; stack_trace = $_.ScriptStackTrace }
            Start-Sleep -Seconds 10
        }

        Write-LogInfo -Message "Sleeping" -Context @{ check_interval_sec = $checkInterval }
        Start-Sleep -Seconds $checkInterval
    }
}

Start-JwkAgent
