<#
.SYNOPSIS
Read-only research helper for issue #34: locate the published signing key for a local Device Link Association JWT.

.DESCRIPTION
Reads only safe metadata from the local Association JWT and probes Microsoft-hosted discovery/JWKS
endpoints derived from its discoveryUrl. The JWT itself is never transmitted.

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
        $null
    }

    $jwt = Try-Utf8Jwt $Bytes
    if ($jwt) { return $jwt }

    if ($Bytes.Length -ge 2 -and $Bytes[0] -eq 0x1f -and $Bytes[1] -eq 0x8b) {
        try {
            $input = New-Object IO.MemoryStream(,$Bytes)
            $gzip = New-Object IO.Compression.GZipStream($input,[IO.Compression.CompressionMode]::Decompress)
            $output = New-Object IO.MemoryStream
            $gzip.CopyTo($output)
            $gzip.Dispose(); $input.Dispose()
            $jwt = Try-Utf8Jwt $output.ToArray()
            $output.Dispose()
            if ($jwt) { return $jwt }
        } catch {}
    }

    try {
        $input = New-Object IO.MemoryStream(,$Bytes)
        $deflate = New-Object IO.Compression.DeflateStream($input,[IO.Compression.CompressionMode]::Decompress)
        $output = New-Object IO.MemoryStream
        $deflate.CopyTo($output)
        $deflate.Dispose(); $input.Dispose()
        $jwt = Try-Utf8Jwt $output.ToArray()
        $output.Dispose()
        if ($jwt) { return $jwt }
    } catch {}

    $null
}

function Test-AllowedMicrosoftUri {
    param([Parameter(Mandatory)][Uri]$Uri)

    if ($Uri.Scheme -ne 'https') { return $false }

    $uriHost = $Uri.Host.ToLowerInvariant()
    $allowedSuffixes = @(
        '.microsoft.com',
        '.microsoftonline.com',
        '.windows.net',
        '.azure.com',
        '.manage.microsoft.com'
    )

    foreach ($suffix in $allowedSuffixes) {
        if ($uriHost -eq $suffix.TrimStart('.') -or $uriHost.EndsWith($suffix)) { return $true }
    }

    return $false
}

function Invoke-SafeJsonGet {
    param([Parameter(Mandatory)][string]$Uri)

    try {
        $u = [Uri]$Uri
    } catch {
        return [pscustomobject]@{ Uri=$Uri; Allowed=$false; Status='InvalidUri'; Json=$null; Error='Invalid URI.' }
    }

    if (-not (Test-AllowedMicrosoftUri $u)) {
        return [pscustomobject]@{ Uri=$Uri; Allowed=$false; Status='BlockedHost'; Json=$null; Error='Host is outside the Microsoft allowlist.' }
    }

    try {
        $response = Invoke-RestMethod -Method Get -Uri $u.AbsoluteUri -ErrorAction Stop
        return [pscustomobject]@{ Uri=$u.AbsoluteUri; Allowed=$true; Status='Success'; Json=$response; Error=$null }
    }
    catch {
        $msg = $_.Exception.Message
        return [pscustomobject]@{ Uri=$u.AbsoluteUri; Allowed=$true; Status='Failed'; Json=$null; Error=$msg }
    }
}

$resolvedModule = (Resolve-Path -LiteralPath $ModulePath -ErrorAction Stop).Path
Remove-Module WindowsDeviceLink -Force -ErrorAction SilentlyContinue
Import-Module $resolvedModule -Force -ErrorAction Stop
$module = Get-Module WindowsDeviceLink | Select-Object -First 1
if (-not $module) { throw 'WindowsDeviceLink did not load.' }

$raw = & $module { Get-WindowsDeviceLinkFirmwareVariableBytes -Name DeviceLinkJwtCompressed }
if (-not $raw.Present -or -not $raw.Bytes) {
    throw 'DeviceLinkJwtCompressed is not present.'
}

try {
    $jwt = Get-JwtTextFromBytes -Bytes $raw.Bytes
    if (-not $jwt) { throw 'DeviceLinkJwtCompressed could not be decoded as a JWT.' }

    $parts = $jwt.Split('.')
    if ($parts.Count -ne 3) { throw 'Association JWT does not contain exactly three segments.' }

    $header = [Text.Encoding]::UTF8.GetString((ConvertFrom-Base64Url $parts[0])) | ConvertFrom-Json -ErrorAction Stop
    $payload = [Text.Encoding]::UTF8.GetString((ConvertFrom-Base64Url $parts[1])) | ConvertFrom-Json -ErrorAction Stop

    $kid = [string]$header.kid
    $x5t = [string]$header.x5t
    $discoveryUrl = [string]$payload.discoveryUrl

    if ([string]::IsNullOrWhiteSpace($discoveryUrl)) {
        throw 'The local Association JWT does not expose discoveryUrl.'
    }

    $base = ([Uri]$discoveryUrl).GetLeftPart([UriPartial]::Authority)
    $discoveryUri = [Uri]$discoveryUrl
    $serviceBase = $discoveryUrl.TrimEnd('/')

    $candidates = @(
        "$serviceBase/.well-known/openid-configuration",
        "$serviceBase/.well-known/jwks",
        $serviceBase,
        "$base/.well-known/openid-configuration",
        "$base/.well-known/jwks"
    ) | Select-Object -Unique

    $results = New-Object System.Collections.Generic.List[object]
    $jwksEndpoint = $null
    $jwks = $null

    foreach ($candidate in $candidates) {
        $probe = Invoke-SafeJsonGet -Uri $candidate

        $hasKeys = $false
        $jwksUri = $null
        if ($probe.Json) {
            if ($probe.Json.PSObject.Properties.Name -contains 'keys' -and $probe.Json.keys) {
                $hasKeys = $true
                if (-not $jwks) {
                    $jwks = $probe.Json
                    $jwksEndpoint = $probe.Uri
                }
            }
            if ($probe.Json.PSObject.Properties.Name -contains 'jwks_uri' -and $probe.Json.jwks_uri) {
                $jwksUri = [string]$probe.Json.jwks_uri
            }
        }

        $results.Add([pscustomobject]@{
            Uri      = $probe.Uri
            Status   = $probe.Status
            HasKeys  = $hasKeys
            JwksUri  = $jwksUri
            Error    = $probe.Error
        })

        if (-not $jwks -and $jwksUri) {
            $jwksProbe = Invoke-SafeJsonGet -Uri $jwksUri
            $jwksHasKeys = $false
            if ($jwksProbe.Json -and $jwksProbe.Json.PSObject.Properties.Name -contains 'keys' -and $jwksProbe.Json.keys) {
                $jwksHasKeys = $true
                $jwks = $jwksProbe.Json
                $jwksEndpoint = $jwksProbe.Uri
            }

            $results.Add([pscustomobject]@{
                Uri      = $jwksProbe.Uri
                Status   = $jwksProbe.Status
                HasKeys  = $jwksHasKeys
                JwksUri  = $null
                Error    = $jwksProbe.Error
            })
        }
    }

    $keyCount = 0
    $kidMatch = $false
    $x5tMatch = $false
    $matchingKeyMetadata = $null

    if ($jwks -and $jwks.keys) {
        $keys = @($jwks.keys)
        $keyCount = $keys.Count

        foreach ($key in $keys) {
            $keyKid = if ($key.PSObject.Properties.Name -contains 'kid') { [string]$key.kid } else { $null }
            $keyX5t = if ($key.PSObject.Properties.Name -contains 'x5t') { [string]$key.x5t } else { $null }

            $kidIsMatch = (-not [string]::IsNullOrWhiteSpace($kid)) -and (-not [string]::IsNullOrWhiteSpace($keyKid)) -and
                [string]::Equals($kid,$keyKid,[StringComparison]::OrdinalIgnoreCase)
            $x5tIsMatch = (-not [string]::IsNullOrWhiteSpace($x5t)) -and (-not [string]::IsNullOrWhiteSpace($keyX5t)) -and
                [string]::Equals($x5t,$keyX5t,[StringComparison]::OrdinalIgnoreCase)

            if ($kidIsMatch -or $x5tIsMatch) {
                $kidMatch = $kidMatch -or $kidIsMatch
                $x5tMatch = $x5tMatch -or $x5tIsMatch
                $matchingKeyMetadata = [pscustomobject]@{
                    KeyType   = if ($key.PSObject.Properties.Name -contains 'kty') { [string]$key.kty } else { $null }
                    Algorithm = if ($key.PSObject.Properties.Name -contains 'alg') { [string]$key.alg } else { $null }
                    Use       = if ($key.PSObject.Properties.Name -contains 'use') { [string]$key.use } else { $null }
                    Kid       = $keyKid
                    X5t       = $keyX5t
                    HasX5c    = [bool]($key.PSObject.Properties.Name -contains 'x5c' -and $key.x5c)
                    HasRsaN   = [bool]($key.PSObject.Properties.Name -contains 'n' -and $key.n)
                    HasRsaE   = [bool]($key.PSObject.Properties.Name -contains 'e' -and $key.e)
                }
                break
            }
        }
    }

    [pscustomobject]@{
        PSTypeName          = 'Windows.DeviceLink.SigningKeyResearch'
        DiscoveryUrl        = $discoveryUrl
        HeaderKeyId         = $kid
        HeaderX5t           = $x5t
        JwksEndpoint        = $jwksEndpoint
        PublishedKeyCount   = $keyCount
        KidMatched          = $kidMatch
        X5tMatched          = $x5tMatch
        MatchingKeyMetadata = $matchingKeyMetadata
        Probes              = @($results)
        JwtTransmitted      = $false
        MutationPerformed   = $false
        Conclusion          = if ($matchingKeyMetadata) {
            'A published Microsoft-hosted signing key matching the local JWT key identifier was located. Signature verification can be attempted locally next.'
        } elseif ($jwks) {
            'Published signing keys were located, but none matched the local JWT key identifier.'
        } else {
            'No published signing-key set was located through the probed Microsoft-hosted discovery endpoints.'
        }
    }
}
finally {
    if ($raw -and $raw.Bytes) { [Array]::Clear($raw.Bytes,0,$raw.Bytes.Length) }
    $raw = $null
}
