# WinPE runtime requirement

WindowsDeviceLink supports Windows PE, but the PowerShell Gallery package intentionally does **not** include `Windows.Management.Service.dll`.

`Windows.Management.Service.dll` is a Microsoft Windows binary. Redistribution rights for this specific file have not been confirmed, so WindowsDeviceLink does not redistribute it in public packages.

## Windows 11

No action is required. On full Windows 11, WindowsDeviceLink uses the registered Windows Runtime and the system copy at:

```text
C:\Windows\System32\Windows.Management.Service.dll
```

## Windows PE

For WinPE, provide a compatible AMD64 copy yourself.

The easiest option is to place the file here after installing/downloading the module:

```text
<module-root>\Runtime\Windows.Management.Service.dll
```

You can then run:

```powershell
Test-WindowsDeviceLinkSupport
Get-WindowsDeviceLink
```

Alternatively, leave the Runtime folder empty and provide the DLL explicitly:

```powershell
Test-WindowsDeviceLinkSupport -WindowsManagementServicePath 'X:\Path\Windows.Management.Service.dll'

Get-WindowsDeviceLink -WindowsManagementServicePath 'X:\Path\Windows.Management.Service.dll'
```

Use a DLL from a properly licensed Windows source and ensure the architecture/build is compatible with the WinPE environment. WindowsDeviceLink validates the file signature where possible and performs a native activation probe before using it.
