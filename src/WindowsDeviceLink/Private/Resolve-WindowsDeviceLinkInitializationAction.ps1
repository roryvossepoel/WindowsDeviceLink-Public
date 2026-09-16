function Resolve-WindowsDeviceLinkInitializationAction {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$HealthState
    )

    switch ($HealthState) {
        'Preassociated' { 'None' }
        'Associated'    { 'None' }
        'LocalOnly'     { 'Register' }
        default         { 'Blocked' }
    }
}
