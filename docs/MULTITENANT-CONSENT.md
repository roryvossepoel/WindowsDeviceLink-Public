# Onboard another tenant with admin consent

Each target tenant must explicitly grant admin consent to the WindowsDeviceLink backend application.

## Before starting

You need:

- the backend application's client ID;
- the target tenant ID;
- an administrator in the target tenant who can grant tenant-wide admin consent;
- `DeviceManagementServiceConfig.ReadWrite.All` configured as an application permission on the home application registration.

## Admin-consent URL

Open:

```text
https://login.microsoftonline.com/<target-tenant-id>/adminconsent?client_id=<client-id>
```

Replace both placeholders with real IDs.

The target-tenant administrator signs in, reviews the requested permissions, and grants consent.

Do not automate this consent step through the WindowsDeviceLink deployment template.

## What happens after consent

A local Enterprise Application/service principal for the multitenant backend application exists in the target tenant.

The backend can then request an app-only token from:

```text
https://login.microsoftonline.com/<target-tenant-id>/oauth2/v2.0/token
```

using the same application/client ID and backend certificate (or client secret).

## Function tenant allow list

Consent alone is intentionally not enough.

Add the target tenant ID to the Function configuration:

```text
WINDOWSDEVICELINK_ALLOWED_TENANTS
```

Example:

```text
11111111-1111-1111-1111-111111111111;
22222222-2222-2222-2222-222222222222
```

Requests for tenants not in this list return HTTP 403.

## Client usage

The Windows/WinPE device supplies the tenant only as routing metadata:

```powershell
Get-WindowsDeviceLink |
    Register-WindowsDeviceLink `
        -Method Webhook `
        -WebhookUri '<backend-uri>' `
        -WebhookApiKey $env:WINDOWSDEVICELINK_WEBHOOK_API_KEY `
        -TenantId '22222222-2222-2222-2222-222222222222'
```

The endpoint never receives the Graph application credential from the device.

## Verify onboarding

Use a dedicated test device and perform one pre-association.

Expected receiver response:

```text
success          : true
tenantId         : <target tenant>
associationState : preassociated
associationId    : <id>
```

Then verify the Device Association in Intune.

If authentication returns HTTP 401/403 from Microsoft Graph, check:

- consent was granted in the **target** tenant;
- the permission is an **application** permission;
- the application/service principal is not disabled;
- the certificate/secret belongs to the home application registration;
- the target tenant ID is correct.

## Removing access

To offboard a tenant:

1. remove its tenant ID from the backend allow list;
2. remove/revoke the Enterprise Application or its granted permissions in the target tenant as required by your governance process.

Removing the tenant from the Function allow list immediately prevents new routed requests even before consent is revoked.
