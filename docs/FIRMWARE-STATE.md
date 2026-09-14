# DeviceLink firmware state

WindowsDeviceLink can inspect and clear the local firmware state used by Windows Autopilot Device Preparation Device Association.

This functionality is separate from the server-side `tenantAssociatedDevices` record in Microsoft Intune.

## UEFI namespace

Validated namespace:

```text
{B3DE75DA-819C-4FD5-9F01-C3D49E8CBBD7}
```

Validated variables:

```text
DeviceLinkId
DeviceLinkJwtCompressed
DeviceLinkJwtLastWrite
DeviceLinkCreationTimeUtc
```

Do not log or publish the raw contents of `DeviceLinkJwtCompressed`.

## Read firmware state

```powershell
Get-WindowsDeviceLinkFirmwareState
```

The cmdlet returns safe metadata only:

- environment (`Windows` or `WindowsPE`);
- variable name;
- presence;
- byte size;
- Win32 error when a variable is not readable/present.

Example:

```powershell
Get-WindowsDeviceLinkFirmwareState |
    Format-Table Name,Present,Size,LastError
```

A missing variable normally returns `Present = False` with Win32 error `203` (`ERROR_ENVVAR_NOT_FOUND`).

## Clear local firmware state

```powershell
Clear-WindowsDeviceLinkFirmwareState
```

This removes only local DeviceLink firmware state. It does not remove:

- the Intune Device Association record;
- the Intune managed-device record;
- the Entra ID device;
- TPM ownership;
- classic Autopilot V1 registration.

For controlled automation or WinPE:

```powershell
Clear-WindowsDeviceLinkFirmwareState -Confirm:$false -PassThru
```

The cmdlet verifies immediately afterward that none of the known DeviceLink variables remain.

> [!IMPORTANT]
> Immediate successful verification does not mean every DeviceLink variable will remain absent after a later Windows boot. Testing confirmed that Windows can recreate the local DeviceLink identity variables after reboot. See **Identity regeneration after reboot** below.

## Server-side removal is separate

Use:

```powershell
Remove-WindowsDeviceLinkAssociation `
    -SerialNumber '<serial-number>' `
    -Method DeviceCode `
    -TenantId '<tenant-id>'
```

for the server-side Intune/Graph record.

For a fully associated device, a complete decommissioning or tenant-move workflow can require both:

1. remove the server-side Device Association record;
2. clear the local DeviceLink firmware state.

Keep these operations separate unless the caller intentionally combines them.

## Validated lifecycle observations

Testing on physical AMD64 hardware confirmed the following behavior.

### Clean device

All four variables were absent.

### DeviceLink generation

After generating DeviceLink information, the following local variables existed:

```text
DeviceLinkId
DeviceLinkCreationTimeUtc
```

The JWT variables were not present yet.

### Preassociation

Creating the server-side preassociation did not add the JWT variables. Local state remained the DeviceLink identity state above.

### Fully associated device

A fully associated device contained all four variables:

```text
DeviceLinkId
DeviceLinkJwtCompressed
DeviceLinkJwtLastWrite
DeviceLinkCreationTimeUtc
```

### Server-side deletion

Deleting the `tenantAssociatedDevices` record did not remove the local firmware variables.

### Local cleanup

Removing all four variables succeeded in both full Windows and AMD64 WinPE and was verified immediately afterward. All four returned `Present = False` and Win32 error `203`.

### Identity regeneration after reboot

A controlled test established an important distinction between local DeviceLink identity and server-side Device Association state:

1. the server-side Device Association record was removed;
2. Intune showed no Device Association record for the device;
3. all four local DeviceLink UEFI variables were cleared and immediately verified absent;
4. the device was rebooted into full Windows;
5. no `Get-WindowsDeviceLink` command was run after reboot;
6. `Get-WindowsDeviceLinkFirmwareState` then showed:

```text
DeviceLinkId                Present
DeviceLinkCreationTimeUtc   Present
DeviceLinkJwtCompressed     Absent
DeviceLinkJwtLastWrite      Absent
```

The same base-state pattern had already been observed after explicit DeviceLink generation.

This demonstrates on the tested device that Windows can recreate `DeviceLinkId` and `DeviceLinkCreationTimeUtc` during/after a normal Windows boot even when no Device Association record exists in Intune. Their presence alone must therefore **not** be interpreted as proof that the device is associated with a tenant.

In the validated fully associated state, the two JWT-related variables were also present. Their exact semantics should not be inferred beyond the observed lifecycle behavior without additional Microsoft documentation or testing.

The firmware cmdlet intentionally does not expose raw values, so this test did not determine whether the regenerated `DeviceLinkId` is byte-for-byte identical to the value that existed before cleanup or a newly generated identity.

## Windows PE

The same native firmware read/write mechanism was validated successfully in AMD64 Windows PE.

Validated in WinPE:

- firmware state read;
- DeviceLink generation;
- Graph preassociation;
- Graph Device Association removal;
- firmware state removal;
- verification that all known firmware variables were absent afterward.

Windows PE therefore provides a useful control point for reinstallation and tenant-to-tenant migration workflows. Be aware that a subsequent full Windows boot can recreate the base DeviceLink identity variables as described above.

## Privilege requirement

Firmware access requires `SeSystemEnvironmentPrivilege`. WindowsDeviceLink enables this privilege in the current process when the firmware cmdlets run. Use an elevated Windows PowerShell session.

## Safety

- Do not clear unrelated UEFI variables.
- Do not expose the raw JWT-compressed value in logs.
- Use `-WhatIf` / confirmation behavior for destructive operations where appropriate.
- Treat server-side removal and local firmware cleanup as separate lifecycle operations.
- Do not treat `DeviceLinkId` or `DeviceLinkCreationTimeUtc` alone as evidence of an active tenant association.
- Expect the base DeviceLink identity variables to be recreated by Windows on the validated hardware after reboot.
