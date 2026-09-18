function Test-WindowsDeviceLinkManagerRuntime {
    <#
    .SYNOPSIS
    Performs a read-only prerequisite probe of DeviceLinkManager using an administrator-supplied runtime.

    .DESCRIPTION
    Intended for Windows PE research. The probe validates the direct-DLL DeviceLinkManager
    activation path and reads the current configure/discovery request information without
    invoking RequestDiscoveryUrlAsync or ConfigureDeviceLinkAsync.

    This command does not create/remove a tenant association and does not write DeviceLink
    association state to firmware.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$WindowsManagementServicePath
    )

    $support = Test-WindowsDeviceLinkSupport -WindowsManagementServicePath $WindowsManagementServicePath
    if (-not $support.Supported) {
        throw "DeviceLink isn't supported: $($support.Reason)"
    }

    if ($support.Environment -ne 'WindowsPE' -or $support.ActivationMode -ne 'DirectDll') {
        throw 'This research probe currently targets Windows PE with an explicitly supplied Windows.Management.Service.dll.'
    }

    $result = [WinPEDeviceLink.Native.DeviceLinkManagerClient]::Probe($support.DllPath)

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
