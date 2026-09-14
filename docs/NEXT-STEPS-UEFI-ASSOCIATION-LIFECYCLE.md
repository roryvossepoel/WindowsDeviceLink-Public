# Device Association lifecycle: validated findings and next release

This document records the firmware-lifecycle investigation completed after `0.4.2-preview1` and the remaining work before `0.4.3-preview1` is published.

## Goal

Support safe Device Association decommissioning and tenant-to-tenant migration across full Windows and AMD64 Windows PE.

A complete lifecycle can require two separate operations:

1. server-side removal of the Intune `tenantAssociatedDevices` record;
2. local removal of DeviceLink firmware state.

These operations are intentionally kept separate in WindowsDeviceLink.

## Validated UEFI state

Namespace:

```text
{B3DE75DA-819C-4FD5-9F01-C3D49E8CBBD7}
```

Current validated variables:

```text
DeviceLinkId
DeviceLinkJwtCompressed
DeviceLinkJwtLastWrite
DeviceLinkCreationTimeUtc
```

Never log or publish raw `DeviceLinkJwtCompressed` content.

## Full Windows findings

Validated on physical Windows 11 hardware:

- clean baseline: all four variables absent;
- fully associated device: all four variables present;
- deleting the server-side Device Association record does not clear local firmware state;
- deleting only `DeviceLinkId` is insufficient on a fully associated device;
- deleting all four known variables succeeds;
- immediate readback confirms all four are absent with Win32 error `203` (`ERROR_ENVVAR_NOT_FOUND`).

## AMD64 WinPE findings

Validated on physical AMD64 WinPE:

1. DeviceLink runtime support succeeds using direct DLL activation;
2. direct firmware read works after enabling `SeSystemEnvironmentPrivilege`;
3. clean firmware state is readable;
4. `Get-WindowsDeviceLink` succeeds;
5. DeviceLink generation creates `DeviceLinkId` and `DeviceLinkCreationTimeUtc`;
6. Graph preassociation succeeds from WinPE;
7. preassociation does not add the JWT firmware variables;
8. server-side Device Association removal by serial number succeeds from WinPE;
9. local DeviceLink firmware deletion succeeds from WinPE;
10. post-delete readback confirms all four known variables are absent.

No external `UEFI` / `UEFIv2` PowerShell module is required.

## Native implementation

The validated native APIs are:

```text
GetFirmwareEnvironmentVariable
SetFirmwareEnvironmentVariable
```

Firmware access requires `SeSystemEnvironmentPrivilege`. The module enables the privilege in the current process.

Development cmdlets now exist:

```powershell
Get-WindowsDeviceLinkFirmwareState
Clear-WindowsDeviceLinkFirmwareState
```

The read command returns safe metadata only. The clear command uses confirmation semantics, removes only currently present known DeviceLink variables, and verifies the post-removal state.

See [`FIRMWARE-STATE.md`](FIRMWARE-STATE.md).

## Server-side cleanup

Validated command:

```powershell
Remove-WindowsDeviceLinkAssociation `
    -SerialNumber '<serial-number>' `
    -Method DeviceCode `
    -TenantId '<tenant-id>'
```

Validated Graph operation:

```http
DELETE /deviceManagement/tenantAssociatedDevices/{associationId}
```

This is Device Association, not classic Autopilot V1.

## Target tenant-to-tenant workflow

A future controlled workflow can use WinPE as the orchestration point:

```text
Boot WinPE
-> inspect local DeviceLink firmware state
-> authenticate to the source tenant
-> remove old tenantAssociatedDevices record
-> clear old local DeviceLink firmware state
-> generate a fresh/current DeviceLink identity
-> pre-associate with the target tenant
-> install Windows
-> continue OOBE / Device Preparation
```

Do not combine these steps into one high-level destructive command until the separate operations and error cases are sufficiently exercised.

## Remaining work before 0.4.3-preview1

1. Live-test `Get-WindowsDeviceLinkFirmwareState` itself on Windows 11.
2. Live-test `Get-WindowsDeviceLinkFirmwareState` itself in AMD64 WinPE.
3. Live-test `Clear-WindowsDeviceLinkFirmwareState` in a controlled scenario.
4. Validate `-WhatIf`, confirmation, no-state, and `-PassThru` behavior.
5. Review public cmdlet naming one final time.
6. Ensure every public cmdlet has useful comment-based help and examples.
7. Run the Gallery packaging safety check.
8. Run a final public-repository scan for customer IDs, serial numbers, secrets, webhook tokens, and test values.
9. Publish `0.4.3-preview1` only after those checks pass.

## Safety requirements

- Never return/log raw JWT firmware contents.
- Only operate in the validated DeviceLink UEFI namespace.
- Only touch known DeviceLink variables.
- Keep server-side Graph deletion and local firmware cleanup distinguishable.
- Do not use classic Autopilot V1 delete APIs for Device Association records.
- Treat customer-specific client IDs, tenant IDs, serial numbers, certificates, secrets, and webhook tokens as non-public test data.
