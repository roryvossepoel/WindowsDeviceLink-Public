# WindowsDeviceLink validation matrix

Last updated: 2026-09-14

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
| Firmware-state read | Pass | Pass |
| Firmware-state clear | Pass | Pass |
| Post-clear firmware verification | Pass | Pass |

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

After `Get-WindowsDeviceLink`, local firmware contained:

```text
DeviceLinkId
DeviceLinkCreationTimeUtc
```

The JWT variables were absent.

This behavior was observed in AMD64 WinPE.

### Preassociation

Creating a server-side preassociation from WinPE did not add the JWT variables. Local state remained:

```text
DeviceLinkId
DeviceLinkCreationTimeUtc
```

### Fully associated device

On a fully associated Windows device, all four variables were present:

```text
DeviceLinkId
DeviceLinkJwtCompressed
DeviceLinkJwtLastWrite
DeviceLinkCreationTimeUtc
```

### Server-side removal does not clear local firmware

Removing the server-side Device Association record did not remove local firmware state.

Deleting only `DeviceLinkId` was insufficient on a fully associated device because the remaining DeviceLink state allowed it to reappear.

### Full Windows cleanup

Deleting all four known variables succeeded in full Windows. Immediate verification showed all four absent with Win32 error `203` (`ERROR_ENVVAR_NOT_FOUND`).

### AMD64 WinPE cleanup

The same native UEFI read/write mechanism was validated in WinPE:

1. read clean firmware state;
2. generate DeviceLink;
3. verify `DeviceLinkId` and `DeviceLinkCreationTimeUtc` appeared;
4. create Graph preassociation;
5. verify firmware state remained unchanged;
6. remove the server-side association from WinPE;
7. delete the local DeviceLink firmware variables from WinPE;
8. verify all four known variables were absent afterward.

This establishes AMD64 WinPE as a viable control point for Device Association cleanup and tenant-move workflows.

## 0.4.3 firmware cmdlet validation

The new firmware cmdlets were exercised directly in AMD64 WinPE, not only through the earlier test scripts.

Validated:

- `Get-WindowsDeviceLinkFirmwareState` returns the four known variables with environment, namespace, presence, size and Win32 error metadata;
- the cmdlet does not expose raw firmware contents;
- empty state returns `Present = False` and Win32 error `203` for all four variables;
- `Clear-WindowsDeviceLinkFirmwareState -WhatIf` honors `ShouldProcess` and performs no write;
- `Clear-WindowsDeviceLinkFirmwareState -Confirm:$false -PassThru` removes present DeviceLink firmware variables;
- the clear cmdlet skips variables that are already absent;
- the clear cmdlet verifies post-removal state automatically;
- `-PassThru` returned all four variables as absent after cleanup;
- successful cleanup reported `DeviceLink firmware state cleared and verified successfully.`

The new cmdlets therefore have a successful live regression in AMD64 WinPE. A final live regression of these cmdlets in full Windows remains desirable before publishing `0.4.3-preview1`.

## Webhook validation

The webhook route has been validated end-to-end on Windows 11.

Confirmed:

- HTTPS POST;
- schema and request ID headers;
- optional `X-WindowsDeviceLink-Key`;
- API key excluded from JSON body;
- optional tenant routing;
- Azure Automation PowerShell 7.4 receiver;
- API-key validation;
- Managed Identity Graph authentication;
- successful preassociation;
- targeted duplicate / HTTP 409 handling.

See [`docs/WEBHOOK-SCHEMA-v1.md`](docs/WEBHOOK-SCHEMA-v1.md).

## Notes

- Full Windows uses the registered Windows Runtime and system `Windows.Management.Service.dll`.
- WinPE uses direct DLL activation.
- The public repository and PowerShell Gallery package do **not** redistribute `Windows.Management.Service.dll`; WinPE users must provide a compatible copy themselves.
- Native CSV generation is used; WindowsDeviceLink does not reconstruct the CSV format.
- Firmware access requires `SeSystemEnvironmentPrivilege`; the firmware cmdlets enable it in the current process.

## Current 0.4.3-preview1 development focus

Development adds:

```powershell
Get-WindowsDeviceLinkFirmwareState
Clear-WindowsDeviceLinkFirmwareState
```

Both include comment-based help and work in the validated AMD64 WinPE path. Before publishing `0.4.3-preview1`, repeat the new cmdlets in full Windows, run packaging checks, review the public documentation, and perform a final public-repository secret/identifier scan.

## Remaining validation

- Live regression of the new firmware cmdlets on Windows 11.
- Additional authentication methods for association removal.
- Webhook transport in AMD64 WinPE.
- Second target tenant through the same webhook/runbook routing table.
- Additional Windows 11 / WinPE builds and OEMs/models.
- Non-Global Microsoft clouds.
