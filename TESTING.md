# WindowsDeviceLink validation matrix

Last updated: 2026-09-06

The primary Windows Autopilot Device Preparation Device Association **pre-association** workflow has been validated successfully on both Windows 11 and AMD64 Windows PE.

## Confirmed working

| Area | Windows 11 | Windows PE |
|---|---:|---:|
| Runtime support detection | Pass | Pass |
| DeviceLink generation | Pass | Pass |
| Graph pre-association | Pass | Pass |
| Duplicate / HTTP 409 handling | Pass | Pass |
| Native `.devicelink.csv` generation | Pass | Pass |
| CSV accepted by Intune | Pass | Pass |
| Export to directory / root | Pass | Pass |
| Device-code authentication | Pass | Pass |
| Client-secret authentication | Pass | Pass |
| Existing access token | Pass | Pass |
| Environment-variable authentication | Pass | Pass |
| Certificate object | Pass | Pass |
| Certificate thumbprint | Pass | Pass |
| Certificate subject name | Pass | Pass |

## Notes

- Full Windows uses the registered Windows Runtime and system `Windows.Management.Service.dll`.
- WinPE uses direct DLL activation.
- The public repository and PowerShell Gallery package do **not** redistribute `Windows.Management.Service.dll`; WinPE users must provide a compatible copy themselves.
- Native CSV generation is used; WindowsDeviceLink does not reconstruct the CSV format.
- Device-code authentication uses direct OAuth 2.0 + Graph REST.
- The WinPE client-secret, access-token and environment-variable flows avoid Graph SDK bootstrapping where practical.

## Lower-priority validation

- Additional Windows 11 and WinPE builds.
- Additional OEMs/models.
- Managed identity on an Azure host.
- Additional file-path/failure edge cases.
- Non-Global Microsoft clouds.
