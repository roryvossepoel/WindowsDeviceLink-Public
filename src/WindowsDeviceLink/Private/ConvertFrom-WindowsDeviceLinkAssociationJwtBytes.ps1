function ConvertFrom-WindowsDeviceLinkAssociationJwtBytes {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][byte[]]$Bytes,
        [string]$ExpectedLinkId
    )

    function ConvertFrom-Base64UrlString {
        param([Parameter(Mandatory)][string]$Value)
        $s = $Value.Replace('-', '+').Replace('_', '/')
        switch ($s.Length % 4) {
            2 { $s += '==' }
            3 { $s += '=' }
        }
        [Convert]::FromBase64String($s)
    }

    function Try-GetUtf8JwtText {
        param([byte[]]$InputBytes)
        try {
            $text = [Text.Encoding]::UTF8.GetString($InputBytes).Trim([char]0).Trim()
            if ($text -match '^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]*$') { return $text }
        }
        catch {}
        $null
    }

    $jwtText = Try-GetUtf8JwtText -InputBytes $Bytes
    $encoding = 'Utf8'

    if (-not $jwtText -and $Bytes.Length -ge 2 -and $Bytes[0] -eq 0x1f -and $Bytes[1] -eq 0x8b) {
        try {
            $inputStream = New-Object IO.MemoryStream(,$Bytes)
            $gzip = New-Object IO.Compression.GZipStream($inputStream, [IO.Compression.CompressionMode]::Decompress)
            $outputStream = New-Object IO.MemoryStream
            $gzip.CopyTo($outputStream)
            $gzip.Dispose(); $inputStream.Dispose()
            $jwtText = Try-GetUtf8JwtText -InputBytes $outputStream.ToArray()
            $outputStream.Dispose()
            $encoding = 'GZip'
        }
        catch {}
    }

    if (-not $jwtText) {
        try {
            $inputStream = New-Object IO.MemoryStream(,$Bytes)
            $deflate = New-Object IO.Compression.DeflateStream($inputStream, [IO.Compression.CompressionMode]::Decompress)
            $outputStream = New-Object IO.MemoryStream
            $deflate.CopyTo($outputStream)
            $deflate.Dispose(); $inputStream.Dispose()
            $jwtText = Try-GetUtf8JwtText -InputBytes $outputStream.ToArray()
            $outputStream.Dispose()
            if ($jwtText) { $encoding = 'Deflate' }
        }
        catch {}
    }

    if (-not $jwtText) {
        return [pscustomobject]@{
            State='Malformed'; Encoding='Unknown'; Algorithm=$null; IssuedAtUtc=$null; NotBeforeUtc=$null; ExpiresUtc=$null
            IdentityClaimPresent=$false; IdentityMatch=$null; SignatureValidation='NotPerformed'; Reason='The firmware value could not be decoded as a supported JWT encoding.'
        }
    }

    try {
        $parts = $jwtText.Split('.')
        if ($parts.Count -ne 3) { throw 'Invalid segment count.' }
        $headerJson = [Text.Encoding]::UTF8.GetString((ConvertFrom-Base64UrlString $parts[0]))
        $payloadJson = [Text.Encoding]::UTF8.GetString((ConvertFrom-Base64UrlString $parts[1]))
        $header = $headerJson | ConvertFrom-Json -ErrorAction Stop
        $payload = $payloadJson | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        return [pscustomobject]@{
            State='Malformed'; Encoding=$encoding; Algorithm=$null; IssuedAtUtc=$null; NotBeforeUtc=$null; ExpiresUtc=$null
            IdentityClaimPresent=$false; IdentityMatch=$null; SignatureValidation='NotPerformed'; Reason='The decoded value is not a valid parseable JWT structure.'
        }
    }

    $epoch = [DateTimeOffset]::FromUnixTimeSeconds(0)
    function ConvertFrom-EpochClaim {
        param($Value)
        if ($null -eq $Value) { return $null }
        try { return $epoch.AddSeconds([int64]$Value).UtcDateTime } catch { return $null }
    }

    $iat = ConvertFrom-EpochClaim $payload.iat
    $nbf = ConvertFrom-EpochClaim $payload.nbf
    $exp = ConvertFrom-EpochClaim $payload.exp
    $now = [DateTime]::UtcNow

    $identityClaimPresent = $false
    $identityMatch = $null
    foreach ($claimName in @('linkId','deviceLinkId','device_link_id')) {
        if ($payload.PSObject.Properties.Name -contains $claimName) {
            $identityClaimPresent = $true
            if (-not [string]::IsNullOrWhiteSpace($ExpectedLinkId)) {
                $identityMatch = ([string]$payload.$claimName).Trim('{}') -ieq ([string]$ExpectedLinkId).Trim('{}')
            }
            break
        }
    }

    $state = 'Valid'
    $reason = 'JWT structure and observed temporal claims are valid. Cryptographic signature validation was not performed.'
    if ($nbf -and $nbf -gt $now) { $state='NotYetValid'; $reason='The JWT not-before time is in the future.' }
    elseif ($exp -and $exp -le $now) { $state='Expired'; $reason='The JWT expiration time has passed.' }
    elseif ($identityClaimPresent -and $identityMatch -eq $false) { $state='IdentityMismatch'; $reason='An identity claim was present but did not match the observed local LinkId.' }

    [pscustomobject]@{
        State=$state
        Encoding=$encoding
        Algorithm=if ($header.alg) { [string]$header.alg } else { $null }
        IssuedAtUtc=$iat
        NotBeforeUtc=$nbf
        ExpiresUtc=$exp
        IdentityClaimPresent=$identityClaimPresent
        IdentityMatch=$identityMatch
        SignatureValidation='NotPerformed'
        Reason=$reason
    }
}
