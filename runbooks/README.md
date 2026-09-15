# WindowsDeviceLink webhook runbook

`Register-WindowsDeviceLinkWebhook.ps1` is an optional Azure Automation receiver for WindowsDeviceLink `0.4.x`.

The endpoint receives a DeviceLink generated locally on Windows/WinPE and performs the tenant-side registration. Graph credentials remain in Azure Automation instead of on the endpoint.

## Runtime Environment

Use an Azure Automation Runtime Environment that includes PowerShell 7.4 and `Microsoft.Graph.Authentication`. The runbook uses `Connect-MgGraph` and `Invoke-MgGraphRequest`.

## Automation variables

### `WindowsDeviceLinkDefaultTenantId`

Optional when the module sends `-TenantId`. Required when a single-tenant webhook is used without a tenant ID in the request.

### `WindowsDeviceLinkWebhookApiKey`

Optional encrypted Automation Variable, but strongly recommended when the webhook endpoint does not have equivalent request protection. If configured, every request must contain the same value in `X-WindowsDeviceLink-Key`.

The module adds this header when `-WebhookApiKey` is supplied. The API key is never placed in the JSON body. Obtain the value from your deployment/configuration/secrets mechanism and do not hard-code real API keys in source control.

### `WindowsDeviceLinkTenantConfiguration`

Optional JSON Automation Variable used for multi-tenant routing. The sample runbook supports `ManagedIdentity` and `Certificate` authentication. This configuration belongs to the receiving automation layer; no Graph credential is required on the Windows/WinPE endpoint when `-Method Webhook` is used.

## Required Graph permission

Whichever identity the runbook uses for a target tenant requires Microsoft Graph application permission:

```text
DeviceManagementServiceConfig.ReadWrite.All
```

with the required admin consent.

## Module usage

Starting with `0.4.4-preview1`, webhook transport is an explicit registration operation. `Get-WindowsDeviceLink` remains local-only.

Single-tenant webhook:

```powershell
Get-WindowsDeviceLink |
    Register-WindowsDeviceLink `
        -Method Webhook `
        -WebhookUri '<azure-automation-webhook-url>'
```

Webhook with API key:

```powershell
$apiKey = $env:WINDOWSDEVICELINK_WEBHOOK_API_KEY
$deviceLink = Get-WindowsDeviceLink

$deviceLink | Register-WindowsDeviceLink `
    -Method Webhook `
    -WebhookUri '<azure-automation-webhook-url>' `
    -WebhookApiKey $apiKey
```

Multi-tenant routing:

```powershell
$deviceLink | Register-WindowsDeviceLink `
    -Method Webhook `
    -WebhookUri '<azure-automation-webhook-url>' `
    -WebhookApiKey $apiKey `
    -TenantId '<target-tenant-id>'
```

`TenantId` is routing information for the receiving runbook. It is not used for local Graph authentication on the device.

## Webhook payload

Schema version 1 contains request ID/type, optional target tenant ID, serial number, manufacturer/model, SMBIOS UUID, Link ID, DeviceLink creation time, complete base64 DeviceLink payload, and source/runtime information.

Only `device.deviceLink` is submitted to the Microsoft Graph import action. Additional fields are available for routing, diagnostics and optional external logging/CMDB integration.

Treat the DeviceLink payload and related identity fields as sensitive operational data and do not write them to unrestricted logs.

## Validated flow

The `0.4.3-preview1` path was validated end-to-end:

```text
WindowsDeviceLink
-> Azure Automation webhook
-> API-key validation
-> tenant routing
-> Managed Identity
-> Microsoft Graph
-> associationState: preassociated
```

The `0.4.4-preview1` development branch retains the same webhook payload/receiver and moves invocation to `Register-WindowsDeviceLink -Method Webhook`; that refactored client invocation must be revalidated before Gallery publication.
