# Azure backend options

WindowsDeviceLink can send a pre-association request to a server-side receiver instead of authenticating directly to Microsoft Graph from Windows or WinPE.

The client-side module already supports the routing values needed by both receivers:

```powershell
$deviceLink | Register-WindowsDeviceLink `
    -Method Webhook `
    -WebhookUri '<receiver-uri>' `
    -WebhookApiKey $env:WINDOWSDEVICELINK_WEBHOOK_API_KEY `
    -TenantId '<target-tenant-id>'
```

`WebhookApiKey` becomes the `X-WindowsDeviceLink-Key` header. `TenantId` is included as routing information in webhook schema v1.

## Architecture

```text
Windows / WinPE
    |
    | Register-WindowsDeviceLink -Method Webhook
    | schemaVersion=1
    | tenantId=<target tenant>
    | X-WindowsDeviceLink-Key
    v
+---------------------------------------+
| Azure Function OR Azure Automation    |
|                                       |
| validate schema                       |
| validate API key                      |
| enforce tenant allow/routing          |
| obtain app-only Graph token           |
+---------------------------------------+
                    |
                    v
        Multitenant Entra application
                    |
                    | DeviceManagementServiceConfig.ReadWrite.All
                    | application permission
                    v
             Microsoft Graph
                    |
                    v
POST /beta/deviceManagement/tenantAssociatedDevices/importTenantAssociatedDevice
```

## Backend choice

### Azure Function

Recommended when you want:

- a conventional HTTP endpoint;
- explicit HTTP status codes;
- a tenant allow list;
- native app-only OAuth without Graph SDK modules;
- Key Vault-backed API key and Graph credential;
- Application Insights;
- infrastructure-as-code / Deploy to Azure.

The Function receiver is in [../function-app](../function-app).

### Azure Automation runbook

Useful when an Automation Account already exists or when a PowerShell-centric operational model is preferred.

The current runbook is in [../runbooks](../runbooks).

For cross-tenant use, certificate authentication through a multitenant app registration is the portable option. A managed identity is tied to its home tenant and is therefore suited to same-tenant Automation scenarios, not general cross-tenant routing.

## Deploy to Azure

Both Azure backends now have resource-group deployment templates.

### Azure Function

The Function backend has a resource-group ARM template generated from the Bicep design.

[![Deploy to Azure](https://aka.ms/deploytoazurebutton)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Froryvossepoel%2FWindowsDeviceLink-Public%2Fmain%2Finfrastructure%2Ffunction-app%2Fazuredeploy.json)

The deployment creates:

- Windows Consumption Function App;
- PowerShell 7.4 / Functions v4 configuration;
- Storage Account;
- Application Insights;
- Key Vault;
- system-assigned managed identity;
- Key Vault Secrets User role assignment;
- webhook API-key secret;
- Graph credential secret;
- inline `Register-WindowsDeviceLink` HTTP function;
- inline `Lookup-WindowsDeviceLink` multitenant search function.

The template intentionally does **not** create the multitenant Entra application or grant admin consent in other tenants. Those are identity-governance actions and remain explicit administrator steps.

## Deployment inputs

The template asks for:

- `graphClientId`;
- `allowedTenantIds`;
- optional `defaultTenantId`;
- optional `tenantNamesJson` for friendly lookup results;
- `graphCredentialType` (`Certificate` preferred, `ClientSecret` supported);
- secure Graph credential;
- optional certificate password;
- secure webhook API key.

For `Certificate`, `graphCredential` is the base64 representation of the PFX.

Example:

```powershell
[Convert]::ToBase64String(
    [IO.File]::ReadAllBytes('C:\Secure\WindowsDeviceLinkBackend.pfx')
)
```

Do not commit the resulting value.

## Client configuration

After deployment, use the Function endpoint output as `-WebhookUri`:

```powershell
Get-WindowsDeviceLink |
    Register-WindowsDeviceLink `
        -Method Webhook `
        -WebhookUri 'https://<app>.azurewebsites.net/api/devicelink/preassociate' `
        -WebhookApiKey $env:WINDOWSDEVICELINK_WEBHOOK_API_KEY `
        -TenantId '<target-tenant-id>'
```

The target tenant must also:

1. be listed in `WINDOWSDEVICELINK_ALLOWED_TENANTS`;
2. have granted admin consent to the backend application.

## Security model

The Azure Function uses its **managed identity only to read its Key Vault secrets**. It does not use that managed identity for cross-tenant Graph calls.

Microsoft Graph authentication uses the separate multitenant Entra application:

```text
Function managed identity
    -> Key Vault only

Multitenant backend app + certificate
    -> Microsoft Graph in consenting tenant
```

This separation avoids storing Graph credentials on Windows/WinPE endpoints and keeps tenant onboarding explicit.

### Azure Automation

[![Deploy Azure Automation](https://aka.ms/deploytoazurebutton)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Froryvossepoel%2FWindowsDeviceLink-Public%2Fmain%2Finfrastructure%2Fautomation%2Fazuredeploy.json)

The Automation deployment creates the Automation Account, PowerShell 7.4 Runtime Environment, Microsoft.Graph.Authentication package, published runbook, variables, managed identity, and optional certificate asset. The Automation webhook is intentionally created afterwards so its secret URL is not exposed through deployment outputs/history. See [../infrastructure/automation/README.md](../infrastructure/automation/README.md).


## Multitenant lookup

The same Function App also exposes:

```text
GET /api/devicelink/lookup?serialNumber=<serial>
```

The endpoint searches the configured allowed tenants and reports where the serial number has a Device Association.

This is intentionally a backend/operator API and does not require WindowsDeviceLink to be installed on the lookup client.

See [MULTITENANT-LOOKUP.md](MULTITENANT-LOOKUP.md).
