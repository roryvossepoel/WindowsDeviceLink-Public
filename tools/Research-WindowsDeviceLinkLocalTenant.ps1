<#
.SYNOPSIS
Read-only research helper for issue #34: local tenant identification from Device Link UEFI/JWT.

.DESCRIPTION
Reads DeviceLinkJwtCompressed through WindowsDeviceLink's private firmware reader and inspects
only a strict allowlist of tenant-identifying JWT metadata. The raw JWT, signature, complete
payload, TPM material and unrelated claim values are never returned or written.

This is a research helper, not a supported public module command.

Requires an elevated PowerShell session for firmware access.
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
            if ($text -match '^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]*$') {
                return $text
            }
        }
        catch {}
        return $null
    }

    $jwt = Try-Utf8Jwt -Candidate $Bytes
    if ($jwt) {
        return [pscustomobject]@{ Encoding='Utf8'; Text=$jwt }
    }

    if ($Bytes.Length -ge 2 -and $Bytes[0] -eq 0x1f -and $Bytes[1] -eq 0x8b) {
        try {
            $input = New-Object IO.MemoryStream(,$Bytes)
            $gzip = New-Object IO.Compression.GZipStream($input,[IO.Compression.CompressionMode]::Decompress)
            $output = New-Object IO.MemoryStream
            $gzip.CopyTo($output)
            $gzip.Dispose(); $input.Dispose()
            $jwt = Try-Utf8Jwt -Candidate $output.ToArray()
            $output.Dispose()
            if ($jwt) {
                return [pscustomobject]@{ Encoding='GZip'; Text=$jwt }
            }
        }
        catch {}
    }

    try {
        $input = New-Object IO.MemoryStream(,$Bytes)
        $deflate = New-Object IO.Compression.DeflateStream($input,[IO.Compression.CompressionMode]::Decompress)
        $output = New-Object IO.MemoryStream
        $deflate.CopyTo($output)
        $deflate.Dispose(); $input.Dispose()
        $jwt = Try-Utf8Jwt -Candidate $output.ToArray()
        $output.Dispose()
        if ($jwt) {
            return [pscustomobject]@{ Encoding='Deflate'; Text=$jwt }
        }
    }
    catch {}

    return $null
}

$resolvedModule = (Resolve-Path -LiteralPath $ModulePath -ErrorAction Stop).Path
Remove-Module WindowsDeviceLink -Force -ErrorAction SilentlyContinue
Import-Module $resolvedModule -Force -ErrorAction Stop
$module = Get-Module WindowsDeviceLink | Select-Object -First 1
if (-not $module) { throw 'WindowsDeviceLink did not load.' }

$firmware = @(Get-WindowsDeviceLinkFirmwareState)
$jwtState = $firmware | Where-Object Name -eq 'DeviceLinkJwtCompressed' | Select-Object -First 1

if (-not $jwtState -or -not $jwtState.Present) {
    [pscustomobject]@{
        PSTypeName            = 'Windows.DeviceLink.LocalTenantResearch'
        AssociatedJwtPresent  = $false
        FirmwareState         = ('{0}/4' -f (@($firmware | Where-Object Present).Count))
        Encoding              = $null
        Algorithm             = $null
        HeaderKeyId           = $null
        HeaderX5t             = $null
        IssuedAtUtc           = $null
        NotBeforeUtc          = $null
        ExpiresUtc            = $null
        SourceVariable        = 'DeviceLinkJwtCompressed'
        SourceClaim           = $null
        TenantId              = $null
        CandidateTenantId     = $null
        CandidateTenantClaim  = $null
        Issuer                = $null
        Audience              = $null
        DiscoveryUrl          = $null
        DiscoveryHost         = $null
        DiscoveryPath         = $null
        UriClaims             = @()
        TenantRelatedClaims   = @()
        HeaderClaimNames      = @()
        PayloadClaimNames     = @()
        SignatureValidation   = 'NotPerformed'
        Conclusion            = 'No local Association JWT is present. Tenant identification cannot be attempted from DeviceLinkJwtCompressed in this state.'
    }
    return
}

$raw = & $module { Get-WindowsDeviceLinkFirmwareVariableBytes -Name DeviceLinkJwtCompressed }
if (-not $raw.Present -or -not $raw.Bytes) {
    throw 'Firmware metadata reports DeviceLinkJwtCompressed as present, but its bytes could not be read.'
}

try {
    $decoded = Get-JwtTextFromBytes -Bytes $raw.Bytes
    if (-not $decoded) {
        throw 'DeviceLinkJwtCompressed could not be decoded as UTF-8, GZip or Deflate JWT text.'
    }

    $parts = $decoded.Text.Split('.')
    if ($parts.Count -ne 3) {
        throw 'Decoded Association JWT does not contain exactly three JWT segments.'
    }

    $header = [Text.Encoding]::UTF8.GetString((ConvertFrom-Base64Url $parts[0])) | ConvertFrom-Json -ErrorAction Stop
    $payload = [Text.Encoding]::UTF8.GetString((ConvertFrom-Base64Url $parts[1])) | ConvertFrom-Json -ErrorAction Stop

    $candidateNames = @(
        'tid',
        'tenantId',
        'tenant_id',
        'tenant',
        'directoryId',
        'directory_id'
    )

    $candidateTenantId = $null
    $candidateTenantClaim = $null
    foreach ($name in $candidateNames) {
        if ($payload.PSObject.Properties.Name -contains $name) {
            $value = [string]$payload.$name
            if (-not [string]::IsNullOrWhiteSpace($value)) {
                $candidateTenantId = $value
                $candidateTenantClaim = $name
                break
            }
        }
    }

    function ConvertFrom-EpochClaim {
        param($Value)
        if ($null -eq $Value) { return $null }
        try { return [DateTimeOffset]::FromUnixTimeSeconds([int64]$Value).UtcDateTime } catch { return $null }
    }

    $tenantRelatedClaims = @(
        $payload.PSObject.Properties.Name |
            Where-Object { $_ -match '(?i)(tenant|directory|issuer|authority|domain|organization|org|tid)' } |
            Sort-Object -Unique
    )

    $issuer = if ($payload.PSObject.Properties.Name -contains 'iss') { [string]$payload.iss } else { $null }
    $audience = if ($payload.PSObject.Properties.Name -contains 'aud') {
        if ($payload.aud -is [System.Collections.IEnumerable] -and $payload.aud -isnot [string]) {
            @($payload.aud) -join ', '
        }
        else { [string]$payload.aud }
    }
    else { $null }

    $discoveryUrl = if ($payload.PSObject.Properties.Name -contains 'discoveryUrl') { [string]$payload.discoveryUrl } else { $null }
    $discoveryHost = $null
    $discoveryPath = $null
    if (-not [string]::IsNullOrWhiteSpace($discoveryUrl)) {
        try {
            $uri = [Uri]$discoveryUrl
            if ($uri.IsAbsoluteUri) {
                $discoveryHost = $uri.Host
                $discoveryPath = $uri.AbsolutePath
            }
        }
        catch {}
    }

    $uriClaims = New-Object System.Collections.Generic.List[object]
    foreach ($property in $payload.PSObject.Properties) {
        $values = @()
        if ($property.Value -is [string]) {
            $values = @([string]$property.Value)
        }
        elseif ($property.Value -is [System.Collections.IEnumerable] -and $property.Value -isnot [string]) {
            $values = @($property.Value | Where-Object { $_ -is [string] } | ForEach-Object { [string]$_ })
        }

        foreach ($value in $values) {
            try {
                $candidateUri = [Uri]$value
                if ($candidateUri.IsAbsoluteUri -and $candidateUri.Scheme -eq 'https') {
                    $uriClaims.Add([pscustomobject]@{
                        ClaimName = $property.Name
                        Scheme    = $candidateUri.Scheme
                        Host      = $candidateUri.Host
                        Path      = $candidateUri.AbsolutePath
                    })
                }
            }
            catch {}
        }
    }

    [pscustomobject]@{
        PSTypeName            = 'Windows.DeviceLink.LocalTenantResearch'
        AssociatedJwtPresent  = $true
        FirmwareState         = ('{0}/4' -f (@($firmware | Where-Object Present).Count))
        Encoding              = $decoded.Encoding
        Algorithm             = if ($header.PSObject.Properties.Name -contains 'alg') { [string]$header.alg } else { $null }
        HeaderKeyId           = if ($header.PSObject.Properties.Name -contains 'kid') { [string]$header.kid } else { $null }
        HeaderX5t             = if ($header.PSObject.Properties.Name -contains 'x5t') { [string]$header.x5t } else { $null }
        IssuedAtUtc           = if ($payload.PSObject.Properties.Name -contains 'iat') { ConvertFrom-EpochClaim $payload.iat } else { $null }
        NotBeforeUtc          = if ($payload.PSObject.Properties.Name -contains 'nbf') { ConvertFrom-EpochClaim $payload.nbf } else { $null }
        ExpiresUtc            = if ($payload.PSObject.Properties.Name -contains 'exp') { ConvertFrom-EpochClaim $payload.exp } else { $null }
        SourceVariable        = 'DeviceLinkJwtCompressed'
        SourceClaim           = $candidateTenantClaim
        TenantId              = $candidateTenantId
        CandidateTenantId     = $candidateTenantId
        CandidateTenantClaim  = $candidateTenantClaim
        Issuer                = $issuer
        Audience              = $audience
        DiscoveryUrl          = $discoveryUrl
        DiscoveryHost         = $discoveryHost
        DiscoveryPath         = $discoveryPath
        UriClaims             = $uriClaims.ToArray()
        TenantRelatedClaims   = $tenantRelatedClaims
        HeaderClaimNames      = @($header.PSObject.Properties.Name | Sort-Object -Unique)
        PayloadClaimNames     = @($payload.PSObject.Properties.Name | Sort-Object -Unique)
        SignatureValidation   = 'NotPerformed'
        Conclusion            = if ($candidateTenantId) {
            "A candidate tenant identifier was found in claim '$candidateTenantClaim'. Correlate it with the known tenant before treating it as authoritative."
        }
        else {
            'No direct tenant-ID claim was found in the allowlisted claim names. Review issuer/audience and tenant-related claim names for indirect tenant identification.'
        }
    }
}
finally {
    if ($raw -and $raw.Bytes) {
        [Array]::Clear($raw.Bytes,0,$raw.Bytes.Length)
    }
    $raw = $null
}
