function ConvertFrom-WindowsDeviceLinkIdBytes {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [byte[]]$Bytes
    )

    foreach ($encoding in @([Text.Encoding]::UTF8, [Text.Encoding]::Unicode)) {
        try {
            $text = $encoding.GetString($Bytes).Trim([char]0).Trim().Trim('{','}')
            $guid = [guid]::Empty
            if ([guid]::TryParse($text, [ref]$guid)) {
                return $guid.ToString().ToUpperInvariant()
            }
        }
        catch {}
    }

    $null
}
