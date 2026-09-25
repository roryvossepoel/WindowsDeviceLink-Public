# Windows PE workflow and support boundaries

WindowsDeviceLink supports a practical Windows PE workflow for **pre-associating a physical device before Windows 11 is installed**.

The important distinction is between:

1. generating the local TPM-backed DeviceLink identity;
2. creating the tenant-side pre-association;
3. completing the device-side association.

In a normal imaging scenario, Windows PE only needs to perform steps 1 and 2. Windows 11 OOBE can complete step 3 automatically after installation.

## Recommended deployment flow

```text
Windows PE
    |
    |  Bring Your Own DLL (BYO-DLL)
    |  administrator-supplied Windows.Management.Service.dll
    v
Generate/read DeviceLink identity
    |
    v
Create Intune Device Association pre-association
    |
    v
Install Windows 11
    |
    v
Windows 11 OOBE + network
    |
    v
Windows automatically completes Device Association
    |
    v
Associated / ready for enrollment
```

Microsoft documents that a pre-associated device automatically completes Device Association when it connects to a network during OOBE. A technician can also trigger association manually from the OOBE Autopilot menu.

For this reason, native association completion inside Windows PE is **not required for the normal preinstallation workflow**.

## Bring Your Own DLL (BYO-DLL)

Windows PE does not ship `Windows.Management.Service.dll` in the validated stock AMD64 image.

WindowsDeviceLink calls the compatibility path for this limitation **Bring Your Own DLL (BYO-DLL)**. The module and PowerShell Gallery package do not include, download or redistribute this Microsoft binary. `BYO-DLL` is used instead of `BYOD` to avoid confusion with the established *Bring Your Own Device* term.

BYO-DLL applies only when the target environment doesn't already provide a usable registered DeviceLink runtime:

- **Full Windows 11:** no BYO-DLL action is needed. Windows provides and registers the runtime.
- **Validated stock AMD64 WinPE:** the administrator supplies a compatible Microsoft-provided DLL.

The same compatible Microsoft binary used by Windows 11 can be activated directly in WinPE. Microsoft has not documented whether or when WinPE will include and register the DeviceLink runtime natively. WindowsDeviceLink therefore describes BYO-DLL as the current compatibility route without claiming that it is temporary or permanent. If native WinPE support appears later, the runtime-selection behavior can be reassessed.

Administrators may supply a compatible Microsoft-provided copy explicitly:

```powershell
Get-WindowsDeviceLink `
    -WindowsManagementServicePath 'E:\Windows.Management.Service.dll'
```

The runtime can also be placed in the module `Runtime` directory when appropriate for a controlled deployment image.

The administrator remains responsible for obtaining and using the Microsoft binary in accordance with Microsoft's licensing terms.

## Windows 11 OOBE version requirement

Use current Windows 11 installation media and service it with current cumulative updates before first boot. Microsoft explicitly recommends verifying that installation media contains the minimum required updates for Windows Autopilot device preparation.

The end-to-end WindowsDeviceLink validation on physical hardware produced these results:

| Windows 11 25H2 build | Observed Device Association OOBE behavior |
|---|---|
| `26200.9168` | Device Association wasn't picked up; generic OOBE was shown and the tenant record remained pre-associated. |
| `26200.9457` after `KB5129195` | OOBE automatically completed Device Association, local firmware changed from `2/4` to `4/4`, the tenant record changed to associated, and the assigned Device Preparation policy was used. |

These are project validation results, not a claim that `KB5129195` itself is the permanent minimum. For deployment media, use the latest supported cumulative update rather than pinning an imaging workflow to this single KB.

Microsoft requirements: <https://learn.microsoft.com/autopilot/device-preparation/requirements>

## What has been validated in AMD64 Windows PE

With an administrator-supplied compatible `Windows.Management.Service.dll`, the following has been validated on physical AMD64 hardware:

- direct DLL activation;
- DeviceLink runtime activation;
- TPM-backed DeviceLink identity generation/readout;
- Windows-generated DeviceLink CSV export;
- local DeviceLink firmware-state inspection;
- local DeviceLink firmware reset;
- tenant-side Device Association lookup;
- tenant-side pre-association;
- tenant-side Device Association removal;
- runtime and health diagnostics.

This makes Windows PE suitable for preparing a device before Windows installation.

## Native discovery and completion in Windows PE

WindowsDeviceLink research also validated that the DeviceLinkManager runtime can be directly activated in Windows PE.

However, native discovery currently stops at:

```text
RequestDiscoveryUrlAsync
HRESULT 0x81036C00
```

The following stages succeed before that failure:

```text
Load Windows.Management.Service.dll       OK
Activate DeviceLinkUtilities              OK
GetDeviceLinkInfoAsync                    OK
Activate DeviceLinkManager                OK
GetConfigureDeviceLinkResult              OK
RequestDiscoveryUrlAsync                  FAIL 0x81036C00
```

Windows PE intentionally contains a smaller Windows component set than full Windows. The research environment lacks several services, registrations and operating-system components that exist on full Windows. The project therefore does not attempt to transform Windows PE into a full Windows runtime by copying arbitrary system components.

The exact internal dependency represented by `0x81036C00` is not publicly documented.

### Current support statement

Native DeviceLink discovery/completion in Windows PE is therefore **experimental and not currently treated as a supported workflow**.

This does not block the normal imaging scenario:

```text
WinPE pre-association
        |
        v
Install Windows 11
        |
        v
OOBE completes association automatically
```

Full Windows remains the validated environment for explicitly invoking native DeviceLink discovery and `ConfigureDeviceLinkAsync` from WindowsDeviceLink.

## Example: pre-associate from Windows PE

Generate the identity:

```powershell
$deviceLink = Get-WindowsDeviceLink `
    -WindowsManagementServicePath 'E:\Windows.Management.Service.dll'
```

Then create the tenant-side pre-association:

```powershell
$deviceLink | Register-WindowsDeviceLink `
    -Method DeviceCode `
    -TenantId '<tenant-id>'
```

Expected state:

```text
Local firmware:       2/4
Tenant association:   preassociated
```

At this point the intended Windows PE task is complete. Install a sufficiently current Windows 11 image and allow OOBE to continue the Device Association lifecycle.

## Cleaning up from Windows PE

Tenant-side and local state remain separate.

Remove only the tenant-side Device Association:

```powershell
Remove-WindowsDeviceLinkAssociation `
    -SerialNumber '<serial-number>' `
    -Method DeviceCode `
    -TenantId '<tenant-id>'
```

Reset only the local DeviceLink firmware state:

```powershell
Reset-WindowsDeviceLinkFirmwareState
```

A local reset changes the device identity lifecycle and should be performed deliberately. It does not remove the tenant-side record automatically.

## Support matrix

| Capability | Full Windows | AMD64 WinPE + supplied runtime |
|---|---:|---:|
| Runtime validation | Yes | Yes |
| Generate/read DeviceLink identity | Yes | Yes |
| Export DeviceLink CSV | Yes | Yes |
| Inspect local firmware state | Yes | Yes |
| Reset local firmware state | Yes | Yes |
| Query tenant Device Association | Yes | Yes |
| Create pre-association | Yes | Yes |
| Remove tenant Device Association | Yes | Yes |
| Native discovery | Yes | Experimental / currently fails at `RequestDiscoveryUrlAsync` |
| Native completion / `ConfigureDeviceLinkAsync` | Yes | Not currently supported |
| Automatic association during Windows 11 OOBE | Yes | Happens after Windows installation |

## Why this split is intentional

Windows PE is primarily a deployment environment. Its most useful Device Association role is to establish the device identity and pre-association **before** Windows 11 is installed.

Windows 11 OOBE is the native environment designed to complete Device Association.

WindowsDeviceLink therefore treats:

- **WinPE** as a preparation and lifecycle-management environment;
- **full Windows / OOBE** as the validated native association-completion environment.

This boundary keeps the WinPE implementation useful without requiring unsupported transplantation of Windows components.
