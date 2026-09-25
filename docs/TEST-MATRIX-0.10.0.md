# WindowsDeviceLink 0.10.0 test matrix

This matrix records both the focused release gate for `0.10.0-preview1` and the
broader validation work planned after that preview. It separates automated contract
coverage from live validation on Windows 11, Windows PE, Microsoft Graph, and the
optional Function backend.

Do not record real tenant names, tenant IDs, application IDs, device identifiers,
service endpoints, policy names, credentials, or tokens in this document, test
fixtures, screenshots, or public logs.

## 0.10.0-preview1 release gate

The preview is scope-frozen. Its release is gated by the behavior changed in this
development cycle rather than by repeating every authentication combination that was
validated in earlier previews.

- [ ] all hardware-independent CI checks pass against the staged package;
- [ ] public Backend CLI smoke test covers tenant catalog and tenant assignment;
- [ ] Backend GUI smoke test covers startup, status, assignment and offboarding;
- [ ] the Windows 11 and AMD64 WinPE core paths remain operational;
- [ ] the public diff contains no environment-specific or sensitive data;
- [ ] no administrator-supplied Microsoft runtime DLL is present in Git or the package;
- [ ] the installed Gallery artifact receives a final smoke test.

The full authentication and screenshot matrices below are follow-up validation and do
not expand the scope of `0.10.0-preview1`.

### Focused manual smoke sequence

Run this sequence from a clean Windows PowerShell 5.1 session after installing or
importing the exact release candidate. Keep the real URI, key, tenant selection, and
output out of committed logs.

```powershell
$backendUri = '<function-base-uri>'
$apiKey = Read-Host 'Function API key' -AsSecureString

Get-WindowsDeviceLinkBackendTenant `
    -BackendUri $backendUri `
    -BackendApiKey $apiKey

Get-WindowsDeviceLinkStatus | Format-List *

Set-WindowsDeviceLinkTenant `
    -BackendUri $backendUri `
    -BackendApiKey $apiKey `
    -TargetTenantName '<catalog-display-name>' `
    -WhatIf | Format-List *
```

Verify the reported `Decision`, source, target, `Changed=False`, reason code, and
recommended action before considering a real assignment. Do not remove `-WhatIf` when
the predicted New, Move, Repair, or no-op decision is not the intended outcome.

Then open the Backend GUI from the same release candidate:

```powershell
Show-WindowsDeviceLink `
    -BackendUri $backendUri `
    -BackendApiKey $apiKey
```

Confirm automatic startup refresh, **Refresh cloud**, **Refresh local**, current action
availability, and clean close/reopen behavior. State-changing GUI actions only need to
be repeated when their current lifecycle state makes the intended result unambiguous.

## CLI usability goals

The command line must support two equally important audiences.

### Operators

- common workflows require as few parameters as the selected mode allows;
- delegated sign-in does not require `TenantId` unless the tenant must be explicit;
- command names and confirmation prompts make state-changing actions clear;
- progress, success, no-op, blocked, and recovery guidance are understandable;
- errors identify the failing stage without exposing credentials or tokens;
- returned objects remain useful when formatted by PowerShell's default view.

### Automation

- app-only and backend routes never require an interactive prompt;
- objects, property names, reason codes, and exit behavior are predictable;
- repeated execution is idempotent or returns an explicit safe decision;
- `-WhatIf`, confirmation behavior, configurable time-outs, and retry guidance work;
- secrets remain in memory and never appear in results, verbose output, or errors;
- commands can be composed through the PowerShell pipeline without parsing display text.

## Live CLI validation

Use generic labels in retained evidence. Mark a row complete only after checking the
returned object as well as the console presentation.

| Environment | Route | Authentication | Persona | Required validation | Status |
|---|---|---|---|---|---|
| Windows 11 | Backend | Function API key | Operator | public catalog and assignment commands; unified public status/offboarding CLI requires follow-up design | Pending |
| Windows 11 | Backend | Function API key | Automation | unattended catalog/assignment, object contract, no-op, time-out and retry-safe result | Pending |
| Windows 11 | Direct | Interactive | Operator | sign-in-selected tenant, status, register, completion, removal | Pending |
| Windows 11 | Direct | DeviceCode | Operator | status, register, completion, removal, token reuse | Pending |
| Windows 11 | Direct | ClientSecret | Automation | unattended lookup, registration, verification, removal | Pending |
| Windows 11 | Direct | CertificateThumbprint | Automation | unattended lookup, registration, verification, removal | Pending |
| Windows 11 | Direct | AccessToken | Automation | caller-supplied token, tenant resolution, lookup and mutation | Pending |
| Windows 11 | Direct | EnvironmentVariable | Automation | environment credentials, lookup and mutation without prompts | Pending |
| Azure host | Direct | ManagedIdentity | Automation | identity selection, lookup and permitted mutation without prompts | Not yet scheduled |
| Windows PE AMD64 | Backend | Function API key | Operator | runtime, public catalog and assignment commands; status/offboarding remain GUI-backed in 0.10.0 | Pending |
| Windows PE AMD64 | Backend | Function API key | Automation | unattended catalog/assignment, no-op, time-out and retry behavior | Pending |
| Windows PE AMD64 | Direct | DeviceCode | Operator | sign-in, status and pre-association using BYO-DLL | Pending |

For `Certificate`, `CertificateThumbprint`, and `CertificateSubjectName`, automated
tests must validate each parameter set. At least one certificate-based route must be
validated live end to end.

## Command-level CLI checks

Run the applicable commands individually instead of treating only the composite GUI
or initializer as evidence.

- [ ] `Test-WindowsDeviceLinkRuntime`
- [ ] `Test-WindowsDeviceLinkSupport`
- [ ] `Test-WindowsDeviceLinkPreflight`
- [ ] `Get-WindowsDeviceLink`
- [ ] `Get-WindowsDeviceLinkFirmwareState`
- [ ] `Get-WindowsDeviceLinkLocalAssociation`
- [ ] `Get-WindowsDeviceLinkAssociation`
- [ ] `Get-WindowsDeviceLinkStatus`
- [ ] `Get-WindowsDeviceLinkBackendTenant`
- [ ] `Register-WindowsDeviceLink`
- [ ] `Initialize-WindowsDeviceLink`
- [ ] `Set-WindowsDeviceLinkTenant`
- [ ] `Complete-WindowsDeviceLinkAssociation`
- [ ] `Remove-WindowsDeviceLinkAssociation`
- [ ] `Reset-WindowsDeviceLinkFirmwareState`
- [ ] `Export-WindowsDeviceLinkCsv`
- [ ] `Test-WindowsDeviceLinkAssociationJwt`
- [ ] `Get-WindowsDeviceLinkRepairPlan`

For every state-changing command, verify the successful path, safe repetition/no-op,
invalid input, denied authorization, transport failure, and `-WhatIf` or confirmation
behavior where supported.

## GUI authentication validation

| Environment | Route | Authentication | Required validation | Status |
|---|---|---|---|---|
| Windows 11 | Backend | Function API key | automatic load and complete action lifecycle | Complete; repeat for release build |
| Windows 11 | Direct | Interactive | sign in, switch account, cloud refresh and action lifecycle | Pending |
| Windows 11 | Direct | DeviceCode | sign in once, token reuse, cloud refresh and action lifecycle | Pending |
| Windows 11 | Direct | ClientSecret | automatic app-only session and action lifecycle | Pending |
| Windows 11 | Direct | CertificateThumbprint | automatic app-only session and action lifecycle | Pending |
| Windows 11 | Direct | AccessToken | cloud refresh and at least one verified mutation | Pending |
| Windows 11 | Direct | EnvironmentVariable | automatic app-only session without prompts | Pending |
| Windows PE AMD64 | Backend | Function API key | automatic load, pre-association and move | Complete; repeat for release build |
| Windows PE AMD64 | Direct | DeviceCode | sign in, status and pre-association using BYO-DLL | Pending |

Managed identity is not considered live GUI-validated unless the GUI is run on an
Azure-hosted Windows environment with an assigned identity.

## GUI behavior and screenshot set

Capture screenshots only after the final release UI has passed the matrix.

- [ ] initial and loading state;
- [ ] Windows 11 association;
- [ ] Windows PE pre-association with **Associate** unavailable;
- [ ] generic tenant selection and association actions;
- [ ] offboarding actions in a representative state;
- [ ] successful CSV export;
- [ ] optional successful repair or move result.

Use real application output but redact or replace all environment-specific data.
Review the title bar, cards, activity log, status bar, dialogs, paths, and background
windows before committing an image. Prefer a fresh generic test configuration over
manual redaction when practical.

## Extended-validation evidence

For the extended validation milestone:

- [ ] all hardware-independent CI and staged-package tests pass;
- [ ] retained live-test notes contain no sensitive or customer-specific data;
- [ ] public screenshots have completed a separate privacy review;
- [ ] the staged package contains no administrator-supplied Microsoft runtime DLL;
- [ ] limitations and combinations that were not live-tested are stated explicitly;
- [ ] the installed Gallery artifact receives a final Windows 11 and Windows PE smoke test.
