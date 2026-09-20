# Authentication and secret-handling matrix

WindowsDeviceLink separates local DeviceLink operations from explicit tenant-side operations. Authentication parameters apply only to cloud operations.

## Security invariants

The module must not emit the following through normal output, information/verbose/debug streams, returned errors or returned objects:

- client secrets;
- access/bearer tokens;
- certificate private-key material;
- webhook API keys;
- raw DeviceLink JWT/payload data.

User-facing device-code `user_code` values are intentionally displayed because the user must enter them during authentication. The OAuth `device_code` value is treated as sensitive and must not be echoed in errors.

## Method matrix

| Method | Transport | Required input | CI coverage | Live validation |
| --- | --- | --- | --- | --- |
| DeviceCode | Native OAuth + Graph REST | optional TenantId; optional ClientId | parameter boundaries, OAuth error redaction, Graph redaction, initializer token-reuse contract | successful sign-in + read/write smoke |
| Interactive | Microsoft.Graph.Authentication | optional TenantId; optional ClientId | parameter boundaries / SDK argument forwarding | interactive sign-in smoke |
| ClientSecret | Native OAuth + Graph REST | TenantId, ClientId, SecureString ClientSecret | required inputs, secret redaction, Graph error redaction | optional app-only read/write smoke |
| AccessToken | Native Graph REST | TenantId, SecureString AccessToken | required inputs, bearer redaction, Graph error semantics | optional valid/expired token smoke |
| Certificate | Microsoft.Graph.Authentication | TenantId, ClientId, X509Certificate2 | required inputs / SDK argument forwarding | certificate-backed app-only smoke |
| CertificateThumbprint | Microsoft.Graph.Authentication | TenantId, ClientId, thumbprint | required inputs / SDK argument forwarding | certificate-store resolution smoke |
| CertificateSubjectName | Microsoft.Graph.Authentication | TenantId, ClientId, subject name | required inputs / SDK argument forwarding | missing/ambiguous/valid certificate smoke |
| EnvironmentVariable | Native OAuth + Graph REST | AZURE_TENANT_ID, AZURE_CLIENT_ID, AZURE_CLIENT_SECRET | missing-variable behavior and secret redaction | optional environment credential smoke |
| ManagedIdentity | Microsoft.Graph.Authentication | optional user-assigned ClientId | parameter boundaries / SDK argument forwarding | Azure-hosted managed-identity smoke |
| Webhook | HTTPS POST | WebhookUri; API key strongly recommended | API-key and DeviceLink-payload redaction | endpoint-specific smoke |

## Error semantics

Authentication or transport failure is never equivalent to `NotAssociated`. Cloud lookup remains indeterminate until a successful Graph response proves that no matching association exists.

Native Graph transport errors are normalized before leaving the module. HTTP status is retained when available, while bearer tokens, client secrets, webhook keys and raw DeviceLink payloads are removed from error text.

Mutation requests are not blindly retried. A POST or DELETE timeout can occur after the service committed the request, so retrying automatically can create ambiguous state.

## DeviceCode orchestration

`Initialize-WindowsDeviceLink -Method DeviceCode` acquires one token at the beginning of the operation and reuses it for:

1. initial association lookup;
2. registration when the state is `LocalOnly`;
3. post-registration verification.

This avoids repeated device-code prompts inside one initialization run.

## Live-test policy

CI covers parameter contracts and redaction without using real credentials. Live tests are kept separate because Interactive, certificate authentication and Managed Identity depend on tenant or hosting infrastructure. Synthetic marker values should be used for all negative/redaction tests; real secrets must never be pasted into issue comments, CI output or test fixtures.
