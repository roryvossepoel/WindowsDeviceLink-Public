function Invoke-WindowsDeviceLinkGraphConnect {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateNotNull()][hashtable]$Parameters,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$MethodName,
        [AllowNull()][string[]]$SensitiveValue,
        [scriptblock]$RequestScript
    )

    try {
        if ($RequestScript) {
            return & $RequestScript $Parameters $MethodName
        }
        Connect-MgGraph @Parameters
    }
    catch {
        $detail = Protect-WindowsDeviceLinkSensitiveText -Text ([string]$_.Exception.Message) -SensitiveValue $SensitiveValue
        if ([string]::IsNullOrWhiteSpace($detail)) {
            throw "Microsoft Graph authentication failed using method '$MethodName'."
        }
        throw "Microsoft Graph authentication failed using method '$MethodName'. $detail"
    }
}
