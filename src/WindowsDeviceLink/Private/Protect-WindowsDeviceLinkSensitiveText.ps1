function Protect-WindowsDeviceLinkSensitiveText {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [string]$Text,

        [AllowNull()]
        [string[]]$SensitiveValue
    )

    if ($null -eq $Text) { return $null }

    $protected = [string]$Text
    foreach ($value in @($SensitiveValue)) {
        if ([string]::IsNullOrWhiteSpace($value)) { continue }
        $protected = $protected.Replace([string]$value, '[REDACTED]')
    }

    # Defensive fallback for exception text that happens to include an HTTP
    # Authorization header even when the exact token value was not supplied.
    $protected = [regex]::Replace(
        $protected,
        '(?i)\bBearer\s+[A-Za-z0-9\-\._~\+/]+=*',
        'Bearer [REDACTED]'
    )

    $protected
}
