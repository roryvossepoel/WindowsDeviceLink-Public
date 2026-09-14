function Reset-WindowsDeviceLinkFirmwareState {
    <#
    .SYNOPSIS
    Resets the local Windows DeviceLink firmware identity and association state.

    .DESCRIPTION
    Removes the known Windows Autopilot Device Preparation Device Association UEFI
    variables from the local device. The cmdlet works in full Windows and AMD64
    Windows PE when firmware write access is available.

    The reset is immediate: all known DeviceLink firmware variables are removed and
    the cmdlet verifies that they are absent. On a later Windows boot, Windows can
    generate a new DeviceLinkId and DeviceLinkCreationTimeUtc. Testing confirmed that
    this is a new local DeviceLink identity, not restoration of the removed identity.

    This cmdlet changes local firmware state only. It does not delete the server-side
    tenantAssociatedDevices record in Microsoft Intune. Use
    Remove-WindowsDeviceLinkAssociation separately for server-side cleanup.

    .PARAMETER PassThru
    Returns the post-reset firmware state objects after successful verification.

    .EXAMPLE
    Reset-WindowsDeviceLinkFirmwareState

    Prompts for confirmation, removes all known DeviceLink firmware variables, and
    verifies that they are absent.

    .EXAMPLE
    Reset-WindowsDeviceLinkFirmwareState -Confirm:$false -PassThru

    Resets local DeviceLink firmware state without an interactive confirmation prompt
    and returns the verified post-reset state. Use this form only in a controlled
    deployment or WinPE workflow.

    .EXAMPLE
    Reset-WindowsDeviceLinkFirmwareState -WhatIf

    Shows the reset operation without changing firmware state.

    .NOTES
    This operation resets local DeviceLink identity/association firmware state. It
    does not clear TPM ownership, delete Entra ID devices, remove Intune managed-device
    records, or remove the server-side Device Association record.

    Windows may create a new DeviceLinkId and DeviceLinkCreationTimeUtc after reboot.
    Their later presence does not mean that the old identity or tenant association was
    restored.

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

    if (-not $PSCmdlet.ShouldProcess($target, 'Reset DeviceLink firmware state')) {
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
        throw "DeviceLink firmware reset verification failed. Remaining variables: $($remaining.Name -join ', ')."
    }

    Write-Information -InformationAction Continue -MessageData 'DeviceLink firmware state reset and verified successfully.'

    if ($PassThru) {
        $after
    }
}
