# Remove Device Association records

`Remove-WindowsDeviceLinkAssociation` removes a Windows Autopilot Device Preparation Device Association record from Microsoft Intune.

The cmdlet targets the Device Association resource:

```text
DELETE /deviceManagement/tenantAssociatedDevices/{associationId}
```

This is **not** the classic Autopilot V1 `windowsAutopilotDeviceIdentities` deletion API.

## Recommended usage: serial number

For normal use, identify the record by device serial number:

```powershell
Remove-WindowsDeviceLinkAssociation `
    -SerialNumber '<serial-number>' `
    -Method DeviceCode
```

The cmdlet resolves the matching Device Association record, obtains its association ID, and deletes that exact record.

If multiple records match the serial number, the cmdlet stops and asks you to use `-AssociationId` instead of guessing.

## Advanced usage: association ID

If the Device Association record ID is already known, delete it directly:

```powershell
Remove-WindowsDeviceLinkAssociation `
    -AssociationId '<association-id>' `
    -Method DeviceCode
```

The association ID is the `Id` returned by the `tenantAssociatedDevice` object after a successful pre-association.

## Authentication

The removal cmdlet supports the same direct authentication families used by the module:

- `DeviceCode`
- `Interactive`
- `ClientSecret`
- `AccessToken`
- `Certificate`
- `CertificateThumbprint`
- `CertificateSubjectName`
- `EnvironmentVariable`
- `ManagedIdentity`

`TenantId` is optional for delegated `DeviceCode` and `Interactive` authentication. Supply it when you need to target a specific tenant, especially in multi-tenant or guest-account scenarios. App-only methods such as certificate authentication remain tenant-specific. `EnvironmentVariable` obtains the tenant from `AZURE_TENANT_ID`.

## Result

A successful removal returns an object similar to:

```text
AssociationId : <association-id>
SerialNumber  : <serial-number>
TenantId      : <tenant-id>
Removed       : True
```

When `-AssociationId` is used directly, `SerialNumber` can be empty because no lookup is required before deletion.

## Lifecycle warning

For a device that is still **Pre-associated**, removing the tenant-side Device Association record is sufficient.

For a device that is already **Associated**, deleting the server-side Device Association record alone is not a complete offboarding operation because trusted tenant affinity is also stored locally in UEFI.

For an associated device, use this order:

```text
1. Ensure the device is no longer enrolled with MDM
2. Clear the local Device Link UEFI state
3. Delete the tenant-side Device Association record
```

WindowsDeviceLink supports the local cleanup with:

```powershell
Reset-WindowsDeviceLinkFirmwareState
```

The local reset and cloud deletion remain separate operations intentionally. See [OFFBOARDING.md](OFFBOARDING.md) for the complete lifecycle flow.

## Validation status

Validated on Windows 11:

- standalone Graph DELETE;
- lookup and removal by `-SerialNumber`;
- direct removal by `-AssociationId`;
- DeviceCode authentication;
- successful `Removed = True` result.

See [`../TESTING.md`](../TESTING.md) for the full validation matrix.
