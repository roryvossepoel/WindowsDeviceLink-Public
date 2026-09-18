# WindowsDeviceLink

[![PowerShell Gallery Version](https://img.shields.io/powershellgallery/v/WindowsDeviceLink?include_prereleases&label=PowerShell%20Gallery)](https://www.powershellgallery.com/packages/WindowsDeviceLink)
[![PowerShell Gallery Downloads](https://img.shields.io/powershellgallery/dt/WindowsDeviceLink)](https://www.powershellgallery.com/packages/WindowsDeviceLink)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

PowerShell module for **Windows Autopilot Device Preparation Device Association** on physical Windows devices.

WindowsDeviceLink can generate the TPM-backed DeviceLink identity, export the official Windows `.devicelink.csv`, query/pre-associate/remove Intune Device Association records, discover tenant association routing, complete device-side association, inspect and reset local DeviceLink UEFI state, and provide combined local/cloud diagnostics and health classification.

> [!IMPORTANT]
> This is preview / proof-of-concept software. The WinPE implementation and native DeviceLink association completion use undocumented Windows Runtime interfaces, and the Device Association cloud operations use Microsoft Graph beta endpoints. These can change without notice.

## Start here

- **New to Device Preparation?** Read [Windows Autopilot v1 vs Windows Autopilot device preparation](docs/AUTOPILOT-V1-VS-DEVICE-PREPARATION.md).
- **Want to know which command to run?** See the [WindowsDeviceLink FAQ / common operations](docs/FAQ.md).
- **Installing on Windows 11 or WinPE?** Read the [installation guide](docs/INSTALLATION.md).
- **Using WinPE before Windows installation?** Read the [WinPE workflow and support boundaries](docs/WINPE-WORKFLOW.md).

## Current version

The current preview release line is `0.5.2-preview1`.

This preview adds a read-only runtime diagnostic for administrator-supplied `Windows.Management.Service.dll` files, documents the validated WinPE pre-association -> Windows 11 OOBE flow, and clarifies the support boundary for native discovery/completion in WinPE. It also retains the completion progress/timing telemetry introduced in 0.5.1-preview1.

## Mental model

Starting with `0.5.0-preview1`, the module exposes the layers explicitly:

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
    Initialize-WindowsDeviceLink
```

`Get-WindowsDeviceLink -Online` has been removed. `Get-WindowsDeviceLink` is always local and a `Get-*` identity operation never creates cloud state.

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

The current unsigned Gallery preview has a validated WinPE-specific PowerShellGet publisher-check issue. In the tested AMD64 WinPE this succeeds:

```powershell
Install-Module WindowsDeviceLink `
    -Repository PSGallery `
    -AllowPrerelease `
    -SkipPublisherCheck `
    -Force
```

`-SkipPublisherCheck` is a temporary workaround for the unsigned preview. WinPE additionally requires a compatible user-supplied `Windows.Management.Service.dll`; the Microsoft DLL is intentionally not redistributed.

Read [`docs/INSTALLATION.md`](docs/INSTALLATION.md) before deploying in WinPE. It covers PowerShellGet, PackageManagement, NuGet, TLS, prerelease installation, the runtime DLL, verification and troubleshooting.

## Requirements

- Physical AMD64 device.
- TPM 2.0 in a usable state.
- UEFI firmware.
- 64-bit Windows PowerShell 5.1.
- Windows 11 or compatible AMD64 Windows PE.
- For WinPE: a compatible user-supplied `Windows.Management.Service.dll`.
- For direct Graph Device Association operations: Microsoft Graph permission `DeviceManagementServiceConfig.ReadWrite.All`.
- For firmware read/reset and device-side completion: elevated PowerShell with the required firmware/runtime access.

Always start on a new system with:

```powershell
Test-WindowsDeviceLinkSupport
```

For association completion, also run:

```powershell
Test-WindowsDeviceLinkPreflight
```

## Generate the local DeviceLink identity

```powershell
$deviceLink = Get-WindowsDeviceLink
$deviceLink | Format-List *
```

`Get-WindowsDeviceLink` does not authenticate to Microsoft Graph and does not change tenant-side state.

`PayloadCreationTimeUtc` is the timestamp of the generated DeviceLink payload. It changes between payload generations and is deliberately distinguished from the persistent firmware `DeviceLinkCreationTimeUtc` value.

Treat DeviceLink payloads, serial numbers, SMBIOS UUIDs, Link IDs and firmware JWT data as sensitive operational data.

## Export the official DeviceLink CSV

```powershell
Get-WindowsDeviceLink -OutputDirectory 'C:\DeviceLink'
```

Windows generates the CSV through `ExportDeviceLinkInfoCsvAsync`; WindowsDeviceLink does not reconstruct the format.

## Pre-associate explicitly

```powershell
$deviceLink = Get-WindowsDeviceLink

$deviceLink | Register-WindowsDeviceLink `
    -Method DeviceCode `
    -TenantId '<tenant-id>'
```

Registration is deliberately a `Register-*` operation. The default DeviceCode client ID is Microsoft's well-known public Graph PowerShell client ID and is not a customer secret.

See [`docs/ONLINE-METHODS.md`](docs/ONLINE-METHODS.md) for all supported authentication methods.

## Query the tenant-side Device Association

```powershell
Get-WindowsDeviceLinkAssociation `
    -SerialNumber '<serial-number>' `
    -Method DeviceCode `
    -TenantId '<tenant-id>'
```

You can also query the exact record with `-AssociationId`. The cmdlet returns tenant-side association state and related Intune metadata; it does not read or change local firmware state.

> [!NOTE]
> During live validation, server-side Graph filtering by serial number did not reliably return an existing `tenantAssociatedDevices` record. The current implementation falls back to paged client-side matching. This is functionally validated but may be less efficient in large tenants; see GitHub issue #1 for the planned retest/optimization.

## Discover device-side association routing

`Test-WindowsDeviceLinkDiscovery` performs the native DeviceLink discovery phase without invoking configure or changing association firmware state. Native discovery is validated on full Windows. In WinPE, direct runtime activation and DeviceLink identity generation work with an administrator-supplied runtime, but native discovery currently fails at `RequestDiscoveryUrlAsync` with HRESULT `0x81036C00`; this is not required for the normal WinPE pre-association -> Windows 11 OOBE flow:

```powershell
Test-WindowsDeviceLinkDiscovery | Format-List *
```

A successful preassociated device can return the tenant ID and enrollment discovery URL together with the native discovery result and async status. The command is intended for diagnostics and readiness checks; it is read-only with respect to DeviceLink association completion.

## Complete device-side association

After the local DeviceLink has been preassociated in the tenant, Windows can complete the association locally:

```powershell
Complete-WindowsDeviceLinkAssociation | Format-List *
```

For a dry run:

```powershell
Complete-WindowsDeviceLinkAssociation -WhatIf
```

The command is deliberately guarded:

- validates preflight and local firmware state first;
- performs native discovery before configure;
- invokes `ConfigureDeviceLinkAsync` at most once;
- performs no automatic retry, firmware reset, cleanup, cloud deletion, or reboot;
- verifies firmware `4/4` after completion;
- validates that the resulting association JWT is structurally valid and matches the local DeviceLink identity;
- returns `AlreadyComplete` without another configure call when local association state is already complete.

The raw association JWT is never returned. `Test-WindowsDeviceLinkAssociationJwt` performs structural, temporal and identity correlation only; cryptographic signature validation is explicitly reported as `NotPerformed` unless a trustworthy signature-validation implementation is added in the future.

See [`docs/DISCOVER-LINK-RESEARCH.md`](docs/DISCOVER-LINK-RESEARCH.md) for the validated native contract and live transition evidence.

## Combined status and health

Local diagnostics require no Graph authentication:

```powershell
Get-WindowsDeviceLinkStatus | Format-List *
Test-WindowsDeviceLinkHealth | Format-List *
```

To correlate the same local device with Intune:

```powershell
Get-WindowsDeviceLinkStatus `
    -Online `
    -Method DeviceCode `
    -TenantId '<tenant-id>' |
    Test-WindowsDeviceLinkHealth |
    Format-List *
```

`Get-WindowsDeviceLinkStatus` keeps observed state explicit: local identity, firmware state, and optional cloud association. `Test-WindowsDeviceLinkHealth` classifies that status without modifying anything. A failed cloud lookup is distinct from a confirmed `NotAssociated` result.

Validated examples include `LocalBaseIdentity`, `LocalOnly`, `Preassociated`, `Associated`, incomplete firmware states, unsupported/runtime failures, and unknown cloud state. Health classification is intended for diagnostics and automation; it never resets, removes, registers, completes, or reboots.

## Safe idempotent initialization

By default, `Initialize-WindowsDeviceLink` keeps its original conservative goal: ensure a valid local DeviceLink has a tenant-side preassociation. It creates a preassociation only when the validated state is exactly `LocalOnly`:

```powershell
Initialize-WindowsDeviceLink `
    -Method DeviceCode `
    -TenantId '<tenant-id>'
```

To explicitly opt in to the full lifecycle through device-side completion:

```powershell
Initialize-WindowsDeviceLink `
    -Method DeviceCode `
    -TenantId '<tenant-id>' `
    -CompleteAssociation
```

The opt-in lifecycle is:

```text
LocalOnly -> Register -> Preassociated -> Complete -> Associated
```

Dry run:

```powershell
Initialize-WindowsDeviceLink `
    -Method DeviceCode `
    -TenantId '<tenant-id>' `
    -CompleteAssociation `
    -WhatIf
```

The initializer remains conservative:

- without `-CompleteAssociation`, `LocalOnly` registers and `Preassociated` remains unchanged;
- with `-CompleteAssociation`, a verified `Preassociated` state can run guarded completion;
- `Associated` remains idempotent and returns `CompletionResult = AlreadyAssociated` without another configure call;
- unexpected/incomplete/unknown states are blocked;
- it never resets firmware, removes an association, or reboots.

For DeviceCode authentication the initializer reuses one access token for lookup, registration and verification, so a normal run requires one device-code sign-in rather than one sign-in per cloud step.

## Read local firmware state

```powershell
Get-WindowsDeviceLinkFirmwareState
```

The cmdlet checks the four validated DeviceLink UEFI variables:

```text
DeviceLinkId
DeviceLinkJwtCompressed
DeviceLinkJwtLastWrite
DeviceLinkCreationTimeUtc
```

Raw `DeviceLinkId` and JWT contents are never returned. `DeviceLinkCreationTimeUtc` has been validated as a UTF-8 ISO-8601 UTC timestamp in both whole-second and fractional-second forms. Only this safe timestamp is exposed in decoded/parsed form. `Get-WindowsDeviceLinkStatus` surfaces it separately as `FirmwareCreationTimeUtc`.

## Reset local firmware state

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

Reset removes all four known DeviceLink UEFI variables and immediately verifies that they are absent. After reboot Windows can generate a new DeviceLink identity; this is new identity generation, not restoration of the removed identity.

See [`docs/FIRMWARE-STATE.md`](docs/FIRMWARE-STATE.md) for the validated lifecycle.

## Remove a tenant-side Device Association

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

Server-side removal and local reset are intentionally separate operations:

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
Windows creates a new local DeviceLink identity
        |
        v
Get-WindowsDeviceLink
        |
        v
Register-WindowsDeviceLink
        |
        v
Complete-WindowsDeviceLinkAssociation
```

The identity-reset and preassociation sequence has been validated on physical AMD64 hardware. Native completion has separately been validated from a known `Preassociated + 2/4` state to `Associated + 4/4`.

## Webhook registration

For centralized/unattended workflows:

```powershell
$deviceLink = Get-WindowsDeviceLink

$deviceLink | Register-WindowsDeviceLink `
    -Method Webhook `
    -WebhookUri '<webhook-url>' `
    -WebhookApiKey $env:WINDOWSDEVICELINK_WEBHOOK_API_KEY `
    -TenantId '<target-tenant-id>'
```

See [`docs/AZURE-BACKEND.md`](docs/AZURE-BACKEND.md), [`docs/MULTITENANT-LOOKUP.md`](docs/MULTITENANT-LOOKUP.md), [`docs/WEBHOOK-SCHEMA-v1.md`](docs/WEBHOOK-SCHEMA-v1.md), [`function-app/README.md`](function-app/README.md), [`infrastructure/function-app/README.md`](infrastructure/function-app/README.md), [`infrastructure/automation/README.md`](infrastructure/automation/README.md), and [`runbooks/README.md`](runbooks/README.md).

## Public commands

| Command | Purpose |
|---|---|
| `Complete-WindowsDeviceLinkAssociation` | Guardedly complete a preassociated DeviceLink on the local device and verify the resulting firmware/JWT state. |
| `Connect-WindowsDeviceLink` | Advanced Microsoft Graph SDK authentication helper. |
| `Export-WindowsDeviceLinkCsv` | Export an existing DeviceLink object using the Windows CSV API. |
| `Get-WindowsDeviceLink` | Obtain the local DeviceLink identity; optionally export it. |
| `Get-WindowsDeviceLinkAssociation` | Query a tenant-side Intune Device Association by serial number or association ID. |
| `Get-WindowsDeviceLinkFirmwareState` | Read safe metadata and the validated safe firmware timestamp. |
| `Get-WindowsDeviceLinkRepairPlan` | Return a non-destructive repair recommendation for observed lifecycle state. |
| `Get-WindowsDeviceLinkStatus` | Combine runtime, local identity, firmware, and optional tenant-side association diagnostics. |
| `Initialize-WindowsDeviceLink` | Safely initialize preassociation and optionally complete association with explicit `-CompleteAssociation`. |
| `Register-WindowsDeviceLink` | Explicitly create a tenant-side preassociation from an existing local DeviceLink object, directly or through a webhook. |
| `Remove-WindowsDeviceLinkAssociation` | Remove a tenant-side Device Association record. |
| `Reset-WindowsDeviceLinkFirmwareState` | Reset and immediately verify local DeviceLink UEFI identity state. |
| `Test-WindowsDeviceLinkAssociationJwt` | Validate local association JWT structure/time/identity correlation without exposing the raw JWT. |
| `Test-WindowsDeviceLinkDiscovery` | Perform read-only native DeviceLink association discovery. |
| `Test-WindowsDeviceLinkHealth` | Non-destructively classify a status object into machine-readable health/lifecycle states. |
| `Test-WindowsDeviceLinkPreflight` | Assess local runtime, firmware, TPM, Secure Boot and DeviceLink prerequisites. |
| `Test-WindowsDeviceLinkRuntime` | Read-only validation of an administrator-supplied DeviceLink runtime DLL, including architecture, version, signature context and activation. |
| `Test-WindowsDeviceLinkSupport` | Validate runtime, architecture and DeviceLink activation. |

## Documentation

- [`docs/AUTOPILOT-V1-VS-DEVICE-PREPARATION.md`](docs/AUTOPILOT-V1-VS-DEVICE-PREPARATION.md) - classic Windows Autopilot vs Windows Autopilot device preparation, terminology, lifecycle and coexistence.
- [`docs/FAQ.md`](docs/FAQ.md) - practical common operations: what to run to preassociate, complete, remove, reset, restart, move tenants, or troubleshoot.
- [`docs/INSTALLATION.md`](docs/INSTALLATION.md) - Windows 11 and WinPE installation, PowerShellGet/PackageManagement and troubleshooting.
- [`docs/WINPE-WORKFLOW.md`](docs/WINPE-WORKFLOW.md) - WinPE pre-association workflow, administrator-supplied runtime, and native discovery/completion support boundary.
- [`docs/ONLINE-METHODS.md`](docs/ONLINE-METHODS.md) - cloud operations and authentication methods.
- [`docs/AZURE-BACKEND.md`](docs/AZURE-BACKEND.md) - Azure Function / Automation backend architecture and Deploy to Azure.
- [`infrastructure/function-app/README.md`](infrastructure/function-app/README.md) - Deploy the Azure Function backend.
- [`infrastructure/automation/README.md`](infrastructure/automation/README.md) - Deploy the Azure Automation backend.
- [`docs/APP-REGISTRATION.md`](docs/APP-REGISTRATION.md) - multitenant Entra app registration and Graph permission.
- [`docs/MULTITENANT-CONSENT.md`](docs/MULTITENANT-CONSENT.md) - onboarding target tenants with explicit admin consent.
- [`docs/SECURITY-HARDENING.md`](docs/SECURITY-HARDENING.md) - reference deployment security boundary and optional organization-specific hardening.
- [`docs/MULTITENANT-LOOKUP.md`](docs/MULTITENANT-LOOKUP.md) - search all managed tenants for the Device Association of a serial number.
- [`docs/FIRMWARE-STATE.md`](docs/FIRMWARE-STATE.md) - UEFI state and validated reset lifecycle.
- [`docs/DISCOVER-LINK-RESEARCH.md`](docs/DISCOVER-LINK-RESEARCH.md) - validated DeviceLinkManager contract, discovery and association-completion evidence.
- [`docs/REMOVE-ASSOCIATION.md`](docs/REMOVE-ASSOCIATION.md) - tenant-side Device Association removal.
- [`docs/CODE-SIGNING.md`](docs/CODE-SIGNING.md) - code signing policy, roles and release provenance.
- [`PRIVACY.md`](PRIVACY.md) - project privacy policy and administrator-initiated network transfers.
- [`TESTING.md`](TESTING.md) - validation matrix and live test observations.

## Validation

`0.5.1-preview1` includes the previously validated physical AMD64 Windows 11 / WinPE identity, firmware and cloud operations plus live Windows 11 validation of native device-side association completion and progress telemetry.

The controlled completion test started from tenant-side `preassociated` plus local firmware `2/4`. Native discovery returned the expected Intune enrollment discovery route and tenant ID. A single `ConfigureDeviceLinkAsync` call completed with HRESULT `0x00000000` and operation result `1`; local firmware transitioned to `4/4`, the association JWT became present and identity-matching, and the tenant-side record changed to `associated`. No retry, cleanup, reset, cloud deletion or reboot was performed.

Follow-up smoke tests confirmed that `Complete-WindowsDeviceLinkAssociation` and `Initialize-WindowsDeviceLink -CompleteAssociation` are idempotent on an already-associated device. Hardware-independent regression tests cover the public command contract, native DeviceLinkManager ABI surface, initializer opt-in boundary, health classifications, Graph operations and package safety under Windows PowerShell 5.1.

See [`TESTING.md`](TESTING.md) and [`docs/DISCOVER-LINK-RESEARCH.md`](docs/DISCOVER-LINK-RESEARCH.md) for the detailed validation evidence.

## Scope

Preview release line: `0.5.2-preview1`.

In scope: AMD64 Windows 11/WinPE, DeviceLink generation, official CSV export, Device Association query/preassociation/removal, native association discovery/completion on supported full Windows builds, local firmware inspection/reset, diagnostics/health, safe initialization, multiple authentication methods, webhook transport, Azure Automation receiver, and Azure Function receiver.

Not currently in scope: ARM64, Device Preparation policy assignment, classic Autopilot V1 management, automatic destructive repair, cryptographic association-JWT signature verification, or production support guarantees.

## Code signing policy

The SignPath Foundation application for WindowsDeviceLink was reviewed but not approved at this stage because the project does not yet have enough external adoption/visibility signals for the Foundation program. Preview releases therefore remain unsigned for now; the project can revisit code signing as community adoption grows or another suitable signing path becomes available.

WindowsDeviceLink does not redistribute or sign Microsoft's `Windows.Management.Service.dll`.

See [`docs/CODE-SIGNING.md`](docs/CODE-SIGNING.md) for the complete policy and [`PRIVACY.md`](PRIVACY.md) for the privacy policy.

## License

Project code is licensed under the MIT License. Microsoft binaries and Microsoft services remain subject to Microsoft's terms.
