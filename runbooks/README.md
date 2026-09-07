# WindowsDeviceLink webhook runbook

`Register-WindowsDeviceLinkWebhook.ps1` is an optional Azure Automation receiver for WindowsDeviceLink `0.4.x`.

The endpoint generates the DeviceLink locally and sends it to the webhook. Graph credentials remain in Azure Automation instead of on the Windows / WinPE device.

## Runtime Environment

Use an Azure Automation Runtime Environment that includes:

- PowerShell 7.4;
- `Microsoft.Graph.Authentication`.

The runbook uses `Connect-MgGraph` and `Invoke-MgGraphRequest`.

## Automation variables

### `WindowsDeviceLinkDefaultTenantId`

Optional when the module sends `-TenantId`. Required when a single-tenant webhook is used without a tenant ID in the request.

Example:

```text
00000000-0000-0000-0000-000000000000
```

### `WindowsDeviceLinkWebhookApiKey`

Optional encrypted Automation Variable, but strongly recommended when the webhook endpoint does not have equivalent request protection.

If configured, every request must contain exactly the same value in:

```text
X-WindowsDeviceLink-Key
```

The module adds this header when `-WebhookApiKey` is supplied. The API key is never placed in the JSON body.

`-WebhookApiKey` accepts a normal string intentionally so unattended deployment and WinPE automation do not require an interactive prompt. Obtain the value from your deployment, configuration, or secrets mechanism and do not hard-code real API keys in source control.

### `WindowsDeviceLinkTenantConfiguration`

Optional JSON Automation Variable used for multi-tenant routing.

Example:

```json
{
  "00000000-0000-0000-0000-000000000001": {
    "authMethod": "ManagedIdentity"
  },
  "00000000-0000-0000-0000-000000000002": {
    "authMethod": "Certificate",
    "clientId": "00000000-0000-0000-0000-000000000003",
    "certificateAssetName": "Tenant-B-DeviceLink"
  }
}
```

Supported values in the sample runbook:

- `ManagedIdentity`
- `Certificate`

This configuration belongs to the **receiving automation layer**. No Graph certificate, client secret or app credential is required on the Windows / WinPE device when `-Method Webhook` is used.

The receiving implementation can also be adapted to obtain tenant-specific credentials or certificate material from a centralized secret store such as Azure Key Vault.

## Required Graph permission

Whichever identity the runbook uses for a target tenant requires Microsoft Graph application permission:

```text
DeviceManagementServiceConfig.ReadWrite.All
```

with the required admin consent.

## Module usage

Single-tenant webhook:

```powershell
Get-WindowsDeviceLink `
    -Online `
    -Method Webhook `
    -WebhookUri '<azure-automation-webhook-url>'
```

Webhook with API key:

```powershell
$apiKey = $env:WINDOWSDEVICELINK_WEBHOOK_API_KEY

Get-WindowsDeviceLink `
    -Online `
    -Method Webhook `
    -WebhookUri '<azure-automation-webhook-url>' `
    -WebhookApiKey $apiKey
```

Multi-tenant routing:

```powershell
Get-WindowsDeviceLink `
    -Online `
    -Method Webhook `
    -WebhookUri '<azure-automation-webhook-url>' `
    -WebhookApiKey $apiKey `
    -TenantId '<target-tenant-id>'
```

`TenantId` is routing information for the receiving runbook. It is not used for local Graph authentication on the device.

## Webhook payload

Schema version 1 contains:

- request ID and request type;
- optional target tenant ID;
- serial number;
- manufacturer / model;
- SMBIOS UUID;
- Link ID;
- DeviceLink creation time;
- complete base64 DeviceLink payload;
- source environment, architecture, module version, PowerShell version and DeviceLink DLL/runtime information.

Only `device.deviceLink` is submitted to the Microsoft Graph import action. The additional fields are available for routing, diagnostics and optional external logging/CMDB integration.

Treat the DeviceLink payload and related identity fields as sensitive operational data and do not write them to unrestricted logs.

## Validated flow

The following path has been validated end-to-end:

```text
WindowsDeviceLink
-> Azure Automation webhook
-> API-key validation
-> tenant routing
-> Managed Identity
-> Microsoft Graph
-> associationState: preassociated
```

A request with an incorrect API key was also confirmed to stop at the runbook before the Graph registration step.
