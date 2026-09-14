function Clear-WindowsDeviceLinkFirmwareState {
    <#
    .SYNOPSIS
    Clears local Windows DeviceLink firmware state.

    .DESCRIPTION
    Removes the known Windows Autopilot Device Preparation Device Association UEFI
    variables from the local device. The cmdlet works in full Windows and AMD64
    Windows PE when firmware write access is available.

    This cmdlet changes local firmware state only. It does not delete the server-side
    tenantAssociatedDevices record in Microsoft Intune. Use
    Remove-WindowsDeviceLinkAssociation separately for server-side cleanup.

    The cmdlet verifies the local state after removal and throws if any known variable
    remains present.

    .PARAMETER PassThru
    Returns the post-removal firmware state objects after successful verification.

    .EXAMPLE
    Clear-WindowsDeviceLinkFirmwareState

    Prompts for confirmation and removes all known DeviceLink firmware variables.

    .EXAMPLE
    Clear-WindowsDeviceLinkFirmwareState -Confirm:$false -PassThru

    Removes the local DeviceLink firmware state without an interactive confirmation
    prompt and returns the verified post-removal state. Use this form only in a
    controlled deployment or WinPE workflow.

    .NOTES
    This operation is destructive to the local Device Association state. It does not
    clear TPM ownership, delete Entra ID devices, or remove Intune managed-device
    records.

    Current validated UEFI namespace:
    {B3DE75DA-819C-4FD5-9F01-C3D49E8CBBD7}

    Current validated variables:
    DeviceLinkId
    DeviceLinkJwtCompressed
    DeviceLinkJwtLastWrite
    DeviceLinkCreationTimeUtc
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [switch]$PassThru
    )

    Initialize-WindowsDeviceLinkFirmware

    $before = @(Get-WindowsDeviceLinkFirmwareState)
    $present = @($before | Where-Object { $_.Present })

    if ($present.Count -eq 0) {
        Write-Information -InformationAction Continue -MessageData 'No DeviceLink firmware state is present.'
        if ($PassThru) { $before }
        return
    }

    $target = if (Test-Path -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Control\MiniNT') {
        'local DeviceLink UEFI state (Windows PE)'
    }
    else {
        'local DeviceLink UEFI state (Windows)'
    }

    if (-not $PSCmdlet.ShouldProcess($target, 'Clear DeviceLink firmware state')) {
        return
    }

    foreach ($item in $before) {
        if (-not $item.Present) { continue }

        $deleted = [WindowsDeviceLink.FirmwareNative]::SetFirmwareEnvironmentVariable(
            $item.Name,
            $item.Namespace,
            $null,
            0
        )

        if (-not $deleted) {
            $lastError = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
            throw "Failed to remove DeviceLink firmware variable '$($item.Name)' (Win32 error $lastError)."
        }

        Write-Information -InformationAction Continue -MessageData "Removed DeviceLink firmware variable: $($item.Name)"
    }

    $after = @(Get-WindowsDeviceLinkFirmwareState)
    $remaining = @($after | Where-Object { $_.Present })

    if ($remaining.Count -gt 0) {
        throw "DeviceLink firmware cleanup verification failed. Remaining variables: $($remaining.Name -join ', ')."
    }

    Write-Information -InformationAction Continue -MessageData 'DeviceLink firmware state cleared and verified successfully.'

    if ($PassThru) {
        $after
    }
}
