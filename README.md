# WindowsDeviceLink

[![PowerShell Gallery Version](https://img.shields.io/powershellgallery/v/WindowsDeviceLink?include_prereleases&label=PowerShell%20Gallery)](https://www.powershellgallery.com/packages/WindowsDeviceLink)
[![PowerShell Gallery Downloads](https://img.shields.io/powershellgallery/dt/WindowsDeviceLink)](https://www.powershellgallery.com/packages/WindowsDeviceLink)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

PowerShell module for **Windows Autopilot Device Preparation Device Association** on physical Windows devices.

WindowsDeviceLink can generate the TPM-backed DeviceLink identity, export the official Windows `.devicelink.csv`, pre-associate directly through Microsoft Graph, remove Device Association records, inspect and reset local DeviceLink UEFI state, or send a richer DeviceLink payload to a webhook for centralized automation.

> [!IMPORTANT]
> This is preview / proof-of-concept software. The WinPE implementation uses an undocumented Windows Runtime interface and the online registration/removal flows use Microsoft Graph beta endpoints. These can change without notice.

## Install from PowerShell Gallery

The currently published Gallery preview is `0.4.3-preview1`.

```powershell
Install-Module WindowsDeviceLink -Repository PSGallery -AllowPrerelease
```

## What this module is for

WindowsDeviceLink focuses on:

1. obtaining the DeviceLink identity from a physical device;
2. optionally exporting the official Windows-generated DeviceLink CSV;
3. pre-associating the device with Intune directly or through a webhook/automation layer;
4. removing server-side Device Association records;
5. inspecting local DeviceLink firmware state;
6. resetting the current local DeviceLink identity/association firmware state for reinstallation or tenant-move workflows.

This is **not** classic Windows Autopilot V1 hardware-hash registration.

## Requirements

- Physical AMD64 device.
- TPM 2.0 in a usable state.
- UEFI firmware.
- 64-bit Windows PowerShell 5.1.
- Windows 11 or compatible AMD64 Windows PE.
- For WinPE: a compatible user-supplied `Windows.Management.Service.dll`.
- For direct Graph pre-association/removal: Microsoft Graph permission `DeviceManagementServiceConfig.ReadWrite.All`.
- For firmware read/reset: elevated PowerShell with `SeSystemEnvironmentPrivilege` available. The module enables this privilege in the current process.

Always start on a new system with:

```powershell
Test-WindowsDeviceLinkSupport
```

## Important WinPE note

`Windows.Management.Service.dll` is **not included** in this repository, GitHub releases, or the PowerShell Gallery package. Windows 11 uses the system copy. WinPE users must provide a compatible Microsoft copy themselves.

Place it at:

```text
WindowsDeviceLink\Runtime\Windows.Management.Service.dll
```

or pass it explicitly with `-WindowsManagementServicePath`.

See [`src/WindowsDeviceLink/Runtime/README.md`](src/WindowsDeviceLink/Runtime/README.md).

## Generate DeviceLink information

```powershell
$deviceLink = Get-WindowsDeviceLink
$deviceLink | Format-List *
```

Treat DeviceLink payloads, serial numbers, SMBIOS UUIDs, Link IDs and firmware JWT data as sensitive operational data.

## Export the official DeviceLink CSV

```powershell
Get-WindowsDeviceLink -OutputDirectory 'C:\DeviceLink'
```

Windows generates the CSV through `ExportDeviceLinkInfoCsvAsync`; WindowsDeviceLink does not reconstruct the format.

## Pre-associate directly

`-Online` requires an explicit authentication method.

```powershell
Get-WindowsDeviceLink `
    -Online `
    -Method DeviceCode `
    -TenantId '<tenant-id>'
```

The default DeviceCode client ID is Microsoft's well-known public Graph PowerShell client ID. It is not a customer secret. See [`docs/ONLINE-METHODS.md`](docs/ONLINE-METHODS.md) for all supported methods and examples.

## Read local firmware state

```powershell
Get-WindowsDeviceLinkFirmwareState
```

The cmdlet checks the four validated DeviceLink UEFI variables and returns metadata only; it never returns raw firmware contents:

```text
DeviceLinkId
DeviceLinkJwtCompressed
DeviceLinkJwtLastWrite
DeviceLinkCreationTimeUtc
```

## Reset local firmware state

`0.4.3-preview1` adds:

```powershell
Reset-WindowsDeviceLinkFirmwareState
```

For controlled automation or WinPE:

```powershell
Reset-WindowsDeviceLinkFirmwareState -Confirm:$false -PassThru
```

For a dry run:

```powershell
Reset-WindowsDeviceLinkFirmwareState -WhatIf
```

The cmdlet removes all four known DeviceLink UEFI variables and immediately verifies that they are absent.

> [!IMPORTANT]
> Reset does **not** mean that DeviceLink variables remain permanently absent. End-to-end testing confirmed that after reset and reboot Windows can generate a **new** `DeviceLinkId` and `DeviceLinkCreationTimeUtc`. SHA-256 fingerprints before and after reset differed, the creation time changed, and the new identity could be pre-associated again. This is new identity generation, not restoration of the removed identity.

See [`docs/FIRMWARE-STATE.md`](docs/FIRMWARE-STATE.md) for the complete validated lifecycle.

## Remove a server-side Device Association

```powershell
Remove-WindowsDeviceLinkAssociation `
    -SerialNumber '<serial-number>' `
    -Method DeviceCode `
    -TenantId '<tenant-id>'
```

The verified operation targets:

```text
DELETE /deviceManagement/tenantAssociatedDevices/{associationId}
```

This does not reset local firmware state. See [`docs/REMOVE-ASSOCIATION.md`](docs/REMOVE-ASSOCIATION.md).

## Tenant-move / reinstallation lifecycle

Server-side removal and local reset are intentionally separate operations. A controlled workflow can be:

```text
old Device Association
        |
        v
Remove-WindowsDeviceLinkAssociation
        |
        v
Reset-WindowsDeviceLinkFirmwareState
        |
        v
all four known UEFI variables immediately absent
        |
        v
reboot
        |
        v
Windows creates a new base DeviceLink identity
        |
        v
Get-WindowsDeviceLink / new preassociation
```

This complete identity-reset and re-preassociation sequence has been validated on physical AMD64 hardware.

## Webhook

For centralized/unattended workflows:

```powershell
Get-WindowsDeviceLink `
    -Online `
    -Method Webhook `
    -WebhookUri '<webhook-url>' `
    -WebhookApiKey $env:WINDOWSDEVICELINK_WEBHOOK_API_KEY `
    -TenantId '<target-tenant-id>'
```

See [`docs/WEBHOOK-SCHEMA-v1.md`](docs/WEBHOOK-SCHEMA-v1.md) and [`runbooks/README.md`](runbooks/README.md).

## Public commands

| Command | Purpose |
|---|---|
| `Get-WindowsDeviceLink` | Generate, export and/or pre-associate a DeviceLink. |
| `Get-WindowsDeviceLinkFirmwareState` | Read safe metadata for local DeviceLink UEFI state. |
| `Reset-WindowsDeviceLinkFirmwareState` | Reset and immediately verify local DeviceLink UEFI identity/association state. |
| `Remove-WindowsDeviceLinkAssociation` | Remove a server-side Device Association record. |
| `Test-WindowsDeviceLinkSupport` | Validate runtime, architecture and DeviceLink activation. |
| `Export-WindowsDeviceLinkCsv` | Export an existing DeviceLink object using the Windows CSV API. |
| `Connect-WindowsDeviceLink` | Advanced Graph SDK authentication helper. |
| `Register-WindowsDeviceLink` | Advanced Graph SDK registration helper for an existing DeviceLink object. |

## Validation

The primary registration, removal and firmware lifecycle flows are validated on Windows 11 and AMD64 Windows PE. The firmware reset lifecycle includes immediate removal verification, reboot, proof that a different DeviceLink identity is generated, and successful re-preassociation of that new identity.

See [`TESTING.md`](TESTING.md) for the validation matrix.

## Scope

Currently published Gallery preview: `0.4.3-preview1`.

In scope: AMD64 Windows 11/WinPE, DeviceLink generation, official CSV export, Device Association preassociation/removal, local firmware inspection/reset, multiple authentication methods, webhook transport and the optional Azure Automation receiver.

Not currently in scope: ARM64, Device Preparation policy assignment, classic Autopilot V1 management, or production support guarantees.

## License

Project code is licensed under the MIT License. Microsoft binaries and Microsoft services remain subject to Microsoft's terms.
