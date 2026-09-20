# WindowsDeviceLink

[![PowerShell Gallery Version](https://img.shields.io/powershellgallery/v/WindowsDeviceLink?include_prereleases&label=PowerShell%20Gallery)](https://www.powershellgallery.com/packages/WindowsDeviceLink)
[![PowerShell Gallery Downloads](https://img.shields.io/powershellgallery/dt/WindowsDeviceLink)](https://www.powershellgallery.com/packages/WindowsDeviceLink)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

PowerShell module for **Windows Autopilot Device Preparation Device Association** on physical Windows devices.

WindowsDeviceLink can:

- generate/read the TPM-backed DeviceLink identity;
- export the official Windows-generated `.devicelink.csv`;
- query, pre-associate and remove Intune Device Association records;
- inspect and reset local DeviceLink UEFI state;
- discover and complete device-side association on supported full Windows builds;
- provide diagnostics, health classification, preflight checks and safe lifecycle orchestration;
- send pre-association requests to optional Azure Function or Azure Automation backends.

> [!IMPORTANT]
> WindowsDeviceLink is preview / proof-of-concept software. The WinPE implementation and native DeviceLink association completion use undocumented Windows Runtime interfaces, and Device Association cloud operations use Microsoft Graph beta endpoints. These can change without notice.

## Start here

- **New to Device Preparation?** Read [Windows Autopilot v1 vs Windows Autopilot device preparation](docs/AUTOPILOT-V1-VS-DEVICE-PREPARATION.md).
- **Want to know which command to run?** See the [FAQ / common operations](docs/FAQ.md).
- **Installing on Windows 11 or WinPE?** Read the [installation guide](docs/INSTALLATION.md).
- **Using WinPE before Windows installation?** Read the [WinPE workflow and support boundaries](docs/WINPE-WORKFLOW.md).
- **Using an Azure backend?** Read [Azure backend options](docs/AZURE-BACKEND.md).

## Current version

The current preview release line is `0.5.2-preview1`.

This release adds the read-only `Test-WindowsDeviceLinkRuntime` diagnostic, documents the validated WinPE pre-association -> Windows 11 OOBE flow, and clarifies the native discovery/completion boundary in WinPE.

## Mental model

WindowsDeviceLink keeps the local, cloud and completion layers separate:

```text
Local DeviceLink identity
    Get-WindowsDeviceLink

Local DeviceLink firmware state
    Get-WindowsDeviceLinkFirmwareState
    Reset-WindowsDeviceLinkFirmwareState

Tenant-side Intune Device Association
    Get-WindowsDeviceLinkAssociation
    Register-WindowsDeviceLink
    Remove-WindowsDeviceLinkAssociation

Native device-side association
    Test-WindowsDeviceLinkDiscovery
    Complete-WindowsDeviceLinkAssociation

Diagnostics / orchestration
    Get-WindowsDeviceLinkStatus
    Get-WindowsDeviceLinkRepairPlan
    Test-WindowsDeviceLinkHealth
    Test-WindowsDeviceLinkPreflight
    Test-WindowsDeviceLinkAssociationJwt
    Test-WindowsDeviceLinkRuntime
    Initialize-WindowsDeviceLink
```

`Get-WindowsDeviceLink` is always local. It does not authenticate to Microsoft Graph and does not create tenant-side state.

## Device Association lifecycle

The normal lifecycle is:

```text
LocalOnly -> Preassociated -> Associated -> Offboarded
```

### Offboarding

The required cleanup depends on the current association state:

```text
Pre-associated
    -> delete the tenant-side Device Association record
    -> done

Associated
    -> ensure the device is no longer enrolled with MDM
    -> clear the local Device Link UEFI state
    -> delete the tenant-side Device Association record
    -> done
```

For an **Associated** device, deleting only the Device Association record from Intune is not a complete offboarding operation. The trusted tenant affinity remains in UEFI until the local Device Link state is cleared.

See [OFFBOARDING.md](docs/OFFBOARDING.md) for the complete operator flow.

## Installation

### Windows 11

Run 64-bit Windows PowerShell 5.1 as administrator:

```powershell
Install-Module WindowsDeviceLink `
    -Repository PSGallery `
    -AllowPrerelease `
    -Force

Import-Module WindowsDeviceLink -Force
Test-WindowsDeviceLinkSupport
```

### Windows PE

The current unsigned Gallery preview can require `-SkipPublisherCheck` in the validated AMD64 WinPE / PowerShellGet environment:

```powershell
Install-Module WindowsDeviceLink `
    -Repository PSGallery `
    -AllowPrerelease `
    -SkipPublisherCheck `
    -Force
```

WinPE additionally requires a compatible administrator-supplied `Windows.Management.Service.dll`. WindowsDeviceLink intentionally does not redistribute this Microsoft binary.

See [INSTALLATION.md](docs/INSTALLATION.md) for the complete setup and troubleshooting path.

## Requirements

- Physical AMD64 device.
- TPM 2.0 in a usable state.
- UEFI firmware.
- 64-bit Windows PowerShell 5.1.
- Windows 11 or compatible AMD64 Windows PE.
- WinPE: compatible administrator-supplied `Windows.Management.Service.dll`.
- Direct Graph Device Association operations: Microsoft Graph permission `DeviceManagementServiceConfig.ReadWrite.All`.
- Firmware read/reset and explicit device-side completion: elevated PowerShell with the required firmware/runtime access.

Start on a new system with:

```powershell
Test-WindowsDeviceLinkSupport
```

For explicit native completion, also run:

```powershell
Test-WindowsDeviceLinkPreflight
```

## Common operations

### Read the local DeviceLink identity

```powershell
Get-WindowsDeviceLink
```

Export the official Windows-generated CSV:

```powershell
Get-WindowsDeviceLink -OutputDirectory 'C:\DeviceLink'
```

### Create a tenant-side pre-association

For normal delegated use, `-TenantId` can be omitted. Supply it when you intentionally need to target a specific tenant, such as in a multi-tenant or guest-account scenario.

```powershell
Get-WindowsDeviceLink |
    Register-WindowsDeviceLink `
        -Method DeviceCode
```

### Query combined local/cloud status

```powershell
Get-WindowsDeviceLinkStatus `
    -Online `
    -Method DeviceCode |
    Format-List *
```

### Safely initialize the full lifecycle

Pre-association only:

```powershell
Initialize-WindowsDeviceLink `
    -Method DeviceCode
```

Pre-association plus explicit device-side completion:

```powershell
Initialize-WindowsDeviceLink `
    -Method DeviceCode `
    -CompleteAssociation
```

Expected lifecycle:

```text
LocalOnly -> Register -> Preassociated -> Complete -> Associated
```

For removal, firmware reset, tenant moves, discovery troubleshooting and detailed state transitions, use the [FAQ](docs/FAQ.md) and dedicated documentation instead of treating the README as the operational manual.

## Windows PE workflow

Windows PE is primarily a **preparation** environment:

```text
Windows PE
    |
    | administrator-supplied Windows.Management.Service.dll
    v
Generate/read DeviceLink identity
    |
    v
Create tenant-side pre-association
    |
    v
Install Windows 11
    |
    v
Windows 11 OOBE + network
    |
    v
Windows completes Device Association
```

With an administrator-supplied compatible runtime, identity generation/readout and tenant-side lifecycle operations are validated in AMD64 WinPE.

Native DeviceLink discovery/completion in WinPE remains experimental. Current research reaches `RequestDiscoveryUrlAsync` and fails with HRESULT `0x81036C00`. Full Windows remains the validated environment for explicit native completion.

See [WINPE-WORKFLOW.md](docs/WINPE-WORKFLOW.md).

## Azure backends

WindowsDeviceLink includes two **optional reference backends** for centralized/unattended pre-association.

### Azure Function

HTTP API backend with pre-association and multitenant lookup.

[![Deploy Azure Function](https://aka.ms/deploytoazurebutton)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Froryvossepoel%2FWindowsDeviceLink-Public%2Fmain%2Finfrastructure%2Ffunction-app%2Fazuredeploy.json)

### Azure Automation

PowerShell runbook backend. The webhook itself is created after deployment so its secret URL is not exposed through deployment output/history.

[![Deploy Azure Automation](https://aka.ms/deploytoazurebutton)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Froryvossepoel%2FWindowsDeviceLink-Public%2Fmain%2Finfrastructure%2Fautomation%2Fazuredeploy.json)

These are working reference deployments, not prescribed production landing zones.

- Same-tenant Azure Automation: **Managed Identity preferred**.
- Cross-tenant: **multitenant App Registration + certificate preferred**.
- Client secret: supported fallback.

See:

- [Azure backend architecture](docs/AZURE-BACKEND.md)
- [App registration](docs/APP-REGISTRATION.md)
- [Multitenant admin consent](docs/MULTITENANT-CONSENT.md)
- [Security and hardening guidance](docs/SECURITY-HARDENING.md)
- [Function deployment](infrastructure/function-app/README.md)
- [Automation deployment](infrastructure/automation/README.md)

### Using the webhook backend

Both backends consume the same webhook contract:

```powershell
Get-WindowsDeviceLink |
    Register-WindowsDeviceLink `
        -Method Webhook `
        -WebhookUri '<backend-uri>' `
        -WebhookApiKey $env:WINDOWSDEVICELINK_WEBHOOK_API_KEY `
        -TenantId '<target-tenant-id>'
```

`WebhookApiKey` protects the receiver. `TenantId` is target-tenant routing metadata. Neither replaces Microsoft Graph authentication performed by the backend.

See [WEBHOOK-SCHEMA-v1.md](docs/WEBHOOK-SCHEMA-v1.md).

## Public commands

| Command | Purpose |
|---|---|
| `Complete-WindowsDeviceLinkAssociation` | Guardedly complete a preassociated DeviceLink on the local device and verify the resulting firmware/JWT state. |
| `Connect-WindowsDeviceLink` | Advanced Microsoft Graph SDK authentication helper. |
| `Export-WindowsDeviceLinkCsv` | Export an existing DeviceLink object using the Windows CSV API. |
| `Get-WindowsDeviceLink` | Obtain the local DeviceLink identity; optionally export it. |
| `Get-WindowsDeviceLinkAssociation` | Query a tenant-side Intune Device Association by serial number or association ID. |
| `Get-WindowsDeviceLinkFirmwareState` | Read safe metadata and the validated firmware timestamp. |
| `Get-WindowsDeviceLinkRepairPlan` | Return a non-destructive repair recommendation for observed lifecycle state. |
| `Get-WindowsDeviceLinkStatus` | Combine runtime, local identity, firmware and optional tenant-side association diagnostics. |
| `Initialize-WindowsDeviceLink` | Safely initialize pre-association and optionally complete association with explicit `-CompleteAssociation`. |
| `Register-WindowsDeviceLink` | Explicitly create a tenant-side pre-association directly or through a webhook. |
| `Remove-WindowsDeviceLinkAssociation` | Remove a tenant-side Device Association record. |
| `Reset-WindowsDeviceLinkFirmwareState` | Reset and immediately verify local DeviceLink UEFI identity state. |
| `Test-WindowsDeviceLinkAssociationJwt` | Validate local association JWT structure/time/identity correlation without exposing the raw JWT. |
| `Test-WindowsDeviceLinkDiscovery` | Perform read-only native DeviceLink association discovery. |
| `Test-WindowsDeviceLinkHealth` | Non-destructively classify status into machine-readable lifecycle/health states. |
| `Test-WindowsDeviceLinkPreflight` | Assess local runtime, firmware, TPM, Secure Boot and DeviceLink prerequisites. |
| `Test-WindowsDeviceLinkRuntime` | Validate an administrator-supplied runtime DLL without changing state. |
| `Test-WindowsDeviceLinkSupport` | Validate runtime, architecture and DeviceLink activation. |

## Documentation

- [AUTOPILOT-V1-VS-DEVICE-PREPARATION.md](docs/AUTOPILOT-V1-VS-DEVICE-PREPARATION.md) — classic Windows Autopilot vs Windows Autopilot device preparation.
- [FAQ.md](docs/FAQ.md) — practical operations and lifecycle questions.
- [INSTALLATION.md](docs/INSTALLATION.md) — Windows 11 / WinPE installation and troubleshooting.
- [WINPE-WORKFLOW.md](docs/WINPE-WORKFLOW.md) — supported WinPE workflow and native completion boundary.
- [ONLINE-METHODS.md](docs/ONLINE-METHODS.md) — cloud operations and authentication methods.
- [AZURE-BACKEND.md](docs/AZURE-BACKEND.md) — Function / Automation architecture and deployment.
- [APP-REGISTRATION.md](docs/APP-REGISTRATION.md) — multitenant Entra App Registration and Graph permission.
- [MULTITENANT-CONSENT.md](docs/MULTITENANT-CONSENT.md) — onboarding target tenants with explicit admin consent.
- [MULTITENANT-LOOKUP.md](docs/MULTITENANT-LOOKUP.md) — search managed tenants by serial number.
- [SECURITY-HARDENING.md](docs/SECURITY-HARDENING.md) — reference-deployment security boundary and optional hardening.
- [FIRMWARE-STATE.md](docs/FIRMWARE-STATE.md) — UEFI state and reset lifecycle.
- [DISCOVER-LINK-RESEARCH.md](docs/DISCOVER-LINK-RESEARCH.md) — validated DeviceLinkManager research/evidence.
- [OFFBOARDING.md](docs/OFFBOARDING.md) — complete pre-associated / associated offboarding flow.
- [REMOVE-ASSOCIATION.md](docs/REMOVE-ASSOCIATION.md) — tenant-side Device Association removal.
- [CODE-SIGNING.md](docs/CODE-SIGNING.md) — code-signing policy and release provenance.
- [PRIVACY.md](PRIVACY.md) — privacy policy and administrator-initiated network transfers.
- [TESTING.md](TESTING.md) — validation matrix and live-test evidence.

## Scope

Preview release line: `0.5.2-preview1`.

In scope: AMD64 Windows 11/WinPE, DeviceLink generation, official CSV export, Device Association query/pre-association/removal, native association discovery/completion on supported full Windows builds, local firmware inspection/reset, diagnostics/health, safe initialization, multiple authentication methods, webhook transport and optional Azure reference backends.

Not currently in scope: ARM64, Device Preparation policy assignment, classic Autopilot v1 management, automatic destructive repair, cryptographic association-JWT signature verification, or production support guarantees.

## Code signing

Preview releases remain unsigned for now. The SignPath Foundation application was reviewed but not approved at this stage because the project does not yet have enough external adoption/visibility signals for the Foundation program.

WindowsDeviceLink does not redistribute or sign Microsoft's `Windows.Management.Service.dll`.

See [CODE-SIGNING.md](docs/CODE-SIGNING.md).

## License

Project code is licensed under the MIT License. Microsoft binaries and Microsoft services remain subject to Microsoft's terms.
