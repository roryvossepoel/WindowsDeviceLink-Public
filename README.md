# WindowsDeviceLink

[![PowerShell Gallery Version](https://img.shields.io/powershellgallery/v/WindowsDeviceLink?include_prereleases&label=PowerShell%20Gallery)](https://www.powershellgallery.com/packages/WindowsDeviceLink)
[![PowerShell Gallery Downloads](https://img.shields.io/powershellgallery/dt/WindowsDeviceLink)](https://www.powershellgallery.com/packages/WindowsDeviceLink)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

PowerShell module for **Windows Autopilot Device Preparation Device Association** on physical Windows devices.

WindowsDeviceLink can generate the TPM-backed DeviceLink identity, export the official Windows `.devicelink.csv`, query/pre-associate/remove Intune Device Association records, inspect and reset local DeviceLink UEFI state, or send a DeviceLink payload to a webhook for centralized automation.

> [!IMPORTANT]
> This is preview / proof-of-concept software. The WinPE implementation uses an undocumented Windows Runtime interface and the Device Association flows use Microsoft Graph beta endpoints. These can change without notice.

## Current versions

The currently published PowerShell Gallery preview is `0.4.3-preview1`.

The `main` branch is now developing `0.4.4-preview1`. This preview intentionally separates local DeviceLink identity, local firmware state, and tenant-side Device Association operations. It is not published to the Gallery until its validation is complete.

## Mental model

Starting with `0.4.4-preview1`, the module exposes three different concepts explicitly:

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
```

`Get-WindowsDeviceLink -Online` has been removed from the development version. This is an intentional breaking preview change: `Get-WindowsDeviceLink` is now always local and a `Get-*` operation no longer creates cloud state.

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
- For firmware read/reset: elevated PowerShell with `SeSystemEnvironmentPrivilege` available.

Always start on a new system with:

```powershell
Test-WindowsDeviceLinkSupport
```

## Generate the local DeviceLink identity

```powershell
$deviceLink = Get-WindowsDeviceLink
$deviceLink | Format-List *
```

`Get-WindowsDeviceLink` does not authenticate to Microsoft Graph and does not change tenant-side state.

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

Registration is now deliberately a `Register-*` operation. The default DeviceCode client ID is Microsoft's well-known public Graph PowerShell client ID and is not a customer secret.

See [`docs/ONLINE-METHODS.md`](docs/ONLINE-METHODS.md) for all supported authentication methods.

## Query the tenant-side Device Association

```powershell
Get-WindowsDeviceLinkAssociation `
    -SerialNumber '<serial-number>' `
    -Method DeviceCode `
    -TenantId '<tenant-id>'
```

You can also query the exact record with `-AssociationId`. The cmdlet returns tenant-side association state and related Intune metadata; it does not read or change local firmware state.

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
Get-WindowsDeviceLinkAssociation
```

This identity-reset and re-preassociation sequence has been validated on physical AMD64 hardware.

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

See [`docs/WEBHOOK-SCHEMA-v1.md`](docs/WEBHOOK-SCHEMA-v1.md) and [`runbooks/README.md`](runbooks/README.md).

## Public commands

| Command | Purpose |
|---|---|
| `Get-WindowsDeviceLink` | Obtain the local DeviceLink identity; optionally export it. |
| `Get-WindowsDeviceLinkFirmwareState` | Read safe metadata for local DeviceLink UEFI state. |
| `Reset-WindowsDeviceLinkFirmwareState` | Reset and immediately verify local DeviceLink UEFI identity state. |
| `Get-WindowsDeviceLinkAssociation` | Query a tenant-side Intune Device Association by serial number or association ID. |
| `Register-WindowsDeviceLink` | Explicitly create a tenant-side pre-association from an existing local DeviceLink object, directly or through a webhook. |
| `Remove-WindowsDeviceLinkAssociation` | Remove a tenant-side Device Association record. |
| `Test-WindowsDeviceLinkSupport` | Validate runtime, architecture and DeviceLink activation. |
| `Export-WindowsDeviceLinkCsv` | Export an existing DeviceLink object using the Windows CSV API. |
| `Connect-WindowsDeviceLink` | Advanced Microsoft Graph SDK authentication helper. |

## Documentation

- [`docs/INSTALLATION.md`](docs/INSTALLATION.md) - Windows 11 and WinPE installation, PowerShellGet/PackageManagement and troubleshooting.
- [`docs/ONLINE-METHODS.md`](docs/ONLINE-METHODS.md) - cloud operations and authentication methods.
- [`docs/FIRMWARE-STATE.md`](docs/FIRMWARE-STATE.md) - UEFI state and validated reset lifecycle.
- [`docs/REMOVE-ASSOCIATION.md`](docs/REMOVE-ASSOCIATION.md) - tenant-side Device Association removal.
- [`docs/CODE-SIGNING.md`](docs/CODE-SIGNING.md) - code signing policy, roles and release provenance.
- [`PRIVACY.md`](PRIVACY.md) - project privacy policy and administrator-initiated network transfers.
- [`TESTING.md`](TESTING.md) - validation matrix and live test observations.

## Validation

The `0.4.3-preview1` Gallery package has been smoke-tested in Windows 11 OOBE and AMD64 WinPE, including registration, removal and the firmware reset/reboot/reassociation lifecycle.

The `0.4.4-preview1` development refactor must be revalidated before Gallery publication, particularly explicit registration and the new Device Association lookup cmdlet.

## Scope

Published Gallery preview: `0.4.3-preview1`.

Development version on `main`: `0.4.4-preview1`.

In scope: AMD64 Windows 11/WinPE, DeviceLink generation, official CSV export, Device Association query/preassociation/removal, local firmware inspection/reset, multiple authentication methods, webhook transport and optional Azure Automation receiver.

Not currently in scope: ARM64, Device Preparation policy assignment, classic Autopilot V1 management, or production support guarantees.

## Code signing policy

WindowsDeviceLink has applied for code signing through the SignPath Foundation. Until the application is approved and the signing integration is complete, preview releases may remain unsigned.

> **Free code signing provided by SignPath.io, certificate by SignPath Foundation.**

Official signed artifacts will be built from the public source repository through the project's automated GitHub Actions release workflow and must be explicitly approved for signing. WindowsDeviceLink does not redistribute or sign Microsoft's `Windows.Management.Service.dll`.

See [`docs/CODE-SIGNING.md`](docs/CODE-SIGNING.md) for the complete policy and [`PRIVACY.md`](PRIVACY.md) for the privacy policy.

## License

Project code is licensed under the MIT License. Microsoft binaries and Microsoft services remain subject to Microsoft's terms.
