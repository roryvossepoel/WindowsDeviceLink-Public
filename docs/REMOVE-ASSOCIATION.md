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
    -Method DeviceCode `
    -TenantId '<tenant-id>'
```

The cmdlet resolves the matching Device Association record, obtains its association ID, and deletes that exact record.

If multiple records match the serial number, the cmdlet stops and asks you to use `-AssociationId` instead of guessing.

## Advanced usage: association ID

If the Device Association record ID is already known, delete it directly:

```powershell
Remove-WindowsDeviceLinkAssociation `
    -AssociationId '<association-id>' `
    -Method DeviceCode `
    -TenantId '<tenant-id>'
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

`TenantId` remains explicit for methods such as DeviceCode and certificate authentication because the tenant is determined by the authentication context. `EnvironmentVariable` obtains the tenant from `AZURE_TENANT_ID`.

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

The currently validated workflow removes a **preassociated** Device Association record from Intune/Graph.

For a device that is already fully associated, deleting the server-side Device Association record alone may not clear device-side tenant affinity. Device-side/UEFI decommissioning is a separate lifecycle operation and is not currently implemented by WindowsDeviceLink.

## Validation status

Validated on Windows 11:

- standalone Graph DELETE;
- lookup and removal by `-SerialNumber`;
- direct removal by `-AssociationId`;
- DeviceCode authentication;
- successful `Removed = True` result.

See [`../TESTING.md`](../TESTING.md) for the full validation matrix.
