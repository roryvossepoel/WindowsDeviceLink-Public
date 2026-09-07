# Choosing an online method

`Get-WindowsDeviceLink -Online` requires an explicit `-Method`.

| Method | Best fit | Credentials on device | Required input |
|---|---|---:|---|
| `DeviceCode` | Interactive admin/test workflow | No persistent secret | `TenantId` |
| `Interactive` | Interactive Graph SDK workflow | No persistent secret | `TenantId` |
| `ClientSecret` | Unattended direct Graph call | Yes | `TenantId`, `ClientId`, `ClientSecret` |
| `AccessToken` | Caller already has a Graph token | Token in memory | `TenantId`, `AccessToken` |
| `Certificate` | Unattended direct Graph call | Certificate/private key | `TenantId`, `ClientId`, `Certificate` |
| `CertificateThumbprint` | Certificate already installed locally | Certificate/private key | `TenantId`, `ClientId`, `CertificateThumbprint` |
| `CertificateSubjectName` | Certificate already installed locally | Certificate/private key | `TenantId`, `ClientId`, `CertificateSubjectName` |
| `EnvironmentVariable` | Existing client-credential automation | Yes | `AZURE_TENANT_ID`, `AZURE_CLIENT_ID`, `AZURE_CLIENT_SECRET` |
| `ManagedIdentity` | Azure-hosted execution with an identity | No | Optional `ClientId` |
| `Webhook` | Unattended endpoint / WinPE / multi-tenant automation | No Graph credential | `WebhookUri`; optional `WebhookApiKey`, `TenantId` |

## Recommended patterns

### Manual administration or testing

Use `DeviceCode` unless another interactive method is specifically required.

```powershell
Get-WindowsDeviceLink `
    -Online `
    -Method DeviceCode `
    -TenantId '<tenant-id>'
```

### Unattended endpoint or WinPE

Prefer `Webhook` when Graph secrets or certificates should not be stored on the endpoint.

```powershell
Get-WindowsDeviceLink `
    -Online `
    -Method Webhook `
    -WebhookUri '<webhook-url>' `
    -WebhookApiKey $env:WINDOWSDEVICELINK_WEBHOOK_API_KEY `
    -TenantId '<target-tenant-id>'
```

The receiving automation layer owns tenant routing and Graph authentication.

### Direct unattended Graph call

Use a protected application credential such as a certificate where appropriate. The credential remains the responsibility of the caller.

## Parameter validation

WindowsDeviceLink rejects:

- `-Online` without `-Method`;
- required method inputs that are missing;
- parameters that do not belong to the selected method.

This validation happens before DeviceLink generation starts.
