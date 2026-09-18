# Deploy the Azure Automation receiver

This folder deploys the Azure Automation backend for WindowsDeviceLink.

> [!NOTE]
> This is a **reference deployment**. It deliberately does not attempt to implement every possible networking, Private Link, SIEM, firewall or enterprise-hardening pattern. See [../../docs/SECURITY-HARDENING.md](../../docs/SECURITY-HARDENING.md).

[![Deploy to Azure](https://aka.ms/deploytoazurebutton)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Froryvossepoel%2FWindowsDeviceLink-Public%2Fmain%2Finfrastructure%2Fautomation%2Fazuredeploy.json)

## What is deployed

The template creates:

- Azure Automation Account with system-assigned managed identity;
- PowerShell 7.4 Runtime Environment;
- `Microsoft.Graph.Authentication` package;
- published `Register-WindowsDeviceLinkWebhook` runbook sourced from this repository;
- encrypted `WindowsDeviceLinkWebhookApiKey` Automation Variable;
- `WindowsDeviceLinkDefaultTenantId` Automation Variable;
- `WindowsDeviceLinkTenantConfiguration` Automation Variable;
- optional Automation certificate asset for cross-tenant certificate authentication.

The webhook itself is intentionally **not** created by the ARM template.

## Why the webhook is a separate step

An Azure Automation webhook URL is effectively a bearer secret. Microsoft only exposes the URL when the webhook is created, and it cannot be retrieved later through normal webhook lookup operations.

For that reason the deployment does not emit a webhook URI into deployment outputs or deployment history.

After deployment, create the webhook explicitly and immediately store the returned URL in a secure location.

Example with Az PowerShell:

```powershell
$expiry = (Get-Date).ToUniversalTime().AddYears(2)

$webhook = New-AzAutomationWebhook `
    -ResourceGroupName '<resource-group>' `
    -AutomationAccountName '<automation-account>' `
    -Name 'WindowsDeviceLink' `
    -RunbookName 'Register-WindowsDeviceLinkWebhook' `
    -ExpiryTime $expiry `
    -IsEnabled $true

$webhook.WebhookURI
```

Copy the URI immediately to your password manager / deployment secret store.

## Single-tenant Managed Identity

For a same-tenant receiver, Managed Identity is the preferred Graph authentication method because no application secret or certificate private key needs to be managed:



1. deploy with `tenantConfigurationJson = {}`;
2. set `defaultTenantId` to that tenant;
3. assign Microsoft Graph application permission `DeviceManagementServiceConfig.ReadWrite.All` to the Automation Account managed identity;
4. create the webhook;
5. call it with `-Method Webhook`.

The sample runbook treats an empty tenant configuration as Managed Identity for the requested/default tenant.

## Cross-tenant certificate mode

For cross-tenant routing, use the multitenant App Registration described in:

- [../../docs/APP-REGISTRATION.md](../../docs/APP-REGISTRATION.md)
- [../../docs/MULTITENANT-CONSENT.md](../../docs/MULTITENANT-CONSENT.md)

Supply the PFX as `certificateBase64` and provide matching `certificateThumbprint`.

Example tenant configuration:

```json
{
  "11111111-1111-1111-1111-111111111111": {
    "authMethod": "Certificate",
    "clientId": "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa",
    "certificateAssetName": "WindowsDeviceLinkBackend"
  },
  "22222222-2222-2222-2222-222222222222": {
    "authMethod": "Certificate",
    "clientId": "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa",
    "certificateAssetName": "WindowsDeviceLinkBackend"
  }
}
```

The same multitenant application/certificate can be used for every tenant that has granted admin consent.

## Client usage

```powershell
Get-WindowsDeviceLink |
    Register-WindowsDeviceLink `
        -Method Webhook `
        -WebhookUri '<automation-webhook-uri>' `
        -WebhookApiKey $env:WINDOWSDEVICELINK_WEBHOOK_API_KEY `
        -TenantId '<target-tenant-id>'
```

For a single-tenant backend with `WindowsDeviceLinkDefaultTenantId`, `-TenantId` can be omitted.

## Security notes

- Treat the Automation webhook URI as a secret.
- Treat `WindowsDeviceLinkWebhookApiKey` as a second independent shared secret.
- Do not commit the PFX/private key.
- The ARM parameter for the PFX and API key is `secureString`.
- The certificate asset is marked non-exportable.
- Admin consent in external tenants is never granted automatically.
