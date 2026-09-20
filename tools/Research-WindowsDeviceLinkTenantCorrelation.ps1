<#
.SYNOPSIS
Read-only research helper for issue #34: correlate all known local source-tenant signals.

.DESCRIPTION
Correlates the current DeviceLinkId UEFI value with:
- HKLM\SOFTWARE\Microsoft\Provisioning\AutopilotSettings\<LinkId>_TenantIdHint
- the tenantId claim in DeviceLinkJwtCompressed, when present.

The helper never returns the raw Association JWT, signature, DeviceLink payload, TPM material,
or unrelated JWT claim values. It performs no cloud calls and no state changes.

This is research tooling, not a supported public module command.
#>

[CmdletBinding()]
param(
    [string]$ModulePath = (Join-Path $PSScriptRoot '..\src\WindowsDeviceLink\WindowsDeviceLink.psd1')
)

$ErrorActionPreference = 'Stop'

function ConvertFrom-Base64Url {
    param([Parameter(Mandatory)][string]$Value)
    $s = $Value.Replace('-', '+').Replace('_', '/')
    switch ($s.Length % 4) {
        2 { $s += '==' }
        3 { $s += '=' }
    }
    [Convert]::FromBase64String($s)
}

function Get-JwtTextFromBytes {
    param([Parameter(Mandatory)][byte[]]$Bytes)

    function Try-Utf8Jwt {
        param([byte[]]$Candidate)
        try {
            $text = [Text.Encoding]::UTF8.GetString($Candidate).Trim([char]0).Trim()
            if ($text -match '^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]*$') { return $text }
        } catch {}
        return $null
    }

    $jwt = Try-Utf8Jwt -Candidate $Bytes
    if ($jwt) { return [pscustomobject]@{ Encoding='Utf8'; Text=$jwt } }

    if ($Bytes.Length -ge 2 -and $Bytes[0] -eq 0x1f -and $Bytes[1] -eq 0x8b) {
        try {
            $input = New-Object IO.MemoryStream(,$Bytes)
            $gzip = New-Object IO.Compression.GZipStream($input,[IO.Compression.CompressionMode]::Decompress)
            $output = New-Object IO.MemoryStream
            $gzip.CopyTo($output)
            $gzip.Dispose(); $input.Dispose()
            $jwt = Try-Utf8Jwt -Candidate $output.ToArray()
            $output.Dispose()
            if ($jwt) { return [pscustomobject]@{ Encoding='GZip'; Text=$jwt } }
        } catch {}
    }

    try {
        $input = New-Object IO.MemoryStream(,$Bytes)
        $deflate = New-Object IO.Compression.DeflateStream($input,[IO.Compression.CompressionMode]::Decompress)
        $output = New-Object IO.MemoryStream
        $deflate.CopyTo($output)
        $deflate.Dispose(); $input.Dispose()
        $jwt = Try-Utf8Jwt -Candidate $output.ToArray()
        $output.Dispose()
        if ($jwt) { return [pscustomobject]@{ Encoding='Deflate'; Text=$jwt } }
    } catch {}

    return $null
}

function ConvertFrom-DeviceLinkIdBytes {
    param([Parameter(Mandatory)][byte[]]$Bytes)

    foreach ($encoding in @([Text.Encoding]::UTF8,[Text.Encoding]::Unicode)) {
        try {
            $text = $encoding.GetString($Bytes).Trim([char]0).Trim().Trim('{','}')
            $guid = [guid]::Empty
            if ([guid]::TryParse($text,[ref]$guid)) {
                return $guid.ToString().ToUpperInvariant()
            }
        } catch {}
    }

    return $null
}

$resolvedModule = (Resolve-Path -LiteralPath $ModulePath -ErrorAction Stop).Path
Remove-Module WindowsDeviceLink -Force -ErrorAction SilentlyContinue
Import-Module $resolvedModule -Force -ErrorAction Stop
$module = Get-Module WindowsDeviceLink | Select-Object -First 1
if (-not $module) { throw 'WindowsDeviceLink did not load.' }

$firmware = @(Get-WindowsDeviceLinkFirmwareState)
$presentCount = @($firmware | Where-Object Present).Count

$linkRaw = & $module { Get-WindowsDeviceLinkFirmwareVariableBytes -Name DeviceLinkId }
if (-not $linkRaw.Present -or -not $linkRaw.Bytes) {
    [pscustomobject]@{
        PSTypeName                   = 'Windows.DeviceLink.TenantCorrelationResearch'
        FirmwareState                = ('{0}/4' -f $presentCount)
        CurrentLinkId                = $null
        RegistryPath                 = 'HKLM:\SOFTWARE\Microsoft\Provisioning\AutopilotSettings'
        RegistryCurrentHintPresent   = $false
        RegistryTenantIdHint         = $null
        RegistryDiscoveryUrl         = $null
        HistoricalTenantHintCount    = 0
        JwtPresent                   = $false
        JwtEncoding                  = $null
        JwtTenantId                  = $null
        JwtTenantClaim               = $null
        RegistryMatchesJwt           = $null
        SourceTenantId               = $null
        SourceTenantSource           = 'Unavailable'
        TrustLevel                   = 'Unavailable'
        SignatureValidation          = 'NotPerformed'
        ConflictDetected             = $false
        MutationPerformed            = $false
        Conclusion                   = 'The current DeviceLinkId UEFI value is not available, so LinkId-scoped local tenant correlation cannot be performed.'
    }
    return
}

try {
    $currentLinkId = ConvertFrom-DeviceLinkIdBytes -Bytes $linkRaw.Bytes
    if (-not $currentLinkId) {
        throw 'The current DeviceLinkId firmware value could not be safely decoded as a GUID.'
    }

    $registryPath = 'HKLM:\SOFTWARE\Microsoft\Provisioning\AutopilotSettings'
    $registryTenant = $null
    $registryDiscovery = $null
    $registryHintPresent = $false
    $historicalHintCount = 0

    if (Test-Path -LiteralPath $registryPath) {
        $registry = Get-ItemProperty -LiteralPath $registryPath -ErrorAction Stop
        $tenantPropertyName = "${currentLinkId}_TenantIdHint"
        $discoveryPropertyName = "${currentLinkId}_DiscoveryUrl"

        $historicalHintCount = @(
            $registry.PSObject.Properties |
                Where-Object { $_.Name -match '(?i)_TenantIdHint$' }
        ).Count

        if ($registry.PSObject.Properties.Name -contains $tenantPropertyName) {
            $value = [string]$registry.$tenantPropertyName
            if (-not [string]::IsNullOrWhiteSpace($value)) {
                $registryTenant = $value.Trim().Trim('{','}')
                $registryHintPresent = $true
            }
        }

        if ($registry.PSObject.Properties.Name -contains $discoveryPropertyName) {
            $value = [string]$registry.$discoveryPropertyName
            if (-not [string]::IsNullOrWhiteSpace($value)) {
                $registryDiscovery = $value
            }
        }
    }

    $jwtPresent = $false
    $jwtEncoding = $null
    $jwtTenant = $null
    $jwtTenantClaim = $null
    $jwtRaw = & $module { Get-WindowsDeviceLinkFirmwareVariableBytes -Name DeviceLinkJwtCompressed }

    try {
        if ($jwtRaw.Present -and $jwtRaw.Bytes) {
            $jwtPresent = $true
            $decoded = Get-JwtTextFromBytes -Bytes $jwtRaw.Bytes
            if ($decoded) {
                $jwtEncoding = $decoded.Encoding
                $parts = $decoded.Text.Split('.')
                if ($parts.Count -eq 3) {
                    $payload = [Text.Encoding]::UTF8.GetString((ConvertFrom-Base64Url $parts[1])) | ConvertFrom-Json -ErrorAction Stop
                    foreach ($name in @('tenantId','tid','tenant_id','tenant','directoryId','directory_id')) {
                        if ($payload.PSObject.Properties.Name -contains $name) {
                            $value = [string]$payload.$name
                            if (-not [string]::IsNullOrWhiteSpace($value)) {
                                $jwtTenant = $value.Trim().Trim('{','}')
                                $jwtTenantClaim = $name
                                break
                            }
                        }
                    }
                }
            }
        }
    }
    finally {
        if ($jwtRaw -and $jwtRaw.Bytes) { [Array]::Clear($jwtRaw.Bytes,0,$jwtRaw.Bytes.Length) }
        $jwtRaw = $null
    }

    $registryMatchesJwt = $null
    if ($registryTenant -and $jwtTenant) {
        $registryMatchesJwt = [string]::Equals($registryTenant,$jwtTenant,[StringComparison]::OrdinalIgnoreCase)
    }

    $conflict = ($registryMatchesJwt -eq $false)
    $sourceTenantId = $null
    $sourceTenantSource = 'Unavailable'
    $trustLevel = 'Unavailable'
    $conclusion = $null

    if ($conflict) {
        $sourceTenantSource = 'Conflict'
        $trustLevel = 'Conflict'
        $conclusion = 'The current-LinkId registry TenantIdHint and local Association JWT tenantId disagree. Do not choose a source tenant automatically.'
    }
    elseif ($registryTenant -and $jwtTenant) {
        $sourceTenantId = $jwtTenant
        $sourceTenantSource = 'RegistryAndAssociationJwt'
        $trustLevel = 'CorrelatedLocalSources'
        $conclusion = 'The current-LinkId registry TenantIdHint and local Association JWT tenantId agree. Both local sources identify the same tenant.'
    }
    elseif ($jwtTenant) {
        $sourceTenantId = $jwtTenant
        $sourceTenantSource = 'AssociationJwt'
        $trustLevel = 'StructurallyObservedJwtClaim'
        $conclusion = 'The tenant was identified from the local Association JWT only. The JWT signature has not been cryptographically verified.'
    }
    elseif ($registryTenant) {
        $sourceTenantId = $registryTenant
        $sourceTenantSource = 'CurrentLinkIdRegistryHint'
        $trustLevel = 'LocalRegistryHint'
        $conclusion = 'The tenant was identified from the TenantIdHint exactly scoped to the current DeviceLinkId. No local Association JWT tenant claim is available.'
    }
    else {
        $conclusion = 'No tenant identifier was found for the current DeviceLinkId in either known local source.'
    }

    [pscustomobject]@{
        PSTypeName                   = 'Windows.DeviceLink.TenantCorrelationResearch'
        FirmwareState                = ('{0}/4' -f $presentCount)
        CurrentLinkId                = $currentLinkId
        RegistryPath                 = $registryPath
        RegistryCurrentHintPresent   = $registryHintPresent
        RegistryTenantIdHint         = $registryTenant
        RegistryDiscoveryUrl         = $registryDiscovery
        HistoricalTenantHintCount    = $historicalHintCount
        JwtPresent                   = $jwtPresent
        JwtEncoding                  = $jwtEncoding
        JwtTenantId                  = $jwtTenant
        JwtTenantClaim               = $jwtTenantClaim
        RegistryMatchesJwt           = $registryMatchesJwt
        SourceTenantId               = $sourceTenantId
        SourceTenantSource           = $sourceTenantSource
        TrustLevel                   = $trustLevel
        SignatureValidation          = 'NotPerformed'
        ConflictDetected             = $conflict
        MutationPerformed            = $false
        Conclusion                   = $conclusion
    }
}
finally {
    if ($linkRaw -and $linkRaw.Bytes) { [Array]::Clear($linkRaw.Bytes,0,$linkRaw.Bytes.Length) }
    $linkRaw = $null
}
