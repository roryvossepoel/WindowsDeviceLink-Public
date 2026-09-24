# WindowsDeviceLink Azure Function receiver

This folder contains the WindowsDeviceLink PowerShell Azure Function backend. It is the project's only server-side backend.

The Function provides pre-association, fast multitenant lookup, safe New / Update / Move / Repair reconciliation, and verified cloud offboarding. Windows/WinPE clients do not need Microsoft Graph credentials.

The authenticated tenant-catalog response is also the compatibility handshake. Backend
API version `1.0` requires WindowsDeviceLink `0.10.0` or newer and advertises
`TenantCatalog`, `MultitenantLookup`, `Reconcile`, and `Offboarding` capabilities. Clients fail closed
when the version or required capabilities do not match.

## Endpoint

Endpoints:

```text
POST /api/devicelink/preassociate
GET  /api/devicelink/lookup?serialNumber=<serial>
GET  /api/devicelink/tenants
POST /api/devicelink/reconcile
POST /api/devicelink/offboard
```

The module sends:

- `X-WindowsDeviceLink-Schema: 1`;
- `X-WindowsDeviceLink-RequestId: <guid>`;
- optional/expected `X-WindowsDeviceLink-Key`;
- the schema v1 JSON request body.

## Backend settings

The Function reads these application settings:

| Setting | Purpose |
|---|---|
| `WINDOWSDEVICELINK_API_KEY` | Shared API key expected in `X-WindowsDeviceLink-Key`. |
| `WINDOWSDEVICELINK_CLIENT_ID` | Client ID of the multitenant Entra application. |
| `WINDOWSDEVICELINK_ALLOWED_TENANTS` | Comma/semicolon-separated allow list of target tenant IDs. Required; backend fails closed when empty. |
| `WINDOWSDEVICELINK_DEFAULT_TENANT_ID` | Optional default tenant when the request omits `tenantId`. |
| `WINDOWSDEVICELINK_TENANT_NAMES_JSON` | Optional tenant ID -> friendly name mapping used by lookup responses. |
| `WINDOWSDEVICELINK_CERTIFICATE_PFX_BASE64` | Preferred Graph credential: base64 PFX, normally supplied through a Key Vault reference. |
| `WINDOWSDEVICELINK_CERTIFICATE_PASSWORD` | Optional PFX password. |
| `WINDOWSDEVICELINK_CLIENT_SECRET` | Fallback Graph client secret, normally supplied through a Key Vault reference. |

For Microsoft Graph authentication in this **reference Function implementation**, certificate-based App Registration authentication is preferred over a client secret. When both are configured, the certificate is used.

The Function's system-assigned Managed Identity is used for Key Vault access in the reference deployment; it is not the Graph identity used by the supplied multi-tenant Function code.

## Deployment scope

The supplied Function App and Deploy to Azure template are a reference deployment, not a complete production network/security architecture. Organizations can add Private Endpoints, access restrictions, API Management, VNet integration or other controls according to their own requirements without changing the webhook schema. See [../docs/SECURITY-HARDENING.md](../docs/SECURITY-HARDENING.md).

## Security behavior

The receiver:

- requires schema v1;
- requires the API key;
- validates the request/header correlation ID;
- rejects target tenants outside the explicit allow list;
- never logs the complete DeviceLink payload;
- keeps the Graph access token only in memory;
- returns normalized errors rather than raw Graph response bodies;
- returns HTTP 409 for an existing/conflicting Device Association.

## Graph permission

The multitenant backend application requires this Microsoft Graph **application** permission:

```text
DeviceManagementServiceConfig.ReadWrite.All
```

Admin consent must be granted in each target tenant.

See:

- [../docs/AZURE-BACKEND.md](../docs/AZURE-BACKEND.md)
- [../docs/APP-REGISTRATION.md](../docs/APP-REGISTRATION.md)
- [../docs/MULTITENANT-CONSENT.md](../docs/MULTITENANT-CONSENT.md)
- [../docs/WEBHOOK-SCHEMA-v1.md](../docs/WEBHOOK-SCHEMA-v1.md)


## Multitenant lookup

The second HTTP function searches all allowed tenants for a Device Association by serial number:

```powershell
Invoke-RestMethod `
    -Method GET `
    -Uri 'https://<app>.azurewebsites.net/api/devicelink/lookup?serialNumber=ABC123' `
    -Headers @{ 'X-WindowsDeviceLink-Key' = $env:WINDOWSDEVICELINK_WEBHOOK_API_KEY }
```

It first tries the Graph serial-number filter and then falls back to paged client-side matching when needed.

See [../docs/MULTITENANT-LOOKUP.md](../docs/MULTITENANT-LOOKUP.md).

## Tenant catalog

`GET /api/devicelink/tenants` returns the allowed tenant IDs and their configured
friendly display names. It requires the same API key as the other endpoints. The
catalog never chooses a target tenant: UI and command-line callers must submit one
explicit target tenant ID to the mutation workflow.


## Reconcile: New / Move / Update

The reconcile endpoint is intended for workflows that already perform a source lookup before submission, such as an imaging or provisioning form.

The supplied `sourceTenantId` is treated as expected state only. The backend performs its own fresh lookup across all allowed tenants before any mutation.

```text
not found anywhere     -> New
found in target        -> Update
found in another tenant + matching sourceTenantId -> Move
```

A Move uses internal DELETE/POST operations. Cloud offboarding is exposed separately as
an authenticated, schema-versioned POST workflow; raw Graph DELETE semantics are never
exposed to the client.

The endpoint fails closed when the source is ambiguous, a configured tenant cannot be searched, or the supplied source does not match current state.

See [../docs/RECONCILE-SCHEMA-v1.md](../docs/RECONCILE-SCHEMA-v1.md).

## Verified cloud offboarding

`POST /api/devicelink/offboard` performs a fresh lookup across every allowed tenant,
requires an unambiguous association, optionally verifies the caller's expected source
tenant, deletes exactly one proven association, and verifies that it is absent. A
transport-ambiguous DELETE is never retried blindly. Repeating the workflow after the
association is absent returns a successful no-change result.
