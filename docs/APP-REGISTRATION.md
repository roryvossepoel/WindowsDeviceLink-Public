# Multitenant backend app registration

This document applies to the WindowsDeviceLink Azure Function backend when it uses an App Registration for app-only Microsoft Graph authentication, especially for **multi-tenant** routing.

## Recommended application design

Create one application in the backend/home tenant with:

```text
Supported account types:
Accounts in any organizational directory
(multitenant)
```

Record:

- Application (client) ID;
- home tenant ID.

The client ID is an identifier and is not secret.

## Microsoft Graph permission

Add:

```text
Microsoft Graph
Application permission
DeviceManagementServiceConfig.ReadWrite.All
```

This is an **application** permission, not delegated permission.

Admin consent is required in every tenant in which this application will create Device Associations.

## Credential

For App Registration-based authentication, certificate-based client credentials are preferred over client secrets.

### Preferred for App Registration: certificate

Create a certificate whose private key is controlled by the backend operator.

Upload the public certificate to:

```text
App registrations
-> <WindowsDeviceLink backend app>
-> Certificates & secrets
-> Certificates
```

The Function deployment expects the PFX as a secure deployment parameter and stores it in Key Vault. The application setting receives only a Key Vault reference.

The private key must never be committed to GitHub.

### Fallback: client secret

Client-secret authentication is supported by the Function receiver for environments that cannot yet use a certificate.

It should be treated as a fallback because secrets:

- have a copyable plaintext value at creation time;
- require rotation;
- are easier to leak than a well-controlled certificate private key.

The deployment stores the secret in Key Vault.

## Why the app is multitenant

A single backend can route requests to multiple managed tenants.

For each target tenant:

1. an administrator grants tenant-wide consent;
2. Entra creates a local service principal / Enterprise Application for the multitenant application;
3. the backend requests a token from that target tenant using the same application/client ID and credential;
4. Microsoft Graph evaluates the application permission granted in that target tenant.

The Function additionally uses an explicit tenant allow list and rejects unknown tenant IDs before authentication.

## Same-tenant Managed Identity

Azure Automation can use its system-assigned Managed Identity when the target tenant is the same tenant that owns the Automation Account identity and that identity has the required Graph application role.

For that same-tenant scenario, Managed Identity is preferred over both certificate and client secret because no application credential needs to be stored or rotated by the backend operator.

Managed Identity is not the general cross-tenant solution. For cross-tenant routing, use the multitenant App Registration with certificate authentication.

The Azure Function reference implementation currently uses its Managed Identity for Key Vault access only; Graph authentication uses the App Registration.

## Required backend values

The Function backend requires:

```text
WINDOWSDEVICELINK_CLIENT_ID
WINDOWSDEVICELINK_ALLOWED_TENANTS
WINDOWSDEVICELINK_API_KEY

and one of:

WINDOWSDEVICELINK_CERTIFICATE_PFX_BASE64
WINDOWSDEVICELINK_CLIENT_SECRET
```

See [MULTITENANT-CONSENT.md](MULTITENANT-CONSENT.md) for tenant onboarding.
