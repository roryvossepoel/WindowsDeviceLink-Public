# WindowsDeviceLink

[![PowerShell Gallery Version](https://img.shields.io/powershellgallery/v/WindowsDeviceLink?include_prereleases&label=PowerShell%20Gallery)](https://www.powershellgallery.com/packages/WindowsDeviceLink)
[![PowerShell Gallery Downloads](https://img.shields.io/powershellgallery/dt/WindowsDeviceLink)](https://www.powershellgallery.com/packages/WindowsDeviceLink)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

PowerShell module for **Windows Autopilot Device Preparation Device Association** on physical Windows devices.

WindowsDeviceLink can generate the TPM-backed DeviceLink identity, export the official Windows `.devicelink.csv`, pre-associate directly through Microsoft Graph, remove Device Association records, inspect and clear local DeviceLink UEFI state, or send a richer DeviceLink payload to a webhook for centralized automation.

> [!IMPORTANT]
> This is preview / proof-of-concept software. The WinPE implementation uses an undocumented Windows Runtime interface and the online registration/removal flows use Microsoft Graph beta endpoints. These can change without notice.

## Install from PowerShell Gallery

The currently published Gallery preview is `0.4.2-preview1`.

```powershell
Install-Module WindowsDeviceLink -Repository PSGallery -AllowPrerelease
```

Then verify the installation:

```powershell
Import-Module WindowsDeviceLink
Get-Module WindowsDeviceLink | Select-Object Name, Version, Path
Test-WindowsDeviceLinkSupport
```

This repository currently contains `0.4.3-preview1` development changes. The firmware-state cmdlets are not part of the published `0.4.2-preview1` Gallery package yet.

## What this module is for

Windows Autopilot Device Preparation **Device Association** introduces a pre-association step for physical Windows devices. WindowsDeviceLink focuses on:

1. obtaining the DeviceLink identity from the physical device;
2. optionally exporting the official Windows-generated DeviceLink CSV;
3. pre-associating the device with Intune either directly or through a webhook/automation layer;
4. removing server-side Device Association records;
5. inspecting and clearing the local DeviceLink firmware state used by fully associated devices.

This is **not** classic Windows Autopilot V1 hardware-hash registration.

## What the module can do

- Generate DeviceLink information on AMD64 Windows 11.
- Generate DeviceLink information in AMD64 Windows PE.
- Export the official Windows-generated `.devicelink.csv`.
- Pre-associate directly in Intune using Microsoft Graph.
- Remove Device Association records by serial number or association ID.
- Read local DeviceLink UEFI state without exposing raw JWT association data.
- Clear local DeviceLink UEFI state and verify removal.
- Perform DeviceLink generation, Graph preassociation/removal, and firmware cleanup from AMD64 WinPE.
- Send a richer DeviceLink payload to a webhook for centralized automation.
- Include an optional tenant ID for multi-tenant routing on the receiving side.
- Include an optional API key in the `X-WindowsDeviceLink-Key` header.
- Use explicit online methods so each flow only accepts its relevant parameters.
- Detect whether the current Windows / WinPE environment can access the DeviceLink runtime.

See:

- [`docs/ONLINE-METHODS.md`](docs/ONLINE-METHODS.md) for authentication guidance;
- [`docs/REMOVE-ASSOCIATION.md`](docs/REMOVE-ASSOCIATION.md) for server-side removal;
- [`docs/FIRMWARE-STATE.md`](docs/FIRMWARE-STATE.md) for local UEFI state and cleanup;
- [`TESTING.md`](TESTING.md) for the validation matrix.

## Important WinPE note

### `Windows.Management.Service.dll` is NOT included

Windows 11 already contains `Windows.Management.Service.dll` and uses the registered Windows Runtime implementation.

Windows PE does not expose the same registered runtime. To use WindowsDeviceLink in WinPE, a compatible Microsoft `Windows.Management.Service.dll` must be supplied by the user.

The DLL is intentionally **not included in this repository, GitHub releases, or the PowerShell Gallery package** because redistribution rights for this Microsoft binary have not been confirmed.

For WinPE, place your compatible copy here:

```text
WindowsDeviceLink\Runtime\Windows.Management.Service.dll
```

or supply it explicitly:

```powershell
Get-WindowsDeviceLink -WindowsManagementServicePath 'X:\Path\Windows.Management.Service.dll'
```

See [`src/WindowsDeviceLink/Runtime/README.md`](src/WindowsDeviceLink/Runtime/README.md) for details.

## Requirements

- Physical AMD64 device.
- TPM 2.0 in a usable state.
- UEFI firmware.
- 64-bit Windows PowerShell 5.1.
- Windows 11 or compatible AMD64 Windows PE.
- A Windows build that supports Device Association runtime activation.
- For WinPE: a compatible user-supplied `Windows.Management.Service.dll`.
- For direct Graph pre-association/removal: Microsoft Graph permission `DeviceManagementServiceConfig.ReadWrite.All`.
- For firmware read/write: elevated PowerShell with `SeSystemEnvironmentPrivilege` available. The module enables this privilege in the current process.

Always run this first on a new system:

```powershell
Test-WindowsDeviceLinkSupport
```

## Quick start

```powershell
Test-WindowsDeviceLinkSupport
Get-WindowsDeviceLink
```

## Generate DeviceLink information

```powershell
$deviceLink = Get-WindowsDeviceLink
$deviceLink | Format-List *
```

Treat DeviceLink payloads and related device identity fields as sensitive operational data. Do not publish DeviceLink payloads, exported CSVs, serial numbers, SMBIOS UUIDs, Link IDs, or firmware JWT data.

## Export the official DeviceLink CSV

```powershell
Get-WindowsDeviceLink -OutputDirectory 'C:\DeviceLink'
```

Windows itself generates the CSV through `ExportDeviceLinkInfoCsvAsync`. WindowsDeviceLink does not reconstruct or re-encode the CSV.

## Online mode

Starting with `0.4.0-preview1`, `-Online` requires an explicit `-Method`.

```powershell
Get-WindowsDeviceLink -Online -Method <method> ...
```

Supported methods:

| Method | Required input |
|---|---|
| `DeviceCode` | `TenantId` |
| `Interactive` | `TenantId` |
| `ClientSecret` | `TenantId`, `ClientId`, `ClientSecret` |
| `AccessToken` | `TenantId`, `AccessToken` |
| `Certificate` | `TenantId`, `ClientId`, `Certificate` |
| `CertificateThumbprint` | `TenantId`, `ClientId`, `CertificateThumbprint` |
| `CertificateSubjectName` | `TenantId`, `ClientId`, `CertificateSubjectName` |
| `EnvironmentVariable` | `AZURE_TENANT_ID`, `AZURE_CLIENT_ID`, `AZURE_CLIENT_SECRET` |
| `ManagedIdentity` | optional `ClientId` |
| `Webhook` | `WebhookUri`; optional `WebhookApiKey` and `TenantId` |

Parameters that do not belong to the selected method are rejected before DeviceLink generation starts.

### Device code

```powershell
Get-WindowsDeviceLink `
    -Online `
    -Method DeviceCode `
    -TenantId '<tenant-id>'
```

The default DeviceCode client ID is Microsoft's well-known public Graph PowerShell client ID. It is not a customer secret. See [`docs/ONLINE-METHODS.md`](docs/ONLINE-METHODS.md).

## Read local firmware state

Development version `0.4.3-preview1` adds:

```powershell
Get-WindowsDeviceLinkFirmwareState
```

Example:

```powershell
Get-WindowsDeviceLinkFirmwareState |
    Format-Table Name,Present,Size,LastError
```

The cmdlet checks these validated UEFI variables without returning raw contents:

```text
DeviceLinkId
DeviceLinkJwtCompressed
DeviceLinkJwtLastWrite
DeviceLinkCreationTimeUtc
```

## Clear local firmware state

Development version `0.4.3-preview1` also adds:

```powershell
Clear-WindowsDeviceLinkFirmwareState
```

For controlled WinPE automation:

```powershell
Clear-WindowsDeviceLinkFirmwareState -Confirm:$false -PassThru
```

This changes local firmware state only. It does not remove the Intune/Graph Device Association record. See [`docs/FIRMWARE-STATE.md`](docs/FIRMWARE-STATE.md).

## Remove a Device Association record

The normal user-facing route is by serial number:

```powershell
Remove-WindowsDeviceLinkAssociation `
    -SerialNumber '<serial-number>' `
    -Method DeviceCode `
    -TenantId '<tenant-id>'
```

If the association ID is already known, use the exact/advanced route:

```powershell
Remove-WindowsDeviceLinkAssociation `
    -AssociationId '<association-id>' `
    -Method DeviceCode `
    -TenantId '<tenant-id>'
```

The removal endpoint was verified independently as:

```text
DELETE /deviceManagement/tenantAssociatedDevices/{associationId}
```

This is a Device Association operation, not classic Autopilot V1 deletion.

## Associated-device cleanup

Server-side removal and local firmware cleanup are intentionally separate operations.

A controlled decommissioning / tenant-move flow can use:

```powershell
Remove-WindowsDeviceLinkAssociation `
    -SerialNumber '<serial-number>' `
    -Method DeviceCode `
    -TenantId '<source-tenant-id>'

Clear-WindowsDeviceLinkFirmwareState
```

Both parts have been validated in full Windows and AMD64 WinPE at the underlying operation level. Keep them separate unless the workflow deliberately intends to perform both.

## Webhook

```powershell
$webhookKey = $env:WINDOWSDEVICELINK_WEBHOOK_API_KEY

Get-WindowsDeviceLink `
    -Online `
    -Method Webhook `
    -WebhookUri '<webhook-url>' `
    -WebhookApiKey $webhookKey `
    -TenantId '<target-tenant-id>'
```

The receiving automation layer owns tenant routing and Graph authentication. No Graph certificate, client secret, or DeviceCode interaction is required on the device when `-Method Webhook` is used.

The webhook schema is documented in [`docs/WEBHOOK-SCHEMA-v1.md`](docs/WEBHOOK-SCHEMA-v1.md).

## Included Azure Automation receiver

An optional receiving implementation is included:

```text
runbooks/Register-WindowsDeviceLinkWebhook.ps1
```

See [`runbooks/README.md`](runbooks/README.md) for setup instructions.

## Validation status

The primary registration and removal flows are validated on Windows 11 and AMD64 Windows PE.

Validated firmware lifecycle behavior includes:

- clean firmware baseline;
- DeviceLink identity state creation;
- preassociation behavior;
- fully associated firmware state;
- server-side deletion leaving local firmware state intact;
- local firmware cleanup in full Windows;
- local firmware cleanup in AMD64 WinPE;
- post-cleanup verification.

See [`TESTING.md`](TESTING.md) for the complete validation matrix.

## Public commands

| Command | Purpose |
|---|---|
| `Get-WindowsDeviceLink` | Generate, export and/or pre-associate a DeviceLink. |
| `Get-WindowsDeviceLinkFirmwareState` | Read safe metadata for local DeviceLink UEFI state. |
| `Clear-WindowsDeviceLinkFirmwareState` | Clear and verify local DeviceLink UEFI state. |
| `Remove-WindowsDeviceLinkAssociation` | Remove a server-side Device Association record by serial number or association ID. |
| `Test-WindowsDeviceLinkSupport` | Validate runtime, architecture and DeviceLink activation. |
| `Export-WindowsDeviceLinkCsv` | Export an already generated DeviceLink object using the Windows CSV API. |
| `Connect-WindowsDeviceLink` | Advanced Graph SDK authentication helper. |
| `Register-WindowsDeviceLink` | Advanced Graph SDK registration helper for an existing DeviceLink object. |

## Scope

Currently published PowerShell Gallery preview: `0.4.2-preview1`.

Current repository development version: `0.4.3-preview1`.

In scope:

- AMD64 Windows 11;
- AMD64 Windows PE;
- DeviceLink generation;
- official DeviceLink CSV export;
- direct Windows Autopilot Device Preparation Device Association pre-association;
- removal of Device Association records;
- local DeviceLink firmware inspection and cleanup;
- delegated and app-registration authentication;
- webhook transport for centralized automation;
- optional Azure Automation receiver example.

Not currently in scope:

- ARM64;
- Device Preparation policy assignment;
- classic Autopilot V1 management;
- production support guarantees.

## License

Project code is licensed under the MIT License. Microsoft binaries and Microsoft services remain subject to Microsoft's terms.
