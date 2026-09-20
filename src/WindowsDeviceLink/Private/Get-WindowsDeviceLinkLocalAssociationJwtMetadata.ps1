function Get-WindowsDeviceLinkLocalAssociationJwtMetadata {
    [CmdletBinding()]
    param()

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

    $raw = Get-WindowsDeviceLinkFirmwareVariableBytes -Name DeviceLinkJwtCompressed
    if (-not $raw.Present -or -not $raw.Bytes) {
        return [pscustomobject]@{
            Present=$false; ParseState='Absent'; Encoding=$null; TenantId=$null; TenantClaim=$null; DiscoveryUrl=$null; SignatureValidation='NotPerformed'
        }
    }

    try {
        $jwtText = Try-GetUtf8JwtText -InputBytes $raw.Bytes
        $encoding = 'Utf8'

        if (-not $jwtText -and $raw.Bytes.Length -ge 2 -and $raw.Bytes[0] -eq 0x1f -and $raw.Bytes[1] -eq 0x8b) {
            try {
                $inputStream = New-Object IO.MemoryStream(,$raw.Bytes)
                $gzip = New-Object IO.Compression.GZipStream($inputStream, [IO.Compression.CompressionMode]::Decompress)
                $outputStream = New-Object IO.MemoryStream
                $gzip.CopyTo($outputStream)
                $gzip.Dispose(); $inputStream.Dispose()
                $jwtText = Try-GetUtf8JwtText -InputBytes $outputStream.ToArray()
                $outputStream.Dispose()
                if ($jwtText) { $encoding = 'GZip' }
            }
            catch {}
        }

        if (-not $jwtText) {
            try {
                $inputStream = New-Object IO.MemoryStream(,$raw.Bytes)
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
                Present=$true; ParseState='Malformed'; Encoding='Unknown'; TenantId=$null; TenantClaim=$null; DiscoveryUrl=$null; SignatureValidation='NotPerformed'
            }
        }

        try {
            $parts = $jwtText.Split('.')
            if ($parts.Count -ne 3) { throw 'Invalid segment count.' }
            $payloadJson = [Text.Encoding]::UTF8.GetString((ConvertFrom-Base64UrlString $parts[1]))
            $payload = $payloadJson | ConvertFrom-Json -ErrorAction Stop
        }
        catch {
            return [pscustomobject]@{
                Present=$true; ParseState='Malformed'; Encoding=$encoding; TenantId=$null; TenantClaim=$null; DiscoveryUrl=$null; SignatureValidation='NotPerformed'
            }
        }

        $tenantId = $null
        $tenantClaim = $null
        foreach ($claimName in @('tenantId','tid','tenant_id','tenant','directoryId','directory_id')) {
            if ($payload.PSObject.Properties.Name -contains $claimName) {
                $value = [string]$payload.$claimName
                if (-not [string]::IsNullOrWhiteSpace($value)) {
                    $tenantId = $value.Trim().Trim('{','}')
                    $tenantClaim = $claimName
                    break
                }
            }
        }

        $discoveryUrl = if ($payload.PSObject.Properties.Name -contains 'discoveryUrl') { [string]$payload.discoveryUrl } else { $null }

        [pscustomobject]@{
            Present=$true; ParseState='Parsed'; Encoding=$encoding; TenantId=$tenantId; TenantClaim=$tenantClaim; DiscoveryUrl=$discoveryUrl; SignatureValidation='NotPerformed'
        }
    }
    finally {
        if ($raw -and $raw.Bytes) { [Array]::Clear($raw.Bytes,0,$raw.Bytes.Length) }
        $raw = $null
    }
}
