# WindowsDeviceLink

[![PowerShell Gallery Version](https://img.shields.io/powershellgallery/v/WindowsDeviceLink?include_prereleases&label=PowerShell%20Gallery)](https://www.powershellgallery.com/packages/WindowsDeviceLink)
[![PowerShell Gallery Downloads](https://img.shields.io/powershellgallery/dt/WindowsDeviceLink)](https://www.powershellgallery.com/packages/WindowsDeviceLink)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

PowerShell module for **pre-associating physical Windows devices with a Microsoft Intune tenant for Windows Autopilot Device Preparation Device Association**.

WindowsDeviceLink can generate the TPM-backed DeviceLink identity, export the official Windows `.devicelink.csv`, pre-associate directly through Microsoft Graph, or send a richer DeviceLink payload to a webhook for centralized automation.

> [!IMPORTANT]
> This is preview / proof-of-concept software. The WinPE implementation uses an undocumented Windows Runtime interface and the online registration uses a Microsoft Graph beta endpoint. Both can change without notice.

## Install from PowerShell Gallery

The currently published Gallery preview is `0.4.0-preview1`.

```powershell
Install-Module WindowsDeviceLink -Repository PSGallery -AllowPrerelease
```

Then verify the installation:

```powershell
Import-Module WindowsDeviceLink
Get-Module WindowsDeviceLink | Select-Object Name, Version, Path
Test-WindowsDeviceLinkSupport
```

This repository may contain post-`0.4.0-preview1` development changes before the next Gallery preview is published.

## What this module is for

Windows Autopilot Device Preparation Device Association introduces a pre-association step for physical Windows devices. WindowsDeviceLink focuses on:

1. obtaining the DeviceLink identity from the physical device;
2. optionally exporting the official Windows-generated DeviceLink CSV;
3. pre-associating the device with Intune either directly or through a webhook/automation layer.

The association itself is completed later by Windows during OOBE.

This is **not** classic Windows Autopilot V1 hardware-hash registration.

## What the module can do

- Generate DeviceLink information on AMD64 Windows 11.
- Generate DeviceLink information in AMD64 Windows PE.
- Export the official Windows-generated `.devicelink.csv`.
- Pre-associate directly in Intune using Microsoft Graph.
- Send a richer DeviceLink payload to a webhook for centralized automation.
- Include an optional tenant ID for multi-tenant routing on the receiving side.
- Include an optional API key in the `X-WindowsDeviceLink-Key` header.
- Use explicit online methods so each flow only accepts its relevant parameters.
- Detect whether the current Windows / WinPE environment can access the DeviceLink runtime.

See [`docs/ONLINE-METHODS.md`](docs/ONLINE-METHODS.md) for guidance on choosing an online method.

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
- For direct Graph pre-association: Microsoft Graph permission `DeviceManagementServiceConfig.ReadWrite.All`.

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

The direct methods were validated successfully on both Windows 11 and AMD64 Windows PE in the 0.3.x line.

The webhook route has been validated end-to-end on Windows 11 with:

- webhook transport;
- request headers and JSON payload;
- API-key validation;
- incorrect API-key rejection before Graph registration;
- tenant configuration routing;
- Azure Automation PowerShell 7.4 Runtime Environment;
- `Microsoft.Graph.Authentication`;
- Managed Identity Graph authentication;
- successful DeviceLink pre-association returning `associationState = preassociated`.

Post-0.4.0 development also adds a reusable parameter regression suite, a formal schema v1 contract, method-selection guidance, and more targeted webhook transport errors.

See [`TESTING.md`](TESTING.md) for the validation matrix.

## Public commands

| Command | Purpose |
|---|---|
| `Get-WindowsDeviceLink` | Generate, export and/or pre-associate a DeviceLink. |
| `Test-WindowsDeviceLinkSupport` | Validate runtime, architecture and DeviceLink activation. |
| `Export-WindowsDeviceLinkCsv` | Export an already generated DeviceLink object using the Windows CSV API. |
| `Connect-WindowsDeviceLink` | Advanced Graph SDK authentication helper. |
| `Register-WindowsDeviceLink` | Advanced Graph SDK registration helper for an existing DeviceLink object. |

## Scope

Currently published PowerShell Gallery preview: `0.4.0-preview1`.

In scope:

- AMD64 Windows 11;
- AMD64 Windows PE;
- DeviceLink generation;
- official DeviceLink CSV export;
- direct Windows Autopilot Device Preparation Device Association pre-association;
- delegated and app-registration authentication;
- webhook transport for centralized automation;
- optional Azure Automation receiver example.

Not currently in scope:

- ARM64;
- Device Preparation policy assignment;
- association completion / UEFI write operations;
- association removal / decommissioning until the correct Device Association delete API is verified;
- production support guarantees.

## License

Project code is licensed under the MIT License. Microsoft binaries and Microsoft services remain subject to Microsoft's terms.
