function Test-WindowsDeviceLinkDiscovery {
    <#
    .SYNOPSIS
    Tests device-side DeviceLink preassociation discovery.

    .DESCRIPTION
    Uses the registered Windows DeviceLinkManager runtime to submit the current TPM-backed
    DeviceLink identity to the native discovery flow and returns the resolved discovery URL,
    tenant ID, native discovery result and configure-result observations.

    This operation performs network discovery but does not invoke ConfigureDeviceLinkAsync and
    does not write DeviceLink association state to firmware.
    #>
    [CmdletBinding()]
    param(
        [ValidateRange(5,600)]
        [int]$TimeoutSeconds = 120
    )

    $support = Test-WindowsDeviceLinkSupport
    if (-not $support.Supported) {
        throw "DeviceLink isn't supported: $($support.Reason)"
    }
    if ($support.Environment -ne 'Windows' -or $support.ActivationMode -ne 'RegisteredWinRT') {
        throw 'DeviceLink discovery currently requires full Windows with the registered DeviceLink WinRT runtime.'
    }

    $identity = Get-WindowsDeviceLink -TimeoutSeconds $TimeoutSeconds
    $result = [WinPEDeviceLink.Native.DeviceLinkManagerClient]::DiscoverRegistered($identity.DeviceLink,$TimeoutSeconds)

    [pscustomobject]@{
        PSTypeName='Windows.DeviceLink.Discovery'
        Environment=$support.Environment
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
