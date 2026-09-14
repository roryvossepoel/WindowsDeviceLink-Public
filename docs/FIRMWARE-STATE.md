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

The cmdlet verifies afterward that none of the known DeviceLink variables remain.

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

Testing on physical AMD64 hardware confirmed:

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

Removing all four variables succeeded and was verified immediately afterward.

## Windows PE

The same native firmware read/write mechanism was validated successfully in AMD64 Windows PE.

Validated in WinPE:

- firmware state read;
- DeviceLink generation;
- Graph preassociation;
- Graph Device Association removal;
- firmware state removal;
- verification that all known firmware variables were absent afterward.

Windows PE therefore provides a useful control point for reinstallation and tenant-to-tenant migration workflows.

## Privilege requirement

Firmware access requires `SeSystemEnvironmentPrivilege`. WindowsDeviceLink enables this privilege in the current process when the firmware cmdlets run. Use an elevated Windows PowerShell session.

## Safety

- Do not clear unrelated UEFI variables.
- Do not expose the raw JWT-compressed value in logs.
- Use `-WhatIf` / confirmation behavior for destructive operations where appropriate.
- Treat server-side removal and local firmware cleanup as separate lifecycle operations.
