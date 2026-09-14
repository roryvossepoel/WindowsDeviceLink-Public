# Next step: local Device Association lifecycle and WinPE

This document captures the Device Association lifecycle investigation after `0.4.2-preview1`.

## Goal

Extend WindowsDeviceLink beyond server-side Device Association removal so that an already **associated** device can be safely prepared for decommissioning or tenant-to-tenant migration.

The remaining question is whether the local Device Association / tenant-affinity state stored in UEFI can be inspected and cleared from AMD64 Windows PE in the same way that is now validated in full Windows.

## Why this matters

Removing the `tenantAssociatedDevices` record from Intune does not clear the local UEFI Device Association state.

A complete lifecycle workflow therefore needs both:

1. local UEFI state handling on the device;
2. removal of the server-side `tenantAssociatedDevices` record.

This is especially relevant for tenant-to-tenant moves and WinPE-based deployment workflows.

## Current UEFI namespace and variables

Validated namespace:

```text
{B3DE75DA-819C-4FD5-9F01-C3D49E8CBBD7}
```

Validated current variables:

```text
DeviceLinkId
DeviceLinkJwtCompressed
DeviceLinkJwtLastWrite
DeviceLinkCreationTimeUtc
```

Do not log or publish the raw value of `DeviceLinkJwtCompressed`.

## Full Windows findings

The following behavior has been validated on physical hardware with current Windows 11 25H2 support for Device Association.

### Clean baseline

Before DeviceLink generation / pre-association, all four variables were absent.

### Pre-associated state

After DeviceLink generation and successful Graph pre-association:

- `DeviceLinkId` was present;
- the additional association variables were not yet present.

### Associated state

After the device reached `Association state = Associated` in Intune, all four current variables were present:

```text
DeviceLinkId                Present
DeviceLinkJwtCompressed     Present
DeviceLinkJwtLastWrite      Present
DeviceLinkCreationTimeUtc   Present
```

### Server-side removal does not clear UEFI state

The Device Association record was removed successfully with:

```powershell
Remove-WindowsDeviceLinkAssociation
```

and the device was removed from Intune, but the local DeviceLink UEFI state remained present.

### Local removal is validated in full Windows

Deleting all four variables with the Windows firmware API succeeded. A direct readback immediately afterward returned `ERROR_ENVVAR_NOT_FOUND` (`203`) for each variable.

Removing only `DeviceLinkId` is not sufficient; the complete set of current Device Association variables must be handled together.

## Native implementation direction

The external `UEFI` / `UEFIv2` PowerShell modules are not required for this project.

Direct Windows APIs have been validated successfully:

```text
GetFirmwareEnvironmentVariable
SetFirmwareEnvironmentVariable
```

Access requires `SeSystemEnvironmentPrivilege`. The privilege exists in an elevated Windows PowerShell token but may be disabled and must be enabled for the current process before firmware access.

A reusable read-only probe is available at:

```text
tests/DeviceLink-Firmware-State.ps1
```

The script:

- enables `SeSystemEnvironmentPrivilege` in the current process;
- reads only the four known DeviceLink variables;
- returns presence, size, environment and Win32 error metadata;
- never returns the raw firmware values;
- detects Windows versus Windows PE.

## Next test: AMD64 WinPE

The next session should start read-only.

Boot an **already associated** physical device into AMD64 WinPE and run:

```powershell
.\tests\DeviceLink-Firmware-State.ps1
```

Validate:

1. `SeSystemEnvironmentPrivilege` can be enabled in WinPE;
2. the four DeviceLink UEFI variables are readable;
3. the same namespace and variable names are visible;
4. `GetFirmwareEnvironmentVariable` behaves consistently with full Windows;
5. no extra PowerShell or external UEFI module dependency is required.

Do not clear any UEFI state during the first WinPE test.

## After WinPE read validation

If read-only access succeeds, perform a controlled WinPE clear test on a disposable / controlled associated device:

1. capture firmware-state metadata before removal;
2. remove all four known DeviceLink UEFI variables;
3. immediately verify that all four are absent;
4. reboot and verify they remain absent;
5. verify the old association does not regenerate unexpectedly;
6. remove any remaining server-side `tenantAssociatedDevices` record as appropriate.

WinPE write support must be treated as separately validated from full Windows.

## Server-side cleanup

The already validated command is:

```powershell
Remove-WindowsDeviceLinkAssociation \
    -SerialNumber '<serial>' \
    -Method <method> \
    -TenantId '<tenant-id>'
```

or the advanced `-AssociationId` route.

Validated Graph delete operation:

```http
DELETE /deviceManagement/tenantAssociatedDevices/{associationId}
```

This is the Device Association API and is not the classic Autopilot V1 deletion API.

## Target tenant-to-tenant workflow

If local UEFI removal is proven safe in WinPE, the target workflow is:

```text
Boot WinPE
-> inspect current Device Association UEFI state
-> clear old Device Association UEFI variables
-> remove old tenantAssociatedDevices record
-> generate/read DeviceLink identity as required
-> create pre-association in the target tenant
-> install Windows
-> continue OOBE / Device Preparation
```

## Candidate module design

Do not publish these commands until WinPE behavior is validated.

Candidate read-only command:

```powershell
Get-WindowsDeviceLinkFirmwareState
```

Candidate local-clear command:

```powershell
Clear-WindowsDeviceLinkFirmwareState
```

Existing server-side command:

```powershell
Remove-WindowsDeviceLinkAssociation
```

Keeping local firmware modification and Graph deletion separate initially remains the safer design.

## Safety requirements

- Read-only WinPE validation comes first.
- Never log or publish raw `DeviceLinkJwtCompressed` content.
- Only operate in the validated DeviceLink UEFI namespace.
- Only touch the four known Device Association variables.
- Do not assume reset/reinstall removes tenant affinity.
- Do not use classic Autopilot V1 delete APIs for Device Association records.
- Be explicit about whether the device is `preassociated` or fully `associated`.
- WinPE write support must be validated independently from full Windows.
