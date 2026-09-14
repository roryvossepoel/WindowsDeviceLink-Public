function Get-WindowsDeviceLinkFirmwareState {
    <#
    .SYNOPSIS
    Reads local Windows DeviceLink firmware state.

    .DESCRIPTION
    Reads the Windows Autopilot Device Preparation Device Association UEFI variables
    from the local device without returning their raw contents.

    The cmdlet works in full Windows and AMD64 Windows PE when firmware access is
    available. It enables SeSystemEnvironmentPrivilege in the current process and
    returns presence, size, and Win32 error information for each known variable.

    The raw DeviceLinkJwtCompressed value is intentionally never returned because it
    contains sensitive DeviceLink association data.

    .OUTPUTS
    PSCustomObject. One object is returned per known DeviceLink firmware variable.

    .EXAMPLE
    Get-WindowsDeviceLinkFirmwareState

    Reads the four known DeviceLink UEFI variables and returns only safe metadata.

    .EXAMPLE
    Get-WindowsDeviceLinkFirmwareState | Format-Table Name,Present,Size,LastError

    Displays a compact DeviceLink firmware-state overview.

    .NOTES
    Current validated UEFI namespace:
    {B3DE75DA-819C-4FD5-9F01-C3D49E8CBBD7}

    Current validated variables:
    DeviceLinkId
    DeviceLinkJwtCompressed
    DeviceLinkJwtLastWrite
    DeviceLinkCreationTimeUtc
    #>
    [CmdletBinding()]
    param()

    Initialize-WindowsDeviceLinkFirmware

    $namespace = '{B3DE75DA-819C-4FD5-9F01-C3D49E8CBBD7}'
    $variables = @(
        'DeviceLinkId',
        'DeviceLinkJwtCompressed',
        'DeviceLinkJwtLastWrite',
        'DeviceLinkCreationTimeUtc'
    )

    $environment = if (Test-Path -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Control\MiniNT') {
        'WindowsPE'
    }
    else {
        'Windows'
    }

    foreach ($name in $variables) {
        $buffer = New-Object byte[] 65536
        $size = [WindowsDeviceLink.FirmwareNative]::GetFirmwareEnvironmentVariable(
            $name,
            $namespace,
            $buffer,
            $buffer.Length
        )

        $lastError = if ($size -eq 0) {
            [Runtime.InteropServices.Marshal]::GetLastWin32Error()
        }
        else {
            $null
        }

        [pscustomobject]@{
            PSTypeName  = 'Windows.DeviceLink.FirmwareState'
            Environment = $environment
            Namespace   = $namespace
            Name        = $name
            Present     = ($size -gt 0)
            Size        = [int]$size
            LastError   = $lastError
        }
    }
}
