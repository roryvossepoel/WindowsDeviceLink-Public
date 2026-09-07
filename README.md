# WindowsDeviceLink

[![PowerShell Gallery Version](https://img.shields.io/powershellgallery/v/WindowsDeviceLink?include_prereleases&label=PowerShell%20Gallery)](https://www.powershellgallery.com/packages/WindowsDeviceLink)
[![PowerShell Gallery Downloads](https://img.shields.io/powershellgallery/dt/WindowsDeviceLink)](https://www.powershellgallery.com/packages/WindowsDeviceLink)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

PowerShell module for **pre-associating physical Windows devices with a Microsoft Intune tenant for Windows Autopilot Device Preparation Device Association**.

WindowsDeviceLink can generate the TPM-backed DeviceLink identity, export the official Windows `.devicelink.csv`, pre-associate directly through Microsoft Graph, remove Device Association records, or send a richer DeviceLink payload to a webhook for centralized automation.

> [!IMPORTANT]
> This is preview / proof-of-concept software. The WinPE implementation uses an undocumented Windows Runtime interface and the online registration/removal flows use Microsoft Graph beta endpoints. These can change without notice.

## Install from PowerShell Gallery

The currently published Gallery preview is `0.4.1-preview1`.

```powershell
Install-Module WindowsDeviceLink -Repository PSGallery -AllowPrerelease
```

Then verify the installation:

```powershell
Import-Module WindowsDeviceLink
Get-Module WindowsDeviceLink | Select-Object Name, Version, Path
Test-WindowsDeviceLinkSupport
```

This repository currently contains `0.4.2-preview1` development changes. They may be newer than the Gallery package until the next preview is published.

## What this module is for

Windows Autopilot Device Preparation Device Association introduces a pre-association step for physical Windows devices. WindowsDeviceLink focuses on:

1. obtaining the DeviceLink identity from the physical device;
2. optionally exporting the official Windows-generated DeviceLink CSV;
3. pre-associating the device with Intune either directly or through a webhook/automation layer;
4. removing Device Association records when a preassociation must be decommissioned or recreated.

The association itself is completed later by Windows during OOBE.

This is **not** classic Windows Autopilot V1 hardware-hash registration.

## What the module can do

- Generate DeviceLink information on AMD64 Windows 11.
- Generate DeviceLink information in AMD64 Windows PE.
- Export the official Windows-generated `.devicelink.csv`.
- Pre-associate directly in Intune using Microsoft Graph.
- Remove Device Association records by serial number or association ID.
- Send a richer DeviceLink payload to a webhook for centralized automation.
- Include an optional tenant ID for multi-tenant routing on the receiving side.
- Include an optional API key in the `X-WindowsDeviceLink-Key` header.
- Use explicit online methods so each flow only accepts its relevant parameters.
- Detect whether the current Windows / WinPE environment can access the DeviceLink runtime.

See [`docs/ONLINE-METHODS.md`](docs/ONLINE-METHODS.md) for guidance on choosing an online method and [`docs/REMOVE-ASSOCIATION.md`](docs/REMOVE-ASSOCIATION.md) for Device Association removal.

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
- For WinPE: a compatible user-supplied `Windows.Management.Service.dll`.
- For direct Graph pre-association/removal: Microsoft Graph permission `DeviceManagementServiceConfig.ReadWrite.All`.

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

Treat DeviceLink payloads and related device identity fields as sensitive operational data. Do not publish DeviceLink payloads, exported CSVs, serial numbers, SMBIOS UUIDs, or Link IDs.

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

## Remove a Device Association record

The normal user-facing route is by serial number:

```powershell
Remove-WindowsDeviceLinkAssociation `
    -SerialNumber '<serial-number>' `
    -Method DeviceCode `
    -TenantId '<tenant-id>'
```

The cmdlet resolves the matching `tenantAssociatedDevice` record and deletes its association ID.

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

This is a Device Association operation, not classic Autopilot V1 deletion. The currently validated scenario is removal of a `preassociated` record. See [`docs/REMOVE-ASSOCIATION.md`](docs/REMOVE-ASSOCIATION.md) for details and lifecycle caveats.

### Webhook

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

The sample receiver supports:

- webhook API-key validation;
- optional default tenant configuration;
- tenant routing through `WindowsDeviceLinkTenantConfiguration`;
- Managed Identity authentication;
- certificate-based authentication stored centrally in Azure Automation;
- Graph DeviceLink pre-association;
- targeted duplicate / HTTP 409 errors.

## Validation status

The main direct registration methods are validated on Windows 11 and AMD64 Windows PE. `0.4.1-preview1` repeated the primary Windows 11 authentication regressions for DeviceCode, ClientSecret, AccessToken, EnvironmentVariable, Certificate, CertificateThumbprint and CertificateSubjectName.

The webhook route has been validated end-to-end on Windows 11 with API-key validation, tenant routing, Azure Automation PowerShell 7.4, Managed Identity Graph authentication and successful pre-association.

`0.4.2-preview1` development additionally validates Device Association removal on Windows 11 by both serial number and exact association ID.

See [`TESTING.md`](TESTING.md) for the validation matrix.

## Public commands

| Command | Purpose |
|---|---|
| `Get-WindowsDeviceLink` | Generate, export and/or pre-associate a DeviceLink. |
| `Remove-WindowsDeviceLinkAssociation` | Remove a Device Association record by serial number or association ID. |
| `Test-WindowsDeviceLinkSupport` | Validate runtime, architecture and DeviceLink activation. |
| `Export-WindowsDeviceLinkCsv` | Export an already generated DeviceLink object using the Windows CSV API. |
| `Connect-WindowsDeviceLink` | Advanced Graph SDK authentication helper. |
| `Register-WindowsDeviceLink` | Advanced Graph SDK registration helper for an existing DeviceLink object. |

## Scope

Currently published PowerShell Gallery preview: `0.4.1-preview1`.

Current repository development version: `0.4.2-preview1`.

In scope:

- AMD64 Windows 11;
- AMD64 Windows PE;
- DeviceLink generation;
- official DeviceLink CSV export;
- direct Windows Autopilot Device Preparation Device Association pre-association;
- removal of Device Association records;
- delegated and app-registration authentication;
- webhook transport for centralized automation;
- optional Azure Automation receiver example.

Not currently in scope:

- ARM64;
- Device Preparation policy assignment;
- association completion / UEFI write operations;
- full device-side/UEFI decommissioning for already associated devices;
- production support guarantees.

## License

Project code is licensed under the MIT License. Microsoft binaries and Microsoft services remain subject to Microsoft's terms.
