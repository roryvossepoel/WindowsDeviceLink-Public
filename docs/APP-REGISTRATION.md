# Multitenant backend app registration

The Azure Function and multi-tenant Azure Automation receiver use a Microsoft Entra application registration for app-only Microsoft Graph authentication.

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

### Preferred: certificate

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

## Same-tenant managed identity

Azure Automation can use a managed identity when the target tenant is the same tenant that owns the Automation Account identity and that identity has the required Graph application role.

Managed identity should not be described as the general cross-tenant solution. For cross-tenant routing, use the multitenant application registration with certificate authentication.

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
