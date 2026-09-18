function Test-WindowsDeviceLinkDiscovery {
    <#
    .SYNOPSIS
    Tests device-side DeviceLink preassociation discovery.

    .DESCRIPTION
    Submits the current TPM-backed DeviceLink identity to the native discovery flow and
    returns the resolved discovery URL, tenant ID, native discovery result and configure-result
    observations.

    On full Windows, the registered DeviceLinkManager WinRT runtime is used. In Windows PE,
    a compatible administrator-supplied Windows.Management.Service.dll can be supplied through
    -WindowsManagementServicePath and is activated directly.

    This operation performs network discovery but does not invoke ConfigureDeviceLinkAsync and
    does not write DeviceLink association state to firmware.
    #>
    [CmdletBinding()]
    param(
        [ValidateNotNullOrEmpty()]
        [string]$WindowsManagementServicePath,

        [ValidateRange(5,600)]
        [int]$TimeoutSeconds = 120
    )

    if ($PSBoundParameters.ContainsKey('WindowsManagementServicePath')) {
        $support = Test-WindowsDeviceLinkSupport -WindowsManagementServicePath $WindowsManagementServicePath
    }
    else {
        $support = Test-WindowsDeviceLinkSupport
    }

    if (-not $support.Supported) {
        throw "DeviceLink isn't supported: $($support.Reason)"
    }

    if ($support.Environment -eq 'WindowsPE' -and $support.ActivationMode -ne 'DirectDll') {
        throw 'Windows PE discovery requires a compatible administrator-supplied Windows.Management.Service.dll.'
    }

    if ($support.Environment -eq 'WindowsPE' -and -not $PSBoundParameters.ContainsKey('WindowsManagementServicePath')) {
        throw 'Windows PE discovery requires -WindowsManagementServicePath because WindowsDeviceLink does not redistribute the Microsoft runtime.'
    }

    if ($PSBoundParameters.ContainsKey('WindowsManagementServicePath')) {
        $identity = Get-WindowsDeviceLink -WindowsManagementServicePath $support.DllPath -TimeoutSeconds $TimeoutSeconds
    }
    else {
        $identity = Get-WindowsDeviceLink -TimeoutSeconds $TimeoutSeconds
    }

    if ($support.ActivationMode -eq 'RegisteredWinRT') {
        $result = [WinPEDeviceLink.Native.DeviceLinkManagerClient]::DiscoverRegistered($identity.DeviceLink,$TimeoutSeconds)
    }
    elseif ($support.ActivationMode -eq 'DirectDll') {
        $directDiscover = [WinPEDeviceLink.Native.DeviceLinkManagerClient].GetMethods([Reflection.BindingFlags]'Public,Static') |
            Where-Object { $_.Name -eq 'Discover' } |
            Select-Object -First 1

        if (-not $directDiscover) {
            throw 'The loaded DeviceLinkManagerClient does not include direct-DLL discovery. PowerShell cannot unload Add-Type classes; after updating this research branch, close this PowerShell process, start a new one, and import the module again.'
        }

        $result = [WinPEDeviceLink.Native.DeviceLinkManagerClient]::Discover($support.DllPath,$identity.DeviceLink,$TimeoutSeconds)
    }
    else {
        throw "Unsupported DeviceLink discovery activation mode '$($support.ActivationMode)'."
    }

    if ($null -eq $result) {
        throw 'DeviceLink discovery returned no native result.'
    }

    [pscustomobject]@{
        PSTypeName='Windows.DeviceLink.Discovery'
        Environment=$support.Environment
        DllSource=$support.DllSource
        ActivationMode=$support.ActivationMode
        DllPath=$support.DllPath
        DllVersion=$support.DllVersion
        LinkId=$identity.LinkId
        DiscoveryResult=$result.DiscoveryResult
        DiscoveryUsable=($result.DiscoveryResult -in @(1,2))
        DiscoveryUrl=$result.DiscoveryUrl
        TenantId=$result.TenantId
        ConfigureResultBefore=$result.ConfigureResultBefore
        ConfigureResultAfter=$result.ConfigureResultAfter
        AsyncStatus=$result.AsyncStatus
        ConfigureInvoked=$false
        StateChanging=$false
    }
}
