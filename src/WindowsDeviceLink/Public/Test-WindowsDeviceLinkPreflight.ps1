function Test-WindowsDeviceLinkPreflight {
    <#
    .SYNOPSIS
    Performs a read-only DeviceLink prerequisites assessment.

    .DESCRIPTION
    Combines runtime support, firmware readability, TPM and Secure Boot observations into a
    machine-readable preflight result. Unknown observations are preserved as warnings rather than
    treated as success. No DeviceLink, firmware or cloud state is changed.
    #>
    [CmdletBinding()]
    param(
        [ValidateNotNullOrEmpty()][string]$WindowsManagementServicePath
    )

    $checks = New-Object System.Collections.Generic.List[object]
    function Add-Check {
        param([string]$Name,[string]$State,[string]$Summary,[object]$ObservedValue)
        $checks.Add([pscustomobject]@{Name=$Name;State=$State;Summary=$Summary;ObservedValue=$ObservedValue}) | Out-Null
    }

    $supportParams = @{}
    if ($PSBoundParameters.ContainsKey('WindowsManagementServicePath')) { $supportParams.WindowsManagementServicePath=$WindowsManagementServicePath }
    $support = Test-WindowsDeviceLinkSupport @supportParams
    Add-Check -Name 'Runtime' -State $(if($support.Supported){'Ready'}else{'Blocked'}) -Summary $(if($support.Supported){'DeviceLink runtime/native probe is available.'}else{$support.Reason}) -ObservedValue $support.ActivationMode

    $isAdmin = $false
    try {
        $identity=[Security.Principal.WindowsIdentity]::GetCurrent()
        $principal=New-Object Security.Principal.WindowsPrincipal($identity)
        $isAdmin=$principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch {}
    Add-Check -Name 'Elevation' -State $(if($isAdmin){'Ready'}else{'Warning'}) -Summary $(if($isAdmin){'Current process is elevated.'}else{'Current process does not appear elevated; firmware operations may fail.'}) -ObservedValue $isAdmin

    try {
        $fw=@(Get-WindowsDeviceLinkFirmwareState)
        $readErrors=@($fw|Where-Object{$_.LastError -and $_.LastError -notin @(2,203)})
        if($readErrors.Count -eq 0){Add-Check -Name 'FirmwareAccess' -State 'Ready' -Summary 'Known DeviceLink firmware variables were queried successfully.' -ObservedValue (($fw|Where-Object Present).Count.ToString()+'/4')}
        else{Add-Check -Name 'FirmwareAccess' -State 'Blocked' -Summary 'One or more firmware variables could not be queried reliably.' -ObservedValue (($readErrors|Select-Object -ExpandProperty LastError -Unique)-join ',')}
    } catch {
        Add-Check -Name 'FirmwareAccess' -State 'Blocked' -Summary 'DeviceLink firmware state could not be read.' -ObservedValue $null
    }

    try {
        $tpm=Get-CimInstance -Namespace 'root\CIMV2\Security\MicrosoftTpm' -ClassName Win32_Tpm -ErrorAction Stop | Select-Object -First 1
        if($tpm){
            $spec=[string]$tpm.SpecVersion
            $isTpm2=($spec -match '(^|,)2\.0(,|$)' -or $spec -match '^2\.0')
            Add-Check -Name 'TPM' -State $(if($isTpm2){'Ready'}else{'Warning'}) -Summary $(if($isTpm2){'TPM 2.0 is reported.'}else{'A TPM is present, but TPM 2.0 could not be confirmed.'}) -ObservedValue $spec
        } else { Add-Check -Name 'TPM' -State 'Warning' -Summary 'TPM presence could not be confirmed.' -ObservedValue $null }
    } catch { Add-Check -Name 'TPM' -State 'Warning' -Summary 'TPM state is unavailable in the current environment.' -ObservedValue $null }

    try {
        $secureBoot=Confirm-SecureBootUEFI -ErrorAction Stop
        Add-Check -Name 'SecureBoot' -State $(if($secureBoot){'Ready'}else{'Warning'}) -Summary $(if($secureBoot){'Secure Boot is enabled.'}else{'Secure Boot is disabled.'}) -ObservedValue ([bool]$secureBoot)
    } catch { Add-Check -Name 'SecureBoot' -State 'Warning' -Summary 'Secure Boot state is unavailable in the current environment.' -ObservedValue $null }

    try {
        $dlParams=@{TimeoutSeconds=30}
        if($PSBoundParameters.ContainsKey('WindowsManagementServicePath')){$dlParams.WindowsManagementServicePath=$WindowsManagementServicePath}
        $identity=Get-WindowsDeviceLink @dlParams
        Add-Check -Name 'LocalIdentity' -State 'Ready' -Summary 'A local DeviceLink identity can be obtained.' -ObservedValue ([string]$identity.LinkId)
    } catch { Add-Check -Name 'LocalIdentity' -State 'Blocked' -Summary 'A local DeviceLink identity could not be obtained.' -ObservedValue $null }

    $resolved = Resolve-WindowsDeviceLinkPreflightState -Checks @($checks)

    [pscustomobject]@{
        PSTypeName='Windows.DeviceLink.Preflight'
        State=$resolved.State
        Ready=$resolved.Ready
        BlockingCount=$resolved.BlockingCount
        WarningCount=$resolved.WarningCount
        Environment=$support.Environment
        Architecture=$support.Architecture
        ActivationMode=$support.ActivationMode
        DllVersion=$support.DllVersion
        Checks=@($checks)
    }
}
