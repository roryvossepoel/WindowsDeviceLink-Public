function Resolve-WindowsDeviceLinkPreflightState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object[]]$Checks
    )

    $blocked = @($Checks | Where-Object State -eq 'Blocked')
    $warnings = @($Checks | Where-Object State -eq 'Warning')
    $state = if ($blocked.Count -gt 0) { 'Blocked' } elseif ($warnings.Count -gt 0) { 'Warning' } else { 'Ready' }

    [pscustomobject]@{
        State=$state
        Ready=($state -eq 'Ready')
        BlockingCount=$blocked.Count
        WarningCount=$warnings.Count
    }
}
