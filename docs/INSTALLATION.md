# WindowsDeviceLink installation guide

This guide covers installation of WindowsDeviceLink from the PowerShell Gallery on Windows 11 and AMD64 Windows PE, including PowerShellGet, PackageManagement, prerelease handling, the WinPE publisher-check workaround, and the separately supplied Windows runtime DLL.

> [!IMPORTANT]
> WindowsDeviceLink is currently preview software. The published version documented here is `0.4.3-preview1`.

## Quick start - Windows 11

Run 64-bit Windows PowerShell 5.1 as administrator:

```powershell
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

Install-Module WindowsDeviceLink `
    -Repository PSGallery `
    -AllowPrerelease `
    -Force

Import-Module WindowsDeviceLink -Force

Get-Module WindowsDeviceLink |
    Select-Object Name,Version,Path

Test-WindowsDeviceLinkSupport
```

A normal Windows 11 installation does **not** require `Windows.Management.Service.dll` to be supplied separately. WindowsDeviceLink uses the Windows runtime already registered by the operating system.

## Understand PowerShellGet and PackageManagement first

`Install-Module`, `Save-Module`, `Find-Module` and related Gallery commands are provided by PowerShellGet. PowerShellGet uses PackageManagement for package-provider functionality.

Before troubleshooting WindowsDeviceLink, inspect what is actually available:

```powershell
Get-Module PowerShellGet,PackageManagement -ListAvailable |
    Sort-Object Name,Version -Descending |
    Select-Object Name,Version,Path
```

`-ListAvailable` shows modules installed on disk. It does **not** tell you which version is currently loaded in the PowerShell process.

Check the loaded versions separately:

```powershell
Get-Module PowerShellGet,PackageManagement |
    Select-Object Name,Version,Path
```

And check which module provides `Install-Module`:

```powershell
Get-Command Install-Module |
    Select-Object Name,Source,Version
```

This distinction matters when multiple PowerShellGet versions are present. A PowerShell session can have an older version loaded even when a newer version exists on disk, or vice versa.

## Prerelease support

WindowsDeviceLink `0.4.3-preview1` is a prerelease package. Install it with `-AllowPrerelease`:

```powershell
Install-Module WindowsDeviceLink `
    -Repository PSGallery `
    -AllowPrerelease
```

If `Install-Module` does not recognize `-AllowPrerelease`, the active PowerShellGet version is too old for this workflow. Inspect `Get-Command Install-Module` and the available PowerShellGet versions before continuing.

## TLS and PowerShell Gallery connectivity

The PowerShell Gallery requires TLS 1.2 or later. In older/minimal Windows PowerShell environments, explicitly selecting TLS 1.2 can avoid repository connectivity failures:

```powershell
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
```

Check repository registration:

```powershell
Get-PSRepository
```

The normal repository entry is `PSGallery`.

Check package discovery without installing anything:

```powershell
Find-Module WindowsDeviceLink `
    -Repository PSGallery `
    -AllowPrerelease |
    Select-Object Name,Version,Repository,PublishedDate
```

## NuGet provider

Some Windows PowerShell / PackageManagement environments prompt to install or update the NuGet provider when Gallery operations are first used.

Inspect providers with:

```powershell
Get-PackageProvider -ListAvailable
```

If PackageManagement explicitly reports that the NuGet provider is missing, install it from a trusted network connection:

```powershell
Install-PackageProvider NuGet -Force
```

Do not add provider-install commands to deployment automation unless the environment actually requires them. Prefer preparing WinPE with known PowerShellGet/PackageManagement dependencies in advance.

## Clean verification after installation

After installation:

```powershell
Import-Module WindowsDeviceLink -Force

Get-Module WindowsDeviceLink |
    Select-Object Name,Version,Path

Get-Command -Module WindowsDeviceLink |
    Sort-Object Name |
    Select-Object Name
```

For `0.4.3-preview1`, the public commands include:

```text
Connect-WindowsDeviceLink
Export-WindowsDeviceLinkCsv
Get-WindowsDeviceLink
Get-WindowsDeviceLinkFirmwareState
Register-WindowsDeviceLink
Remove-WindowsDeviceLinkAssociation
Reset-WindowsDeviceLinkFirmwareState
Test-WindowsDeviceLinkSupport
```

Then run:

```powershell
Test-WindowsDeviceLinkSupport | Format-List *
```

## AMD64 Windows PE

Windows PE needs more preparation than full Windows.

At a high level:

```text
AMD64 Windows PE
    -> Windows PowerShell support
    -> PackageManagement / PowerShellGet
    -> TLS 1.2 and PSGallery connectivity
    -> WindowsDeviceLink from PSGallery
    -> user-supplied Windows.Management.Service.dll
    -> Test-WindowsDeviceLinkSupport
```

### PowerShell support in WinPE

WindowsDeviceLink currently targets 64-bit Windows PowerShell 5.1-compatible environments. Build WinPE with the PowerShell-related optional components and their dependencies appropriate to the ADK/WinPE version you use.

The exact ADK optional-component package set can vary by Windows ADK release. Do not assume that a bare WinPE image contains PowerShellGet, PackageManagement, .NET support, networking cmdlets, or all certificate/trust functionality needed for Gallery operations.

After booting WinPE, inspect the environment rather than assuming it is correct:

```powershell
$PSVersionTable

Get-Module PowerShellGet,PackageManagement -ListAvailable |
    Select-Object Name,Version,Path

Get-Command Install-Module |
    Select-Object Name,Source,Version
```

### Validated WinPE PowerShellGet environment

The `0.4.3-preview1` Gallery smoke test was performed in AMD64 WinPE with PowerShellGet `2.2.5` active. Multiple versions were present in the image, including the older inbox `1.0.0.1`, so checking the active command source was important.

### Current WinPE install behavior for unsigned preview packages

During the validated `0.4.3-preview1` smoke test:

```powershell
Install-Module WindowsDeviceLink `
    -Repository PSGallery `
    -AllowPrerelease `
    -Force
```

failed in the tested WinPE with:

```text
InvalidModuleAuthenticodeSignature
```

The same Gallery package installed normally in full Windows 11.

Additional testing established:

- `Find-Module` worked in WinPE;
- `Save-Module` worked in WinPE;
- the saved Gallery package imported and ran correctly;
- WindowsDeviceLink `0.4.3-preview1` is not yet Authenticode signed;
- `Install-Module ... -SkipPublisherCheck` succeeded in the same WinPE environment.

This is therefore documented as a current WinPE installation limitation/workaround for the unsigned preview, not as a WindowsDeviceLink runtime failure.

### Recommended WinPE installation for 0.4.3-preview1

For the current unsigned preview, the directly validated installation command is:

```powershell
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

Install-Module WindowsDeviceLink `
    -Repository PSGallery `
    -AllowPrerelease `
    -SkipPublisherCheck `
    -Force
```

`-SkipPublisherCheck` bypasses PowerShellGet's publisher check. Use it only when you intentionally trust the package source and understand the tradeoff. It is **not** required for the validated Windows 11 installation.

The project plans to add trusted code signing in a later release and retest whether this WinPE workaround can then be removed.

### WinPE fallback: Save-Module + Import-Module

If `Install-Module` is undesirable or fails, `Save-Module` was also validated:

```powershell
New-Item -ItemType Directory -Path X:\Temp -Force | Out-Null

Save-Module WindowsDeviceLink `
    -Path X:\Temp `
    -Repository PSGallery `
    -AllowPrerelease `
    -Force
```

Then import the saved version explicitly:

```powershell
Import-Module 'X:\Temp\WindowsDeviceLink\0.4.3\WindowsDeviceLink.psd1' -Force
```

This still uses the package downloaded from PSGallery; it only avoids the `Install-Module` installation/publisher-check path.

## Windows.Management.Service.dll in WinPE

The PowerShell Gallery package intentionally does **not** redistribute Microsoft's `Windows.Management.Service.dll`.

A compatible AMD64 copy must be supplied by the user for DeviceLink runtime activation in WinPE.

Place it in the installed/saved module's Runtime directory:

```text
<WindowsDeviceLink module directory>\Runtime\Windows.Management.Service.dll
```

For example, when testing a saved Gallery package:

```text
X:\Temp\WindowsDeviceLink\0.4.3\Runtime\Windows.Management.Service.dll
```

Or pass the DLL explicitly when generating DeviceLink information:

```powershell
Get-WindowsDeviceLink `
    -WindowsManagementServicePath 'E:\Path\Windows.Management.Service.dll'
```

WindowsDeviceLink does not provide, download, or redistribute this DLL.

See [`../src/WindowsDeviceLink/Runtime/README.md`](../src/WindowsDeviceLink/Runtime/README.md).

## Verify WinPE support

Before generating DeviceLink data:

```powershell
Test-WindowsDeviceLinkSupport | Format-List *
```

Without the user-supplied DLL, a WinPE result can correctly report:

```text
Supported      : False
Environment    : WindowsPE
Architecture   : AMD64
ActivationMode : DirectDll
```

with a warning that `Windows.Management.Service.dll` was not found.

After supplying a compatible DLL, the validated result is expected to report support with direct-DLL activation.

## Firmware-state commands do not expose raw JWT data

After importing the module, firmware state can be inspected with:

```powershell
Get-WindowsDeviceLinkFirmwareState
```

For a non-destructive reset test:

```powershell
Reset-WindowsDeviceLinkFirmwareState -WhatIf
```

Do not run the reset without `-WhatIf` unless you intentionally want to reset the local DeviceLink identity/association firmware state.

## Troubleshooting

### `Install-Module` is not recognized

PowerShellGet is missing or not available in the current PowerShell session.

Check:

```powershell
Get-Module PowerShellGet -ListAvailable
```

### `-AllowPrerelease` is not recognized

The active `Install-Module` command is from an older PowerShellGet version.

Check:

```powershell
Get-Command Install-Module |
    Select-Object Name,Source,Version
```

### Multiple PowerShellGet versions are shown

This is normal on some Windows/WinPE images. `-ListAvailable` shows what exists on disk. `Get-Module PowerShellGet` shows what is loaded. `Get-Command Install-Module` shows which module/version supplies the command you are actually invoking.

### PSGallery cannot be reached

Check TLS and repository registration:

```powershell
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Get-PSRepository
Find-Module WindowsDeviceLink -Repository PSGallery -AllowPrerelease
```

### NuGet provider error

Inspect PackageManagement providers:

```powershell
Get-PackageProvider -ListAvailable
```

Only install/update the NuGet provider if PackageManagement reports that it is required.

### `InvalidModuleAuthenticodeSignature` in WinPE

For the current unsigned `0.4.3-preview1` package, this was reproduced with `Install-Module` in the tested AMD64 WinPE while the same package installed normally in Windows 11.

Validated workaround:

```powershell
Install-Module WindowsDeviceLink `
    -Repository PSGallery `
    -AllowPrerelease `
    -SkipPublisherCheck `
    -Force
```

Validated fallback:

```powershell
Save-Module WindowsDeviceLink `
    -Path X:\Temp `
    -Repository PSGallery `
    -AllowPrerelease `
    -Force
```

then import the saved manifest directly.

### `Test-WindowsDeviceLinkSupport` is False in WinPE

First check whether the runtime DLL exists:

```powershell
Get-Module WindowsDeviceLink |
    Select-Object Name,Version,Path
```

Locate that version's `Runtime` directory and verify:

```powershell
Test-Path '<module-directory>\Runtime\Windows.Management.Service.dll'
```

If the DLL is absent, supply a compatible Microsoft copy or pass `-WindowsManagementServicePath` explicitly.

### Module path points to a development checkout

For a Gallery smoke test, make sure `Get-Module WindowsDeviceLink` points to the installed/saved Gallery package rather than a GitHub checkout. Remove the currently loaded module and import the intended package explicitly if necessary.

## Security notes

- Prefer PSGallery over arbitrary download locations.
- Do not publish or log DeviceLink payloads, raw firmware JWT data, tenant secrets, API keys, certificate private keys, serial-number test data, or exported identity files.
- `-SkipPublisherCheck` reduces a publisher-verification control. It is a current WinPE workaround for the unsigned preview, not the preferred long-term state.
- WindowsDeviceLink plans to introduce trusted code signing and then retest the WinPE installation path without `-SkipPublisherCheck`.
- The separately supplied Microsoft DLL remains subject to Microsoft's licensing and redistribution terms.

## Related documentation

- [`FIRMWARE-STATE.md`](FIRMWARE-STATE.md)
- [`ONLINE-METHODS.md`](ONLINE-METHODS.md)
- [`REMOVE-ASSOCIATION.md`](REMOVE-ASSOCIATION.md)
- [`../TESTING.md`](../TESTING.md)
