# Multitenant Device Association lookup

> [!IMPORTANT]
> Tenant-wide lookup is now a **fallback and verification path**, not the preferred way to discover the source tenant on the local device. When WindowsDeviceLink can read local DeviceLink association metadata, use `Get-WindowsDeviceLinkLocalAssociation` first.

## Preferred source-tenant discovery

On a physical device, first try:

```powershell
Get-WindowsDeviceLinkLocalAssociation
```

This command is cloud-independent and can identify the source tenant from local DeviceLink metadata:

- after successful native discovery, the exact current-LinkId registry value `<LinkId>_TenantIdHint`;
- after full association, the `tenantId` claim in `DeviceLinkJwtCompressed`;
- when both are present, WindowsDeviceLink correlates them and fails closed if they disagree.

Recommended decision path:

```text
local DeviceLink tenant available
  -> use local TenantId as expected source context
  -> authenticate only when cloud verification or mutation is required

local tenant unavailable
  -> fall back to multitenant backend lookup
```

Historical registry hints can survive a firmware reset, so only a hint whose prefix exactly matches the **current** UEFI `DeviceLinkId` is eligible.

See [LOCAL-TENANT-DISCOVERY.md](LOCAL-TENANT-DISCOVERY.md).


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
      "tenantName": "Customer A",
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

An absent device returns `matchCount: 0`, `matches: []`, and no tenant error when Graph returns successful empty collections. Only treat the device as absent across the configured tenants when `failedTenantCount` is zero and `successfulTenantCount` equals `searchedTenantCount`.

Tenant errors also include safe diagnostic fields:

- `stage`: `GraphToken`, `GraphLookup`, or `GraphLookupFallback`;
- `statusCode`: the upstream HTTP status, when available;
- `upstreamErrorCode`: a recognized OAuth or Graph error code;
- `aadstsCodes`: numeric Entra error codes, such as `AADSTS700027`;
- `upstreamCorrelationId`: the upstream correlation/request GUID, when available.

These fields identify whether a failure occurred while obtaining a token or querying Graph. Raw upstream error descriptions and response bodies are not returned or logged. HTTP 200 and `success: true` indicate that the lookup response was assembled; callers must still inspect tenant coverage, including when every tenant failed.

## Friendly tenant names

The deployment optionally accepts:

```text
tenantNamesJson
```

Example:

```json
{
  "11111111-1111-1111-1111-111111111111": "Management",
  "22222222-2222-2222-2222-222222222222": "Customer A"
}
```

This becomes:

```text
WINDOWSDEVICELINK_TENANT_NAMES_JSON
```

Tenant names are display metadata only. Tenant IDs remain the routing and security boundary.

Authenticated clients can retrieve the same authoritative catalog through:

```text
GET /api/devicelink/tenants
```

The GUI uses this endpoint to populate its selector. Command-line automation should
normally pass `-TargetTenantId`; `-TargetTenantName` is available for operator
convenience and must resolve to exactly one catalog entry.

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


## Using lookup before reconcile

A UI or provisioning workflow can use this endpoint to pre-populate the current/source tenant before submitting a reconcile request.

That earlier lookup is advisory only. `POST /api/devicelink/reconcile` performs its own fresh lookup before any state-changing operation so stale form data cannot directly trigger deletion from the wrong tenant.

See [RECONCILE-SCHEMA-v1.md](RECONCILE-SCHEMA-v1.md).
