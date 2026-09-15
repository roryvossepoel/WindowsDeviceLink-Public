# WindowsDeviceLink validation matrix

Last updated: 2026-09-15

The primary Windows Autopilot Device Preparation Device Association workflow has been validated on physical AMD64 hardware across Windows 11 and AMD64 Windows PE.

## Confirmed direct functionality

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
| Device Association removal by serial number | Pass | Pass |
| Device Association removal by association ID | Pass | Not repeated |
| `Get-WindowsDeviceLinkFirmwareState` | Pass | Pass |
| Firmware reset operation | Pass | Pass |
| Firmware reset `-WhatIf` | Pass | Pass |
| Post-reset firmware verification | Pass | Pass |
| New identity after reset/reboot | Pass | Pass (reset), rebooted to Windows |
| Re-preassociation with new identity | Pass | Pass (identity created after WinPE reset) |
| Published PSGallery package import | Pass | Pass |
| Published package support probe | Pass | Pass with user-supplied DLL |
| Published package firmware read | Pass | Pass |
| Published package reset `-WhatIf` | Pass | Pass |

## Online method validation

`Get-WindowsDeviceLink -Online` requires an explicit `-Method`.

Validated parameter behavior:

| Scenario | Result |
|---|---|
| `-Online` without `-Method` | Pass - rejected before DeviceLink generation. |
| `-Method Webhook` without `-WebhookUri` | Pass - rejected with targeted error. |
| Method-incompatible parameter supplied | Pass - rejected with targeted error. |
| `-Method DeviceCode` without `-TenantId` | Pass - rejected with targeted error. |
| `-Method ClientSecret` with missing required input | Pass - rejected with targeted error. |
| `-Method AccessToken` without token | Pass - rejected with targeted error. |

The main Windows 11 registration methods were repeated successfully using DeviceCode, ClientSecret, AccessToken, EnvironmentVariable, Certificate, CertificateThumbprint and CertificateSubjectName. Each also produced the targeted HTTP 409 duplicate error when appropriate.

ClientSecret and EnvironmentVariable use native OAuth + direct Graph REST on both Windows and WinPE and do not require `Microsoft.Graph.Authentication` for those methods.

## DeviceCode public client ID

The default DeviceCode client ID is:

```text
14d82eec-204b-4c2f-b7e8-296a70dab67e
```

This is Microsoft's well-known public Graph PowerShell / Graph Command Line Tools client ID. It is intentionally public and is not a customer-specific app registration, secret, certificate, or tenant identifier.

## Device Association removal validation

The Device Association removal operation was derived from the Intune admin center request and independently verified as:

```text
DELETE /deviceManagement/tenantAssociatedDevices/{associationId}
```

Validated:

- standalone DELETE of a `preassociated` record;
- removal by serial number on Windows 11;
- serial-number lookup resolving the correct association ID;
- removal by association ID on Windows 11;
- successful removal result with `Removed = True`;
- removal by serial number from AMD64 WinPE.

The cmdlet targets Device Association records (`tenantAssociatedDevices`) and does **not** use the classic Autopilot V1 deletion API.

## Firmware lifecycle validation

Validated UEFI namespace:

```text
{B3DE75DA-819C-4FD5-9F01-C3D49E8CBBD7}
```

Validated variables:

```text
DeviceLinkId
DeviceLinkJwtCompressed
DeviceLinkJwtLastWrite
DeviceLinkCreationTimeUtc
```

The raw `DeviceLinkJwtCompressed` value is treated as sensitive and must not be logged or published.

### Observed states

- Clean baseline: all four variables absent.
- After DeviceLink generation: `DeviceLinkId` and `DeviceLinkCreationTimeUtc` present; JWT variables absent.
- After preassociation: same local base identity state; JWT variables still absent.
- Fully associated Windows device: all four variables present.
- Server-side association removal: local firmware state remains until explicitly reset.

### AMD64 WinPE lifecycle

Validated in WinPE:

1. read clean firmware state;
2. generate DeviceLink;
3. verify base identity variables appeared;
4. create Graph preassociation;
5. remove the server-side association;
6. reset local DeviceLink firmware variables;
7. verify all four variables absent afterward.

### Full Windows reset and identity regeneration

A controlled end-to-end test established that the reset removes the old identity rather than temporarily hiding it:

1. Intune contained no Device Association record for the test device;
2. the current `DeviceLinkId` was fingerprinted with SHA-256 and creation-time bytes were recorded without publishing the raw ID;
3. all four UEFI variables were removed and immediately verified absent with Win32 error `203`;
4. the device was restarted normally;
5. no `Get-WindowsDeviceLink` command was run before the post-boot firmware check;
6. Windows had recreated `DeviceLinkId` and `DeviceLinkCreationTimeUtc`; both JWT variables remained absent;
7. the post-boot DeviceLinkId SHA-256 fingerprint differed from the pre-reset fingerprint and the creation time changed;
8. `Get-WindowsDeviceLink` returned the new identity;
9. the new identity was successfully pre-associated;
10. Intune showed a new `Pre-associated` record for the same physical device;
11. after the subsequent Windows restart, Intune reported the new Device Association as `Associated` and all four known DeviceLink firmware variables were present again.

Conclusion: the reset removes the old local DeviceLink identity. Windows can generate a **new** base identity after reboot. The reappearance of `DeviceLinkId` and `DeviceLinkCreationTimeUtc` is therefore expected regeneration, not restoration of the removed identity or tenant association.

## 0.4.3 firmware cmdlet validation

The firmware implementation has been exercised directly in both full Windows and AMD64 WinPE. The published API uses:

```powershell
Get-WindowsDeviceLinkFirmwareState
Reset-WindowsDeviceLinkFirmwareState
```

Validated behavior includes safe metadata-only reads, `ShouldProcess` / `-WhatIf`, noninteractive reset with `-Confirm:$false`, `-PassThru`, skipping already absent variables, and immediate post-reset verification.

`Reset-WindowsDeviceLinkFirmwareState` replaced the earlier development-only `Clear-WindowsDeviceLinkFirmwareState` name before Gallery publication because reset more accurately describes the lifecycle: the old identity is removed and Windows may later create a new identity.

## Published 0.4.3-preview1 Gallery smoke test

The actual package published to PSGallery was tested after publication, rather than relying only on the repository checkout/build output.

### Windows 11 OOBE

Validated from the installed Gallery package:

- `Install-Module WindowsDeviceLink -Repository PSGallery -AllowPrerelease -Force` succeeded;
- module version/path confirmed the Gallery installation rather than a development checkout;
- `Test-WindowsDeviceLinkSupport` passed;
- `Get-WindowsDeviceLinkFirmwareState` passed on the associated test device;
- all four known firmware variables were present in the associated state;
- `Reset-WindowsDeviceLinkFirmwareState -WhatIf` correctly invoked `ShouldProcess` without modifying state.

### AMD64 Windows PE

The same published package was then tested in WinPE.

Observed environment included PowerShellGet `2.2.5` as the active `Install-Module` provider, with older PowerShellGet/PackageManagement versions also present on disk.

Validated findings:

- normal `Install-Module ... -AllowPrerelease -Force` failed in the tested WinPE with `InvalidModuleAuthenticodeSignature`;
- `Find-Module` and `Save-Module` succeeded;
- the saved PSGallery package imported directly and reported version `0.4.3`;
- the current preview package is not Authenticode signed;
- `Install-Module ... -AllowPrerelease -SkipPublisherCheck -Force` succeeded;
- without `Windows.Management.Service.dll`, `Test-WindowsDeviceLinkSupport` correctly reported WinPE/AMD64/direct-DLL mode but unsupported because the DLL was absent;
- after a compatible user-supplied Microsoft DLL was placed in the module `Runtime` directory, the support probe succeeded;
- `Get-WindowsDeviceLinkFirmwareState` returned the four known variables from the Gallery package;
- `Reset-WindowsDeviceLinkFirmwareState -WhatIf` worked and did not modify state.

The current WinPE `-SkipPublisherCheck` requirement is documented as a workaround for the unsigned preview and will be retested after trusted code signing is introduced.

See [`docs/INSTALLATION.md`](docs/INSTALLATION.md) for the supported installation routes and troubleshooting guidance.

## Webhook validation

The webhook route has been validated end-to-end on Windows 11, including HTTPS POST, schema/request ID headers, optional API-key header, tenant routing, Azure Automation PowerShell 7.4, Managed Identity Graph authentication, successful preassociation and targeted duplicate handling.

See [`docs/WEBHOOK-SCHEMA-v1.md`](docs/WEBHOOK-SCHEMA-v1.md).

## Notes

- Full Windows uses the registered Windows Runtime and system `Windows.Management.Service.dll`.
- WinPE uses direct DLL activation.
- The public repository and PowerShell Gallery package do **not** redistribute `Windows.Management.Service.dll`; WinPE users must provide a compatible copy themselves.
- Native CSV generation is used; WindowsDeviceLink does not reconstruct the CSV format.
- Firmware access requires `SeSystemEnvironmentPrivilege`; the firmware cmdlets enable it in the current process.
- PowerShellGet `Save-Module` does not exercise the same install/publisher-check path as `Install-Module`; both routes were tested separately in WinPE.

## Published preview

`WindowsDeviceLink 0.4.3-preview1` has been published to the PowerShell Gallery after successful package build and release validation in GitHub Actions, followed by live smoke tests of the published package in Windows 11 OOBE and AMD64 WinPE.

## Remaining validation / future work

- Trusted code signing; SignPath Foundation is the planned route to investigate.
- Retest normal WinPE `Install-Module` without `-SkipPublisherCheck` after signing.
- Additional authentication methods for association removal.
- Webhook transport in AMD64 WinPE.
- Second target tenant through the same webhook/runbook routing table.
- Additional Windows 11 / WinPE builds and OEMs/models.
- Non-Global Microsoft clouds.
