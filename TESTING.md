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
| `Clear-WindowsDeviceLinkFirmwareState` | Pass | Pass |
| Firmware clear `-WhatIf` | Pass | Pass |
| Post-clear firmware verification | Pass | Pass |
| Reboot regeneration observation | Pass | Pass (clear), rebooted to Windows |

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
- `Remove-WindowsDeviceLinkAssociation -SerialNumber ... -Method DeviceCode` on Windows 11;
- serial-number lookup resolving the correct association ID;
- `Remove-WindowsDeviceLinkAssociation -AssociationId ... -Method DeviceCode` on Windows 11;
- successful removal result with `Removed = True`;
- `Remove-WindowsDeviceLinkAssociation -SerialNumber ... -Method DeviceCode` from AMD64 WinPE.

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

### Clean baseline

On a clean test device all four variables were absent.

### DeviceLink generation

After `Get-WindowsDeviceLink`, local firmware contained `DeviceLinkId` and `DeviceLinkCreationTimeUtc`. The JWT variables were absent. This behavior was observed in AMD64 WinPE.

### Preassociation

Creating a server-side preassociation from WinPE did not add the JWT variables. Local state remained `DeviceLinkId` plus `DeviceLinkCreationTimeUtc`.

### Fully associated device

On a fully associated Windows device, all four variables were present.

### Server-side removal does not clear local firmware

Removing the server-side Device Association record did not remove local firmware state. Deleting only `DeviceLinkId` was insufficient on the fully associated test device because the remaining DeviceLink state allowed it to reappear.

### AMD64 WinPE lifecycle

The native UEFI mechanism and module workflow were validated in WinPE:

1. read clean firmware state;
2. generate DeviceLink;
3. verify `DeviceLinkId` and `DeviceLinkCreationTimeUtc` appeared;
4. create Graph preassociation;
5. verify firmware state remained unchanged;
6. remove the server-side association from WinPE;
7. delete the local DeviceLink firmware variables from WinPE;
8. verify all four known variables were absent afterward.

### Full Windows cleanup and reboot regeneration

The `0.4.3` firmware cmdlets were then exercised directly in full Windows on the same physical device.

Validated sequence:

1. after boot, `Get-WindowsDeviceLinkFirmwareState` returned `DeviceLinkId` and `DeviceLinkCreationTimeUtc` as present and both JWT variables as absent;
2. Intune contained no Device Association record for the device;
3. `Clear-WindowsDeviceLinkFirmwareState -Confirm:$false -PassThru` removed the two present variables;
4. automatic post-clear verification returned all four variables absent with Win32 error `203`;
5. the device was restarted normally;
6. no `Get-WindowsDeviceLink` command was run after restart;
7. `Get-WindowsDeviceLinkFirmwareState` again returned `DeviceLinkId` and `DeviceLinkCreationTimeUtc` as present while both JWT variables remained absent;
8. `Clear-WindowsDeviceLinkFirmwareState -WhatIf` in full Windows correctly invoked `ShouldProcess` without modifying state.

This demonstrates on the tested device that Windows can recreate the base DeviceLink identity variables after a normal boot even when there is no server-side Device Association record. `DeviceLinkId` and `DeviceLinkCreationTimeUtc` alone must therefore not be treated as proof of tenant association.

The safe firmware-state cmdlet intentionally does not return raw values, so this regression did not determine whether the regenerated `DeviceLinkId` is identical to the pre-clear value or newly generated.

## 0.4.3 firmware cmdlet validation

The new cmdlets have now been exercised directly in both full Windows and AMD64 WinPE.

Validated:

- `Get-WindowsDeviceLinkFirmwareState` returns environment, namespace, name, presence, size and Win32 error metadata;
- raw firmware contents are not exposed;
- empty state returns `Present = False` and Win32 error `203`;
- `Clear-WindowsDeviceLinkFirmwareState -WhatIf` honors `ShouldProcess` in Windows and WinPE;
- `Clear-WindowsDeviceLinkFirmwareState -Confirm:$false -PassThru` removes present variables;
- already absent variables are skipped;
- post-removal state is automatically verified;
- `-PassThru` returns the verified state;
- successful cleanup reports `DeviceLink firmware state cleared and verified successfully.`

## Webhook validation

The webhook route has been validated end-to-end on Windows 11, including HTTPS POST, schema/request ID headers, optional API-key header, tenant routing, Azure Automation PowerShell 7.4, Managed Identity Graph authentication, successful preassociation and targeted duplicate handling.

See [`docs/WEBHOOK-SCHEMA-v1.md`](docs/WEBHOOK-SCHEMA-v1.md).

## Notes

- Full Windows uses the registered Windows Runtime and system `Windows.Management.Service.dll`.
- WinPE uses direct DLL activation.
- The public repository and PowerShell Gallery package do **not** redistribute `Windows.Management.Service.dll`; WinPE users must provide a compatible copy themselves.
- Native CSV generation is used; WindowsDeviceLink does not reconstruct the CSV format.
- Firmware access requires `SeSystemEnvironmentPrivilege`; the firmware cmdlets enable it in the current process.
- Immediate firmware clear verification and persistent absence across future Windows boots are different conditions.

## Current 0.4.3-preview1 development focus

The live firmware cmdlet regression is now complete on the tested Windows 11 and AMD64 WinPE paths. Before publishing `0.4.3-preview1`, remaining release work is packaging validation, final documentation/cmdlet-name review, and a final public-repository secret/identifier scan.

## Remaining validation

- Additional authentication methods for association removal.
- Webhook transport in AMD64 WinPE.
- Second target tenant through the same webhook/runbook routing table.
- Additional Windows 11 / WinPE builds and OEMs/models.
- Determine whether regenerated `DeviceLinkId` is identical or newly generated, if a safe test method is added.
- Non-Global Microsoft clouds.
