# Tenant assignment modes

WindowsDeviceLink supports several operator flows through two execution routes:

- **Direct** — the device talks directly to Microsoft Graph.
- **Backend** — the device delegates catalog lookup and tenant assignment to the
  WindowsDeviceLink Function App.

Backend mode is the recommended route for structural multitenant use. Direct mode
remains useful for single-tenant operation, fixed-purpose media, and controlled
environments that deliberately do not deploy the Function App.

## Choose a mode

| Mode | Who determines the tenant? | Authentication | Best suited for |
|---|---|---|---|
| Account-based Direct | The signed-in account context | Delegated user token | Ad-hoc work in one tenant at a time |
| Fixed-tenant Direct | A supplied `TenantId` | Delegated or application | Dedicated scripts or media for one enforced tenant |
| Delegated catalog Direct | Operator selection from a catalog | User plus delegated app permissions | A small tenant list without a backend |
| Application catalog Direct | Operator selection from a catalog | App-only credential and application permissions | Controlled non-interactive environments without a backend |
| Backend | Operator selection from the Function catalog | Function API access; Graph credentials stay in Azure | Structural multitenant lookup, registration, and verified Move |

If a device may already exist in another managed tenant, choose **Backend**. Direct
mode can inspect only its current target tenant and therefore cannot prove that the
device is absent elsewhere.

## GUI and CLI are different operator surfaces

The modes describe authentication and tenant scope; they do not imply that every
workflow is unattended.

| Mode | GUI flow | CLI automation |
|---|---|---|
| Account-based Direct | Operator selects **Sign in** and completes user authentication | Not fully unattended; Interactive or DeviceCode requires a user |
| Fixed-tenant Direct with delegated auth | Tenant is hidden and enforced; operator still signs in | Target is deterministic, but user authentication remains interactive |
| Delegated catalog Direct | Operator selects a tenant, then signs in against it | A script can resolve the catalog entry, but delegated authentication still requires a user or existing SSO context |
| Fixed or catalog Direct with app-only auth | No **Sign in** button; cloud actions obtain authentication non-interactively | Can be unattended when the credential and target tenant are supplied securely |
| Backend | Operator selects the Function-provided target and chooses **Register device** | Can be unattended by calling `Set-WindowsDeviceLinkTenant` with an explicit target |

The GUI remains an operator interface: even with non-interactive authentication, tenant
selection and **Register device** are intentional operator actions. For zero-touch
execution, use the CLI and pass or resolve the target tenant in the script.

Examples of CLI-oriented choices:

```powershell
# Account-based or delegated: user interaction is expected.
Set-WindowsDeviceLinkTenant -Method DeviceCode

# Fixed tenant plus app-only authentication: suitable for automation when the
# certificate is protected and intentionally available to the endpoint.
Set-WindowsDeviceLinkTenant `
    -Method CertificateThumbprint `
    -TenantId '<tenant-id>' `
    -ClientId '<client-id>' `
    -CertificateThumbprint '<thumbprint>'

# Backend: preferred unattended multitenant route.
Set-WindowsDeviceLinkTenant `
    -BackendUri 'https://<app>.azurewebsites.net/api/devicelink' `
    -BackendApiKey $apiKey `
    -TargetTenantId '<tenant-id>'
```

## Account-based Direct mode

Start the GUI without a tenant ID or catalog:

```powershell
Show-WindowsDeviceLink
```

The GUI shows no tenant selector. The tenant that issues the delegated sign-in token
becomes the target tenant. **Switch account** can start a new sign-in, allowing another
tenant to be used in a later session.

This mode still uses an app registration. When no custom `ClientId` is supplied, the
underlying Microsoft Graph authentication client is used. Effective access is limited
by both the delegated permissions granted to that client and the rights of the signed-in
user.

Use this mode when flexibility is intentional and the operator can reliably select the
correct account and tenant during sign-in.

## Fixed-tenant Direct mode

Supply one tenant ID to enforce the authority used for authentication and Graph calls:

```powershell
Show-WindowsDeviceLink -TenantId '<tenant-id>'
```

The GUI shows no tenant selector. The operator cannot redirect the workflow to another
tenant. This is useful for customer-specific WinPE media, scripts, or support workflows.

An explicit `TenantId` cannot be combined with a local tenant catalog because that would
create two competing sources for the target tenant.

## Delegated catalog Direct mode

Supply a friendly tenant catalog and use `Interactive` or `DeviceCode` authentication:

```powershell
Show-WindowsDeviceLink `
    -Method DeviceCode `
    -ClientId '<multitenant-app-client-id>' `
    -TenantsPath 'E:\Config\tenants.json'
```

The operator must select a tenant before signing in. The selected tenant becomes the
authentication authority. A multitenant app registration can use the same Client ID in
every tenant where its service principal exists and delegated consent has been granted.
The signed-in user must also have sufficient rights in the selected tenant.

Changing the selected tenant invalidates the current GUI session. Microsoft sign-in may
reuse an existing SSO session, but WindowsDeviceLink must still obtain a new delegated
access token issued by the newly selected tenant. A token issued by one tenant is never
used for Graph operations in another tenant.

## Application catalog Direct mode

Use a catalog with an app-only authentication method such as `Certificate`,
`CertificateThumbprint`, or `ClientSecret`. No user signs in interactively. The operator
selects a tenant and WindowsDeviceLink automatically requests an app-only token from that
tenant.

The same application credential can be presented to every tenant where the multitenant
application has a service principal, the required application permissions, and admin
consent. Access tokens remain tenant-specific: selecting another tenant requires a token
issued by that tenant. Implementations may cache valid tokens in memory by tenant ID,
but must never treat one token as valid for the whole catalog.

This route places an application credential on, or within reach of, the executing
Windows or WinPE environment. Prefer a certificate over a client secret and assess the
impact of distributing a credential with application permissions. For broadly deployed
WinPE media or powerful multitenant permissions, use Backend mode instead.

In the GUI, app-only methods do not show **Sign in** because there is no user session to
establish. Selecting a catalog tenant scopes subsequent **Refresh cloud** or
**Register device** actions; token acquisition happens as part of that action.

## Backend mode — recommended for multitenant

Backend mode is activated with `BackendUri` and `BackendApiKey`:

```powershell
$apiKey = Read-Host 'WindowsDeviceLink API key' -AsSecureString

Show-WindowsDeviceLink `
    -BackendUri 'https://<app>.azurewebsites.net/api/devicelink' `
    -BackendApiKey $apiKey
```

The Function App provides the authoritative tenant catalog and keeps Microsoft Graph
credentials in Azure. The device receives neither the Graph certificate nor a client
secret. The backend checks every configured tenant before deciding what to do.

Backend mode supports:

- complete lookup across configured tenants;
- friendly centrally managed tenant names;
- New and no-op decisions;
- verified tenant-to-tenant Move;
- local DeviceLink identity renewal when required;
- target-state verification and centralized diagnostic correlation.

The API key authenticates the device to the Function App; it is not a Microsoft Graph
token. A backend failure never silently falls back to Direct mode.

## Authentication and token boundaries

Both delegated and application authentication use an app registration:

| Authentication | Executing identity | Graph permissions | Interactive user |
|---|---|---|---|
| Delegated | App registration plus user | Delegated | Yes |
| Application | App registration only | Application | No |
| Backend | Function App's configured app identity | Application | No Graph login on the device |

A multitenant app registration provides a reusable application identity, not a universal
access token. Microsoft Entra issues a separate token for each target tenant. The Client
ID and certificate or secret may be reused where consent exists; the token may not.

## Functional and security differences

| Capability | Direct | Backend |
|---|---:|---:|
| Operate in one known target tenant | Yes | Yes |
| Local or HTTPS friendly-name catalog | Yes | Function catalog |
| Prove absence from every configured tenant | No | Yes |
| Discover the current source tenant | No | Yes |
| Verified cross-tenant Move | No | Yes |
| Keep Graph application credentials off the endpoint | Delegated only | Yes |
| Central tenant allow-list and audit correlation | No | Yes |
| Useful without Azure infrastructure | Yes | No |

## Decision contract

| Proven state | Decision | Renew local identity |
|---|---|---|
| Direct target absent, firmware 2/4 | New | No |
| Direct target present | None | No |
| Backend: absent everywhere, firmware 2/4 | New | Yes |
| Backend: absent everywhere, stale firmware 4/4 | New | Yes |
| Backend: present in target | None | No |
| Backend: present in another tenant | Move | Yes |
| Backend lookup incomplete or ambiguous | Block | No mutation |

Assignment results expose `OperationMode`, `Decision`, `ReasonCode`, `Changed`,
`RetrySafe`, and `RecommendedAction`. An uncertain mutation requires a fresh read; it
is never blindly retried.

## Practical recommendation

- Choose **Account-based Direct** for simple interactive work in one tenant at a time.
- Choose **Fixed-tenant Direct** when the target must be enforced by configuration.
- Choose **Delegated catalog Direct** only when operators need a controlled list but no
  Function App is available.
- Choose **Application catalog Direct** only after accepting the endpoint credential
  exposure and operational limitations.
- Choose **Backend** whenever tenant-to-tenant movement, authoritative lookup, central
  credential protection, or repeatable multitenant operations matter.
