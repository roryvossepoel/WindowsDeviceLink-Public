function Test-WindowsDeviceLinkManagerRuntime {
    <#
    .SYNOPSIS
    Performs a read-only prerequisite probe of DeviceLinkManager.

    .DESCRIPTION
    On full Windows, the registered DeviceLinkManager WinRT runtime is used.
    In Windows PE, an administrator-supplied Windows.Management.Service.dll is required
    and activated directly.

    The probe reads current configure/discovery request information without invoking
    RequestDiscoveryUrlAsync or ConfigureDeviceLinkAsync.

    This command does not create/remove a tenant association and does not write DeviceLink
    association state to firmware.
    #>
    [CmdletBinding()]
    param(
        [ValidateNotNullOrEmpty()]
        [string]$WindowsManagementServicePath
    )

    $isWinPE = Test-Path -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Control\MiniNT'

    if ($isWinPE) {
        if (-not $PSBoundParameters.ContainsKey('WindowsManagementServicePath')) {
            throw 'Windows PE requires -WindowsManagementServicePath because WindowsDeviceLink does not redistribute the Microsoft runtime.'
        }

        $support = Test-WindowsDeviceLinkSupport -WindowsManagementServicePath $WindowsManagementServicePath
        if (-not $support.Supported) {
            throw "DeviceLink isn't supported: $($support.Reason)"
        }
        if ($support.ActivationMode -ne 'DirectDll') {
            throw "Unexpected Windows PE activation mode '$($support.ActivationMode)'."
        }

        $result = [WinPEDeviceLink.Native.DeviceLinkManagerClient]::Probe($support.DllPath)
    }
    else {
        if ($PSBoundParameters.ContainsKey('WindowsManagementServicePath')) {
            throw 'Do not supply -WindowsManagementServicePath on full Windows. The registered WinRT runtime is used as the comparison baseline.'
        }

        $support = Test-WindowsDeviceLinkSupport
        if (-not $support.Supported) {
            throw "DeviceLink isn't supported: $($support.Reason)"
        }
        if ($support.ActivationMode -ne 'RegisteredWinRT') {
            throw "Unexpected full-Windows activation mode '$($support.ActivationMode)'."
        }

        $result = [WinPEDeviceLink.Native.DeviceLinkManagerClient]::ProbeRegistered()
    }

    [pscustomobject]@{
        PSTypeName             = 'Windows.DeviceLink.ManagerRuntimeProbe'
        Environment            = $support.Environment
        DllSource              = $support.DllSource
        ActivationMode         = $support.ActivationMode
        DllPath                = $support.DllPath
        DllVersion             = $support.DllVersion
        Success                = [bool]$result.Success
        FailedPhase            = $result.FailedPhase
        HResult                = if ($result.HResultHex) { $result.HResultHex } else { $null }
        Message                = $result.Message
        ConfigureResult        = if ($result.ConfigureResult -eq [int]::MinValue) { $null } else { $result.ConfigureResult }
        DiscoveryInfoAvailable = [bool]$result.DiscoveryInfoAvailable
        DiscoveryResult        = if ($result.DiscoveryResult -eq [int]::MinValue) { $null } else { $result.DiscoveryResult }
        DiscoveryUrl           = $result.DiscoveryUrl
        TenantId               = $result.TenantId
        RequestInvoked         = $false
        ConfigureInvoked       = $false
        StateChanging          = $false
    }
}
