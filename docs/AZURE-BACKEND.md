# Azure Function backend

> [!IMPORTANT]
> The Azure template in this repository is a **reference deployment**: a functional, security-conscious starting point rather than a prescribed production landing zone. Network isolation, ingress restrictions, private endpoints, SIEM integration and other environment-specific hardening remain the deploying organization's responsibility. See [SECURITY-HARDENING.md](SECURITY-HARDENING.md).

WindowsDeviceLink uses the Azure Function App as its only server-side backend.

The Function keeps Microsoft Graph credentials off Windows/WinPE endpoints and provides a fast HTTP API for:

- pre-association;
- multitenant lookup;
- New / Update / Move reconciliation;
- authoritative pre/post-state verification.

## Architecture

```text
Windows / WinPE
    |
    | HTTPS + X-WindowsDeviceLink-Key
    v
+---------------------------------------+
| Azure Function App                    |
|                                       |
| /api/devicelink/preassociate          |
| /api/devicelink/lookup                |
| /api/devicelink/reconcile             |
|                                       |
| validate schema/API key               |
| enforce tenant allow list             |
| obtain app-only Graph token           |
| lookup / mutate / verify              |
+---------------------------------------+
                    |
                    v
        Multitenant Entra application
                    |
                    | DeviceManagementServiceConfig.ReadWrite.All
                    | application permission
                    v
             Microsoft Graph
```

The previous Azure Automation/runbook reference backend was removed. The project intentionally maintains one backend implementation so lookup, registration, reconciliation, safety checks and deployment remain consistent.

## Endpoints

```text
POST /api/devicelink/preassociate
GET  /api/devicelink/lookup?serialNumber=<serial>
POST /api/devicelink/reconcile
```

No standalone DELETE endpoint is exposed. Deletion is an internal guarded step of a validated Move.

## Deploy to Azure

[![Deploy to Azure](https://aka.ms/deploytoazurebutton)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Froryvossepoel%2FWindowsDeviceLink-Public%2Fmain%2Finfrastructure%2Ffunction-app%2Fazuredeploy.json)

The deployment creates the Function App and its supporting reference resources, including Key Vault, storage and Application Insights.

See [../infrastructure/function-app/README.md](../infrastructure/function-app/README.md).

## Authentication

For a backend serving multiple Entra tenants, the preferred model is:

```text
multitenant Entra App Registration
+ certificate credential
+ admin consent in every target tenant
+ DeviceManagementServiceConfig.ReadWrite.All
```

A client secret is supported as a fallback.

The Function's system-assigned Managed Identity is used for Key Vault access in the reference deployment. The supplied Function code uses the configured App Registration for Microsoft Graph authentication.

See [APP-REGISTRATION.md](APP-REGISTRATION.md) and [MULTITENANT-CONSENT.md](MULTITENANT-CONSENT.md).

## Backend settings

The Function uses application settings including:

- `WINDOWSDEVICELINK_API_KEY`
- `WINDOWSDEVICELINK_CLIENT_ID`
- `WINDOWSDEVICELINK_ALLOWED_TENANTS`
- `WINDOWSDEVICELINK_DEFAULT_TENANT_ID` (optional)
- `WINDOWSDEVICELINK_TENANT_NAMES_JSON` (optional)
- `WINDOWSDEVICELINK_CERTIFICATE_PFX_BASE64` (preferred Graph credential)
- `WINDOWSDEVICELINK_CERTIFICATE_PASSWORD` (optional)
- `WINDOWSDEVICELINK_CLIENT_SECRET` (fallback)

## Function-backed initialization

`Initialize-WindowsDeviceLink` can use the Function App for cloud-state orchestration while keeping native DeviceLink completion local to Windows.

Pre-association only:

```powershell
Initialize-WindowsDeviceLink `
    -BackendUri 'https://<app>.azurewebsites.net/api/devicelink' `
    -BackendApiKey $env:WINDOWSDEVICELINK_WEBHOOK_API_KEY `
    -TargetTenantId '<target-tenant-id>'
```

Full association:

```powershell
Initialize-WindowsDeviceLink `
    -BackendUri 'https://<app>.azurewebsites.net/api/devicelink' `
    -BackendApiKey $env:WINDOWSDEVICELINK_WEBHOOK_API_KEY `
    -TargetTenantId '<target-tenant-id>' `
    -FullAssociation
```

The backend path performs an authoritative all-tenant lookup first.

```text
not found anywhere
    -> pre-associate in TargetTenantId

found in TargetTenantId
    -> no cloud change

found in another tenant
    -> BLOCK
    -> explicit tenant-move workflow required
```

`Initialize-WindowsDeviceLink` deliberately does **not** perform an implicit Move. A cross-tenant move deletes tenant-side state and therefore remains an explicit operation.

With `-FullAssociation`, once the requested target tenant is verified as pre-associated, WindowsDeviceLink invokes the existing guarded local `Complete-WindowsDeviceLinkAssociation` operation. The Function App is then queried again to verify the final tenant-side state.

`-BackendUri` is the API base URI ending in:

```text
/api/devicelink
```

WindowsDeviceLink derives the `lookup` and `preassociate` routes from that base URI.

## Client pre-association

```powershell
Get-WindowsDeviceLink |
    Register-WindowsDeviceLink `
        -Method Webhook `
        -WebhookUri '<function-preassociate-uri>' `
        -WebhookApiKey $env:WINDOWSDEVICELINK_WEBHOOK_API_KEY `
        -TenantId '<target-tenant-id>'
```

The API key authenticates the caller to the Function. The tenant ID is routing context; neither replaces Microsoft Graph authentication performed by the backend.

## Multitenant lookup

The lookup endpoint searches all allowed tenants and returns normalized tenant-side state without returning the DeviceLink payload.

See [MULTITENANT-LOOKUP.md](MULTITENANT-LOOKUP.md).

## Reconcile

The reconcile endpoint derives the required operation from fresh cloud state:

```text
not found anywhere                         -> New
found in requested target                  -> Update / no-op
found in another tenant + matching source  -> Move
```

The caller supplies facts such as expected source tenant, target tenant and current DeviceLink identity. The caller does **not** submit a New/Move/Update decision.

See [RECONCILE-SCHEMA-v1.md](RECONCILE-SCHEMA-v1.md).

## Safety model

The Function backend:

- requires an explicit tenant allow list;
- fails closed when a configured tenant cannot be searched;
- rejects ambiguous duplicate state;
- verifies an expected source tenant before Move;
- re-reads source state immediately before deletion;
- does not blindly retry POST/DELETE after an ambiguous transport failure;
- verifies source removal before target creation;
- verifies target creation afterwards;
- never resets local DeviceLink firmware;
- never logs the complete DeviceLink payload.

## Hardening

The Deploy to Azure template is deliberately a reference baseline. Depending on the environment, organizations can add controls such as Private Endpoints, access restrictions, API Management, VNet integration, WAF/reverse proxy controls and SIEM forwarding without changing the WindowsDeviceLink request contract.

See [SECURITY-HARDENING.md](SECURITY-HARDENING.md).
