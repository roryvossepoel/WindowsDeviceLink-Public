function ConvertFrom-WindowsDeviceLinkFirmwareTimestamp {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [byte[]]$Bytes
    )

    $result = [ordered]@{
        DecodedValue = $null
        ParsedUtc    = $null
    }

    if ($null -eq $Bytes -or $Bytes.Length -eq 0) {
        return [pscustomobject]$result
    }

    # DeviceLinkCreationTimeUtc is the only firmware value that may be decoded.
    # Keep the accepted representation deliberately narrow so arbitrary binary or
    # sensitive firmware contents can never be surfaced through this helper.
    $candidate = [Text.Encoding]::UTF8.GetString($Bytes)
    if ($candidate -notmatch '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,7})?Z$') {
        return [pscustomobject]$result
    }

    $parsed = [DateTimeOffset]::MinValue
    if (-not [DateTimeOffset]::TryParse(
        $candidate,
        [Globalization.CultureInfo]::InvariantCulture,
        [Globalization.DateTimeStyles]::AssumeUniversal -bor [Globalization.DateTimeStyles]::AdjustToUniversal,
        [ref]$parsed
    )) {
        return [pscustomobject]$result
    }

    $result.DecodedValue = $candidate
    $result.ParsedUtc = $parsed.UtcDateTime
    [pscustomobject]$result
}
