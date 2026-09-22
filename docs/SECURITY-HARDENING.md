# Security and hardening guidance

WindowsDeviceLink provides backend code and a **reference Azure deployment template** for the Azure Function App.

The template is intended to provide a functional, security-conscious starting point. It is **not** a complete Azure landing zone and does not prescribe one production network/security architecture for every organization.

## Responsibility boundary

WindowsDeviceLink provides:

- the webhook contract;
- API-key support;
- explicit tenant routing;
- minimal Microsoft Graph permissions;
- app-only authentication examples;
- secret-safe logging behavior;
- a reference Azure Function deployment;
- documented single-tenant and multitenant identity patterns.

The deploying organization remains responsible for deciding which additional controls its environment requires.

## Authentication hierarchy

### Single tenant

The Azure Function reference backend uses its system-assigned Managed Identity for **Key Vault access**. Microsoft Graph authentication in the supplied multitenant implementation uses the backend App Registration.

Organizations that require direct same-tenant Graph authentication with Managed Identity can adapt the Function implementation to their own architecture.

### Multiple tenants

For one backend serving multiple Entra tenants, use a **multitenant App Registration with certificate-based client credentials**.

Each target tenant explicitly grants admin consent. The same application identity can then request an app-only token from the selected target tenant.

### Client secret

Client-secret authentication is supported only as a fallback where certificate-based authentication is not practical.

It should not be interpreted as the preferred production credential.

## Request protection

The reference webhook flow supports:

- HTTPS;
- `X-WindowsDeviceLink-Key`;
- explicit `TenantId` routing;
- tenant allow-listing where implemented;
- request correlation IDs;
- payload-safe logging.

The API key and tenant ID serve different purposes:

```text
WebhookApiKey
    -> authenticate/authorize the caller to the receiver

TenantId
    -> select the intended target tenant
```

Neither replaces Microsoft Graph authentication.

## Optional organization-specific hardening

Organizations can add additional controls without changing the WindowsDeviceLink webhook schema.

Examples include:

- Private Endpoints;
- public network access disabled;
- IP/subnet access restrictions;
- VNet integration;
- API Management;
- reverse proxy/WAF controls;
- Entra-protected ingress;
- Key Vault network restrictions;
- centralized SIEM/log forwarding;
- Defender for Cloud;
- certificate rotation policies;
- custom monitoring/alerting;

These are deliberately **not** all implemented by the reference templates.

The appropriate combination depends on the organization's network design, Azure governance, threat model and operational requirements.

## Reference deployment policy

A Deploy to Azure button means:

```text
working reference deployment
!=
mandatory production architecture
```

Use the template as a baseline, review it, and harden or replace it according to your organization's standards.

WindowsDeviceLink should remain focused on Device Association rather than becoming a general-purpose Azure security framework.
