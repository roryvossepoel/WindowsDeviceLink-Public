# WindowsDeviceLink Azure Function receiver

This folder contains the PowerShell Azure Function receiver for `Register-WindowsDeviceLink -Method Webhook`.

The Function accepts the existing webhook schema v1 and performs the tenant-side Microsoft Graph pre-association. Windows/WinPE clients do not need Graph credentials.

## Endpoint

Endpoints:

```text
POST /api/devicelink/preassociate
GET  /api/devicelink/lookup?serialNumber=<serial>
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

Certificate authentication is preferred. When both certificate and client secret are configured, the certificate is used.

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
