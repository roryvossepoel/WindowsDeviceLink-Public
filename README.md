# WindowsDeviceLink

PowerShell module for **pre-associating physical Windows devices with a Microsoft Intune tenant for Windows Autopilot Device Preparation Device Association**.

WindowsDeviceLink can generate the TPM-backed DeviceLink identity from a device, export the official Windows `.devicelink.csv`, or submit the DeviceLink directly to Intune through Microsoft Graph before the device enrolls.

> [!IMPORTANT]
> This is preview / proof-of-concept software. The WinPE implementation uses an undocumented Windows Runtime interface and the online registration uses a Microsoft Graph beta endpoint. Both can change without notice.

## What this module is for

Windows Autopilot Device Preparation Device Association introduces a pre-association step for physical Windows devices. WindowsDeviceLink focuses on the first two parts of that process:

1. Obtain the DeviceLink information from the physical device.
2. Pre-associate the device with the tenant in Intune.

The association itself is completed later by Windows during OOBE.

This is **not** classic Windows Autopilot V1 hardware-hash registration.

## What the module can do

- Generate DeviceLink information on AMD64 Windows 11.
- Generate DeviceLink information in AMD64 Windows PE.
- Export the official Windows-generated `.devicelink.csv` format.
- Pre-associate the device directly in Intune using Microsoft Graph.
- Use device-code authentication.
- Use app-registration authentication with client secret, certificate, access token, or environment variables.
- Detect whether the current Windows / WinPE environment can access the DeviceLink runtime.

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
- For online pre-association: Microsoft Graph permission `DeviceManagementServiceConfig.ReadWrite.All`.
- For WinPE: a compatible user-supplied `Windows.Management.Service.dll`.

## Quick start

```powershell
Import-Module .\src\WindowsDeviceLink\WindowsDeviceLink.psd1 -Force

Test-WindowsDeviceLinkSupport
Get-WindowsDeviceLink
```

## Generate DeviceLink information

```powershell
$deviceLink = Get-WindowsDeviceLink
$deviceLink | Format-List *
```

The DeviceLink payload contains device identity information. Do not publish DeviceLink payloads, exported CSVs, serial numbers, SMBIOS UUIDs, or Link IDs.

## Export the official DeviceLink CSV

```powershell
Get-WindowsDeviceLink -OutputDirectory 'C:\DeviceLink'
```

Windows itself generates the CSV through `ExportDeviceLinkInfoCsvAsync`. WindowsDeviceLink does not reconstruct or re-encode the CSV.

Example filename:

```text
ABC1234_Contoso-Computers_Model-123_2026-09-06.devicelink.csv
```

## Pre-associate directly in Intune

```powershell
Get-WindowsDeviceLink `
    -Online `
    -TenantId '<tenant-id>' `
    -UseDeviceCode
```

The module submits the DeviceLink to:

```text
POST /beta/deviceManagement/tenantAssociatedDevices/importTenantAssociatedDevice
```

A successful response normally returns `AssociationState : preassociated`.

### Export and pre-associate in one command

```powershell
Get-WindowsDeviceLink `
    -OutputDirectory 'C:\DeviceLink' `
    -Online `
    -TenantId '<tenant-id>' `
    -UseDeviceCode
```

## Authentication validation

The following methods have been validated successfully on both Windows 11 and AMD64 Windows PE:

| Method | Windows 11 | Windows PE |
|---|---:|---:|
| Device code | Yes | Yes |
| Client secret | Yes | Yes |
| Existing access token | Yes | Yes |
| Environment variables | Yes | Yes |
| Certificate object | Yes | Yes |
| Certificate thumbprint | Yes | Yes |
| Certificate subject name | Yes | Yes |

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

Current preview: `0.3.12-preview1`.

In scope:

- AMD64 Windows 11;
- AMD64 Windows PE;
- DeviceLink generation;
- official DeviceLink CSV export;
- Windows Autopilot Device Preparation Device Association pre-association;
- delegated device-code and app-registration authentication.

Not currently in scope:

- ARM64;
- Device Preparation policy assignment;
- association completion / UEFI write operations;
- association removal / decommissioning;
- production support guarantees.

## License

Project code is licensed under the MIT License. Microsoft binaries and Microsoft services remain subject to Microsoft's terms.
