# Multitenant Device Association lookup

The Azure Function backend can search the configured managed tenants for a Device Association by serial number.

This is useful when the operator does not know which tenant currently owns or has pre-associated a physical device.

## Endpoint

```text
GET /api/devicelink/lookup?serialNumber=<serial>
```

Required header:

```text
X-WindowsDeviceLink-Key: <backend API key>
```

Optional query parameter:

```text
tenantId=<tenant-id>
```

When `tenantId` is omitted, the Function searches every tenant in:

```text
WINDOWSDEVICELINK_ALLOWED_TENANTS
```

When `tenantId` is supplied, only that tenant is searched and it must still be present in the allow list.

## Why the lookup has a fallback

Microsoft Graph's beta `tenantAssociatedDevices` endpoint has been observed to accept a serial-number `$filter` but return no match even when a matching Device Association exists.

The Function therefore mirrors the WindowsDeviceLink module behavior:

```text
1. try server-side serialNumber filter
2. verify exact serial-number match client-side
3. if no exact match:
       enumerate the tenantAssociatedDevices collection
       match serialNumber client-side
```

This prioritizes correctness over speed.

For a backend managing many tenants or tenants with large Device Association populations, lookup latency can increase because each tenant may require a paged collection fallback.

## Example

```powershell
$headers = @{
    'X-WindowsDeviceLink-Key' = $env:WINDOWSDEVICELINK_WEBHOOK_API_KEY
}

Invoke-RestMethod `
    -Method GET `
    -Uri 'https://<app>.azurewebsites.net/api/devicelink/lookup?serialNumber=ABC123' `
    -Headers $headers
```

## Response

Example with one match:

```json
{
  "success": true,
  "requestId": "00000000-0000-0000-0000-000000000000",
  "serialNumber": "ABC123",
  "searchedTenantCount": 3,
  "successfulTenantCount": 3,
  "failedTenantCount": 0,
  "matchCount": 1,
  "matches": [
    {
      "tenantId": "22222222-2222-2222-2222-222222222222",
      "tenantName": "Contoso",
      "associationId": "00000000-0000-0000-0000-000000000000",
      "associationState": "preassociated",
      "serialNumber": "ABC123",
      "manufacturer": "Dell Inc.",
      "model": "Example Model",
      "managedDeviceId": null,
      "preassociationDateTime": "2026-09-18T10:00:00Z",
      "deploymentProfileId": null
    }
  ],
  "tenants": [],
  "tenantErrors": []
}
```

The response deliberately does not contain:

- DeviceLink payloads;
- access tokens;
- Graph credentials;
- certificate/private-key data.

## Partial failures

A lookup across multiple tenants does not fail the entire request because one tenant is unavailable.

Instead:

- successful tenants are still searched;
- per-tenant failures are returned in `tenantErrors`;
- `failedTenantCount` indicates incomplete coverage.

This distinction is important: no match in a successfully searched tenant is different from a tenant that could not be searched.

## Friendly tenant names

The deployment optionally accepts:

```text
tenantNamesJson
```

Example:

```json
{
  "11111111-1111-1111-1111-111111111111": "Contoso",
  "22222222-2222-2222-2222-222222222222": "Fabrikam"
}
```

This becomes:

```text
WINDOWSDEVICELINK_TENANT_NAMES_JSON
```

Tenant names are display metadata only. Tenant IDs remain the routing and security boundary.

## Security

The lookup endpoint:

- requires the same backend API key as pre-association;
- searches only explicitly allowed tenants;
- uses the backend app registration for Graph;
- never accepts Graph credentials from the caller;
- never returns the DeviceLink payload;
- fails closed when no tenant allow list is configured.

## Related documentation

- [AZURE-BACKEND.md](AZURE-BACKEND.md)
- [APP-REGISTRATION.md](APP-REGISTRATION.md)
- [MULTITENANT-CONSENT.md](MULTITENANT-CONSENT.md)
