# WindowsDeviceLink operator GUI

`Show-WindowsDeviceLink` opens a compact operator dashboard for inspecting and managing Windows Autopilot device preparation Device Association.

## Start the GUI

Direct mode is the default. On full Windows the sign-in is Interactive; Windows PE
defaults to DeviceCode. No tenant ID is required when the sign-in context should choose
the tenant:

```powershell
Show-WindowsDeviceLink
```

Supply `-TenantId` only when Direct mode must target one tenant explicitly, or use a
tenant catalog when an operator needs friendly choices.

Backend mode is enabled explicitly for complete multitenant lookup and Move:

```powershell
$apiKey = Read-Host 'WindowsDeviceLink API key' -AsSecureString

Show-WindowsDeviceLink `
    -BackendUri 'https://<app>.azurewebsites.net/api/devicelink' `
    -BackendApiKey $apiKey
```

The GUI retrieves the allowed tenant catalog from the Function App and automatically
checks the current cloud association when it opens. Device, Local association, and
Cloud association are shown together. The dedicated **Target tenant** row contains the
backend selector. After selecting a tenant, choose **Pre-associate** or, on supported
full Windows, **Associate** in the separate **Device association** row. Each action
performs its own fresh cloud check before changing state.
Diagnostic, export, recovery, and offboarding actions are available in the same view.

Backend mode and Direct-mode Graph authentication are deliberately separate. Do not combine
`-BackendUri`/`-BackendApiKey` with `-Method`, `-Tenants`, `-TenantsUri`, or
`-TenantsPath`.

In Direct mode, use either one explicit `-TenantId` or one of the tenant-catalog
parameters. Combining an explicit tenant with a catalog is rejected because it would
make the effective target ambiguous.

On full Windows, `Interactive` authentication is used by default unless `-Method` is specified.

On Windows PE, `DeviceCode` is used by default because interactive browser authentication is not available there.

Windows PE also requires the **Bring Your Own DLL (BYO-DLL)** compatibility path unless the environment already provides a usable registered DeviceLink runtime. Supply a compatible `Windows.Management.Service.dll` in the module `Runtime` directory or pass `-WindowsManagementServicePath`. The GUI disables **Associate** in WinPE because normal WinPE usage ends at pre-association; Windows 11 OOBE completes the association. See [WINPE-WORKFLOW.md](WINPE-WORKFLOW.md).

Direct mode opens without authenticating and initially loads only local device and
firmware state. Choose **Sign in** in the **Target tenant** row first. After
successful authentication, the GUI reuses that session
for subsequent cloud actions. DeviceCode tokens are retained only in memory, renewed
when required, cleared when the selected tenant changes, and discarded when the GUI
closes. Backend mode continues to load cloud state automatically because it does not
require an interactive Graph sign-in on the device.

After a successful Direct-mode sign-in, **Sign in** changes to **Sign out**. Signing
out clears the in-memory authentication context and unlocks a configured tenant
selector. While signed in, that selector remains locked so a token cannot be reused
silently for another target tenant.
Single-tenant Direct mode deliberately has no tenant selector: the authenticated tenant
is authoritative unless `-TenantId` fixed it explicitly. When a local tenant catalog is
configured, selecting a target tenant is mandatory before sign-in or any cloud action;
authentication is then scoped to that selected tenant.

**Sign in** is shown only for delegated `Interactive` and `DeviceCode` methods. App-only
methods do not represent a user as signed in: their credential is used non-interactively
when **Refresh cloud**, **Pre-associate**, **Associate**, or another cloud action runs.

## Authentication

Select an authentication method with `-Method`.

| Method | Typical parameters |
|---|---|
| `Interactive` | Optional `-TenantId`, optional `-ClientId` |
| `DeviceCode` | Optional `-TenantId`, optional `-ClientId` |
| `ClientSecret` | `-TenantId`, `-ClientId`, `-ClientSecret` |
| `AccessToken` | `-AccessToken`; `-TenantId` can be supplied when needed |
| `Certificate` | `-TenantId`, `-ClientId`, `-Certificate`; optional `-SendCertificateChain` |
| `CertificateThumbprint` | `-TenantId`, `-ClientId`, `-CertificateThumbprint`; optional `-SendCertificateChain` |
| `CertificateSubjectName` | `-TenantId`, `-ClientId`, `-CertificateSubjectName`; optional `-SendCertificateChain` |
| `EnvironmentVariable` | Uses the documented Azure/Entra environment variables |
| `ManagedIdentity` | Optional `-ClientId` for a user-assigned identity |

Examples:

```powershell
Show-WindowsDeviceLink -Method Interactive
```

```powershell
Show-WindowsDeviceLink `
    -Method DeviceCode `
    -TenantId '<tenant-id>'
```

```powershell
$secret = Read-Host 'Client secret' -AsSecureString

Show-WindowsDeviceLink `
    -Method ClientSecret `
    -TenantId '<tenant-id>' `
    -ClientId '<client-id>' `
    -ClientSecret $secret
```

The GUI uses the existing WindowsDeviceLink authentication helpers and public cmdlets.
It adds only session-scoped orchestration so an operator does not need to repeat the
same DeviceCode sign-in for every action.

## Tenant selection

### Backend mode

The Function App provides tenant IDs and friendly names. The selected tenant is always
an explicit target; the backend never selects one on the operator's behalf.

The **Pre-associate** action performs one of these guarded outcomes after a complete
multitenant lookup:

| Current cloud state | Result |
|---|---|
| Not found in any configured tenant | Pre-associate in the selected tenant |
| Already present in the selected tenant | No change |
| Present in another configured tenant | Renew the local DeviceLink identity, then perform and verify the move |

The same orchestration is available from the command line through
`Set-WindowsDeviceLinkTenant`.

### Direct mode with an explicit tenant

Use `-TenantId` when the GUI should use one explicit tenant:

```powershell
Show-WindowsDeviceLink -TenantId '<tenant-id>'
```

No selector is shown for this single-target route. When no explicit tenant or tenant
catalog is supplied, no selector is shown either and the authenticated Microsoft Entra
context is authoritative.

### Friendly tenant list

This mode does not require a Function App. The list only supplies display names and
tenant IDs; authentication and Graph actions still use the selected direct method.
The operator must select one tenant before signing in. Changing the selection clears
the current GUI authentication session and requires a new sign-in for the new tenant.

```powershell
Show-WindowsDeviceLink -Tenants @{
    'Tenant Alpha' = '11111111-1111-1111-1111-111111111111'
    'Tenant Beta' = '22222222-2222-2222-2222-222222222222'
    'Tenant Gamma' = '33333333-3333-3333-3333-333333333333'
}
```

### Local JSON

```powershell
Show-WindowsDeviceLink `
    -TenantsPath 'E:\Config\tenants.json'
```

### HTTPS JSON

```powershell
Show-WindowsDeviceLink `
    -TenantsUri 'https://config.example.com/windowsdevicelink/tenants.json'
```

Both JSON options use the same simple schema:

```json
{
  "Tenant Alpha": "11111111-1111-1111-1111-111111111111",
  "Tenant Beta": "22222222-2222-2222-2222-222222222222",
  "Tenant Gamma": "33333333-3333-3333-3333-333333333333"
}
```

`-TenantsUri` accepts only an absolute HTTPS URI. Tenant values must be valid GUIDs. These files should contain names and tenant IDs only; do not store credentials or secrets in them.

When multiple tenant sources are supplied, precedence is:

```text
TenantsUri -> TenantsPath -> Tenants
```

Explicit `-Tenants` values therefore have the highest priority for duplicate names.

The same JSON is available to command-line scripts:

```powershell
$tenant = Get-WindowsDeviceLinkTenantCatalog `
    -Path 'E:\Config\tenants.json' `
    -Name 'Tenant Alpha'

Get-WindowsDeviceLinkAssociation `
    -SerialNumber '<serial-number>' `
    -Method Interactive `
    -TenantId $tenant.TenantId
```

This is tenant selection, not centralized orchestration. Direct mode does not search
every catalog tenant and cannot safely infer or perform a cross-tenant Move. Select the
correct tenant explicitly; use Backend mode when lookup and verified moves are
required.

## Windows 11 and Windows PE

| Capability | Windows 11 | Windows PE |
|---|---|---|
| Local DeviceLink / firmware inspection | Yes | Yes |
| Tenant-side online lookup | Yes | Yes, when authentication/network prerequisites are available |
| DeviceLink CSV export | Yes | Yes |
| Pre-associate | Yes | Yes |
| Associate | Yes | No; use pre-association and let full Windows/OOBE complete Device Association |
| Remove cloud | Yes | Yes |
| Reset local | Yes | Yes |
| Remove both | Yes | Yes, when cloud authentication/network prerequisites are available |
| Default GUI authentication | `Interactive` | `DeviceCode` |
| DeviceLink runtime | Registered Windows runtime | Administrator-supplied compatible runtime may be required |

### Windows PE runtime DLL

WindowsDeviceLink does **not** redistribute Microsoft's `Windows.Management.Service.dll`.

When the compatible runtime DLL is not available from the documented module runtime location, provide it explicitly:

```powershell
Show-WindowsDeviceLink `
    -WindowsManagementServicePath 'E:\Windows.Management.Service.dll'
```

The same parameter can be combined with tenant and authentication options:

```powershell
Show-WindowsDeviceLink `
    -WindowsManagementServicePath 'E:\Windows.Management.Service.dll' `
    -TenantsPath 'E:\Config\tenants.json'
```

The DLL must come from an administrator-controlled compatible Windows source. See [INSTALLATION.md](INSTALLATION.md) and [WINPE-WORKFLOW.md](WINPE-WORKFLOW.md) for the validated WinPE workflow and support boundary.

## Actions

- **Pre-associate** — ensure the device is pre-associated with the selected target. In Backend mode this can perform a verified New, no-op, Move, or same-tenant Repair as required.
- **Associate** — first ensure the selected tenant assignment, then explicitly complete and verify the device-side association on supported full Windows. This action is disabled in WinPE.
- **Sign in** — establish the target tenant for the current Direct-mode UI session and immediately load the cloud association.
- **Sign out** — clear the current Direct-mode authentication context; with a tenant catalog, this also unlocks target selection for the next sign-in.
- **Refresh local** — refresh local DeviceLink identity and firmware information.
- **Refresh cloud** — refresh tenant-side Device Association state using the selected tenant context.
- **Export CSV** — export the Microsoft-generated DeviceLink CSV.
- **Remove cloud** — remove only the tenant-side Device Association record.
- **Reset local** — reset only local DeviceLink firmware state.
- **Remove both** — verify/remove cloud state first, then reset local DeviceLink firmware state.

State-changing actions delegate to the existing guarded public cmdlets and retain their safety behavior.

The dashboard uses a two-by-two status layout: Device and Connection above Local
association and Cloud association. Device separates manufacturer, model, serial number,
and operating system. Connection explains the active mode, authentication route,
endpoint, and tenant scope. The Cloud association card keeps the current state, friendly
tenant name, Association ID, and last-check time together. The Actions section contains
the target tenant selector and the **Pre-associate** and **Associate** actions. In Backend mode,
Pre-associate performs the complete lookup, decision, identity renewal, tenant assignment, and verification workflow itself. Associate continues with supported device-side completion.
**Refresh cloud** remains available for an explicit diagnostic refresh. Direct-only
sign-in and onboarding actions are hidden while Backend mode is active.

## Activity log

The Activity pane shows the delegated command, authentication progress, important lifecycle phases, compact result fields and final status.

Large nested status objects are intentionally omitted from the normal GUI activity view. Use the CLI diagnostics when complete object output is required.
