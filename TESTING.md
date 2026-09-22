# WindowsDeviceLink validation matrix

Last updated: 2026-09-20

The primary Windows Autopilot Device Preparation Device Association workflow has been validated on physical AMD64 hardware across Windows 11 and AMD64 Windows PE.

## Confirmed direct functionality

| Area | Windows 11 | Windows PE |
|---|---:|---:|
| Runtime support detection | Pass | Pass |
| DeviceLink generation | Pass | Pass |
| Graph pre-association | Pass | Pass |
| Duplicate / HTTP 409 handling | Pass | Pass |
| Native `.devicelink.csv` generation | Pass | Pass |
| CSV accepted by Intune | Pass | Pass |
| Export to directory / root | Pass | Pass |
| Device-code authentication | Pass | Pass |
| Client-secret authentication | Pass | Pass |
| Existing access token | Pass | Pass |
| Environment-variable authentication | Pass | Pass |
| Certificate object | Pass | Pass |
| Certificate thumbprint | Pass | Pass |
| Certificate subject name | Pass | Pass |
| Device Association lookup: no match | Pass | Pass via status lookup |
| Device Association lookup by serial number | Pass | Pass via status lookup |
| Device Association lookup by association ID | Pass | Not repeated |
| Device Association removal by serial number | Pass | Pass |
| Device Association removal by association ID | Pass | Not repeated |
| `Get-WindowsDeviceLinkStatus` local status | Pass | Pass |
| `Get-WindowsDeviceLinkStatus -Online` with preassociation | Pass | Not repeated |
| `Get-WindowsDeviceLinkStatus -Online` with association | Pass | Pass |
| `Test-WindowsDeviceLinkHealth` local | Pass | Pass |
| `Test-WindowsDeviceLinkHealth` online associated | Pass | Pass |
| `Initialize-WindowsDeviceLink` LocalOnly -> Preassociated | Pass | Not repeated |
| `Initialize-WindowsDeviceLink` preassociated idempotency | Pass | Not repeated |
| `Initialize-WindowsDeviceLink` associated idempotency | Pass | Pass |
| `Get-WindowsDeviceLinkFirmwareState` | Pass | Pass |
| Firmware timestamp, whole seconds | Pass | Pass-compatible parser |
| Firmware timestamp, fractional seconds | Pass | Pass |
| Firmware reset operation | Pass | Pass |
| Firmware reset `-WhatIf` | Pass | Pass |
| Post-reset firmware verification | Pass | Pass |
| Post-reset reboot remains 0/4 until DeviceLink identity retrieval | Pass | Not repeated |
| New base identity materialized by DeviceLink retrieval after reset | Pass | Pass (identity created after WinPE reset) |
| Published PSGallery package import (0.4.4-preview1) | Pass | Pass |
| Published package support probe (0.4.4-preview1) | Pass | Pass with user-supplied DLL |
| Published package firmware read (0.4.4-preview1) | Pass | Pass |
| Published package local status (0.4.4-preview1) | Pass | Pass |
| Published package online associated health (0.4.4-preview1) | Pass | Pass |

## 0.4.4 command-boundary, Device Association, health and initialization validation

`0.4.4-preview1` separates the local DeviceLink identity from tenant-side Device Association state and adds combined status, health classification and safe idempotent initialization.

The intended command boundaries are:

```text
Get-WindowsDeviceLink
    local DeviceLink identity only

Get-WindowsDeviceLinkFirmwareState
    local UEFI state only

Get-WindowsDeviceLinkAssociation
    tenant-side Intune/Graph Device Association only

Get-WindowsDeviceLinkStatus
    combined diagnostic view; local by default, cloud only with -Online

Test-WindowsDeviceLinkHealth
    classifies a status object without changing state

Initialize-WindowsDeviceLink
    safe orchestration; creates a missing preassociation only for validated LocalOnly state
```

### Physical Windows 11 validation

Validated on physical AMD64 Windows 11 devices, including OOBE:

- `Get-WindowsDeviceLink` returned the local identity without authentication or Graph activity;
- the former `Get-WindowsDeviceLink -Online` parameter is no longer present;
- Device Association lookup returned no result before registration;
- `Register-WindowsDeviceLink -Method DeviceCode` created a `preassociated` record;
- `Get-WindowsDeviceLinkAssociation` returned that record by serial number and association ID;
- `Get-WindowsDeviceLinkStatus` returned runtime, local identity and firmware state without cloud authentication;
- a base/preassociated local identity showed two of four known firmware variables present;
- `Get-WindowsDeviceLinkStatus -Online` correlated the same local identity with the tenant-side `preassociated` record;
- `Test-WindowsDeviceLinkHealth` classified local 2/4 state without cloud lookup as `LocalBaseIdentity`;
- the same local 2/4 state with a confirmed absent tenant association was classified as `LocalOnly`;
- `Initialize-WindowsDeviceLink -WhatIf` on `LocalOnly` reported `Action=Register` and `Changed=False`;
- a real initialization transitioned `LocalOnly` to `Preassociated` and verified the result through the read path;
- an already preassociated device returned `Action=None`, `Changed=False`, `BeforeState=Preassociated`, `AfterState=Preassociated`;
- an associated device with 4/4 firmware returned `Action=None`, `Changed=False`, `BeforeState=Associated`, `AfterState=Associated`;
- DeviceCode initialization reuses one access token for lookup, registration where required, and verification.

### Physical AMD64 WinPE validation for 0.4.4

The same physical associated Dell device was validated first in Windows 11 OOBE and then in AMD64 WinPE.

Validated in WinPE:

- `Test-WindowsDeviceLinkSupport` reported `Environment=WindowsPE`, `Architecture=AMD64`, `Supported=True`, `DllSource=Bundled` and `ActivationMode=DirectDll` when a compatible runtime DLL was supplied;
- `Get-WindowsDeviceLinkFirmwareState` returned all four known firmware variables as present;
- `Get-WindowsDeviceLinkStatus` worked fully locally in WinPE with `DeviceLinkPresent=True`, `FirmwareStateComplete=True`, `FirmwareVariablesPresent=4/4`, `CloudChecked=False`;
- local health was classified as `LocalCompleteFirmwareState` with informational severity;
- `Get-WindowsDeviceLinkStatus -Online -Method DeviceCode` successfully correlated the WinPE identity with the existing tenant-side Device Association;
- online health returned `State=Associated`, `CloudChecked=True`, `AssociationPresent=True`, `AssociationState=associated`, `FirmwareVariablesPresent=4/4` and no association error;
- `Initialize-WindowsDeviceLink -Method DeviceCode` on the already associated device returned `Action=None`, `Changed=False`, `BeforeState=Associated`, `AfterState=Associated` and performed no registration or firmware change;
- one DeviceCode sign-in was used for the initializer operation.

No tenant IDs, serial numbers, Link IDs, SMBIOS UUIDs, association IDs or device-code values from the live validation are retained in this document.

## Health regression validation

The hardware-independent health regression suite was run successfully under Windows PowerShell 5.1.

Validated classifications include:

- Unsupported;
- IdentityUnavailable;
- FirmwareUnavailable;
- CloudUnknown;
- FirmwareStateUnknown;
- NoFirmwareState;
- IncompleteFirmwareState;
- LocalBaseIdentity;
- LocalCompleteFirmwareState;
- LocalOnly;
- CloudAssociationMissingWithCompleteFirmware;
- Preassociated;
- PreassociatedUnexpectedFirmwareState;
- Associated;
- AssociatedIncompleteFirmwareState;
- UnclassifiedAssociationState.

The suite also validates invariants preventing incomplete associated firmware from being reported as healthy `Associated`, and preventing cloud lookup failures from being interpreted as `LocalOnly`/`NotAssociated`.

## Online method validation

The `0.4.4-preview1` API places authentication on explicit tenant-side operations rather than on `Get-WindowsDeviceLink`.

The parameter regression suite passed, including validation that:

- `Get-WindowsDeviceLink` no longer accepts `-Online`;
- webhook registration requires `WebhookUri` and rejects cloud-only authentication inputs;
- delegated `Interactive` and `DeviceCode` authentication can omit `TenantId`; `DeviceCode` defaults to the `organizations` authority;
- Device Association lookup requires exactly one selector;
- ClientSecret operations require the complete credential input set.

Validated authentication methods continue to cover DeviceCode, Interactive, ClientSecret, AccessToken, Certificate, CertificateThumbprint, CertificateSubjectName, EnvironmentVariable and ManagedIdentity where applicable. Webhook registration remains an explicit `Register-WindowsDeviceLink -Method Webhook` operation.



## Operator GUI validation

`Show-WindowsDeviceLink` has been exercised on physical AMD64 Windows 11 hardware. Windows PE GUI support is implemented and requires dedicated live validation on the existing AMD64 WinPE test environment before RC1.

Validated GUI behavior includes:

- startup on full Windows without materializing a new DeviceLink identity implicitly;
- module version and Preview status in the window title;
- Windows 11 environment display;
- local firmware / tenant-correlation display;
- tenant selector with friendly names supplied through `-Tenants`;
- default `Interactive` authentication and alternate `-Method` contract;
- online cloud-state refresh;
- CSV export;
- pre-association;
- full association with live Information-stream progress;
- cloud-only offboarding;
- local-only firmware reset;
- fail-safe full offboarding that verifies cloud state before local reset;
- consistent disabled action state while operations are running;
- activity logging and clear action;
- compact full-Windows layout with conditional outer scrolling;
- native Windows confirmation dialogs.

The hardware-independent `Gui-Contract-Validation.ps1` suite validates export, authentication defaults, tenant-selector contract, WinPE guardrails and delegation to existing public cmdlets.

### Windows PE GUI validation matrix

Before RC1, validate on physical AMD64 Windows PE:

- GUI startup with WinForms available;
- automatic runtime discovery where configured;
- explicit `-WindowsManagementServicePath`;
- default `Interactive` authentication;
- explicit `DeviceCode` authentication;
- local refresh;
- online Device Association lookup;
- DeviceLink CSV export;
- pre-association;
- `Full associate` visible but disabled;
- cloud-only offboarding;
- local firmware reset;
- fail-closed full offboarding.

The GUI must remain usable when the DeviceLink runtime is unavailable: runtime-dependent actions are disabled and the blocking reason is surfaced through Activity/tooltips rather than terminating the dashboard.

## Local tenant discovery validation

Validated on a physical Microsoft Surface Laptop 3 running AMD64 Windows 11.

The public `Get-WindowsDeviceLinkLocalAssociation` command was exercised across the lifecycle and confirmed to remain fully local (`CloudChecked=False`).

Observed sequence:

- associated `4/4`: current-LinkId registry `TenantIdHint` and JWT `tenantId` both present and equal -> `CorrelatedLocalSources`;
- cloud Device Association deleted while UEFI remained `4/4`: local tenant ID remained readable;
- UEFI reset to `0/4`: old registry hints remained but no tenant was selected because no current LinkId existed;
- new base identity materialized to `2/4`: no matching current-LinkId TenantIdHint existed and local tenant remained unavailable;
- Graph preassociation alone: still no current-LinkId TenantIdHint;
- read-only native discovery: wrote the current-LinkId `TenantIdHint` and `DiscoveryUrl` while firmware remained `2/4`;
- full completion: JWT variables returned and the JWT `tenantId` again matched the registry hint.

The hardware-independent `Local-Association-Validation.ps1` regression suite passed for matching sources, registry-only, JWT-only, conflict and unavailable states. The conflict path returns no selected TenantId.

Independent online JWT validation research confirmed structural/time/device correlation but did not locate a published signing key for the observed `DeviceTag_<guid>` issuer; signature verification therefore remains `NotPerformed`.
## Firmware lifecycle validation

Validated UEFI namespace:

```text
{B3DE75DA-819C-4FD5-9F01-C3D49E8CBBD7}
```

Validated variables:

```text
DeviceLinkId
DeviceLinkJwtCompressed
DeviceLinkJwtLastWrite
DeviceLinkCreationTimeUtc
```

The raw `DeviceLinkJwtCompressed` value is treated as sensitive and must not be logged or published.

### Observed states

- Clean baseline: all four variables absent.
- After DeviceLink generation: `DeviceLinkId` and `DeviceLinkCreationTimeUtc` present; JWT variables absent.
- After preassociation: same local base identity state; JWT variables still absent.
- Fully associated Windows device: all four variables present.
- Server-side association removal: local firmware state remains until explicitly reset.

### DeviceLinkCreationTimeUtc format

Live validation established that `DeviceLinkCreationTimeUtc` is a UTF-8 ISO-8601 UTC timestamp. At least two representations have been observed on physical hardware:

```text
2026-09-06T12:22:51Z
2026-09-15T07:48:22.972Z
```

The first observed representation was 20 bytes and used whole seconds. A second associated Dell device exposed a 24-byte value with milliseconds. The 0.4.4 parser accepts both whole and fractional seconds.

The fractional-seconds parser was explicitly revalidated in a fresh AMD64 WinPE PowerShell 5.1 session. `DecodedValue` returned the exact UTC text and `ParsedUtc` returned the parsed UTC `DateTime`. `DecodedValue` remained empty for `DeviceLinkId`, `DeviceLinkJwtCompressed` and `DeviceLinkJwtLastWrite`.

`PayloadCreationTimeUtc` is separate: it belongs to the newly generated DeviceLink payload and changes between payload generations. The firmware creation timestamp remains stable across those generations. The module therefore exposes the two concepts separately.

### AMD64 WinPE lifecycle

Validated in WinPE:

1. read clean firmware state;
2. generate DeviceLink;
3. verify base identity variables appeared;
4. create Graph preassociation;
5. remove the server-side association;
6. reset local DeviceLink firmware variables;
7. verify all four variables absent afterward.

### Full Windows reset and identity materialization

A controlled end-to-end offboarding test established the post-reset behavior more precisely:

1. the device started fully associated with all four known UEFI variables present;
2. all four UEFI variables were removed and immediately verified absent with Win32 error `203`;
3. the tenant-side Device Association record was removed successfully by local serial-number autodetection;
4. a follow-up tenant lookup confirmed that no Device Association record remained;
5. after reboot, the firmware state still showed **0/4**;
6. `Get-WindowsDeviceLink` was then invoked;
7. immediately afterward, `DeviceLinkId` and `DeviceLinkCreationTimeUtc` were present again while both JWT variables remained absent, producing the expected base **2/4** state.

Conclusion: reset removes the old local DeviceLink identity. A reboot alone does not necessarily recreate the base identity. A later DeviceLink identity retrieval can materialize a **new** base identity. Reappearance of the base variables does not mean the old tenant association was restored.

## Device Association removal validation

The Device Association removal operation was derived from the Intune admin center request and independently verified as:

```text
DELETE /deviceManagement/tenantAssociatedDevices/{associationId}
```

Validated standalone deletion, removal by serial number, removal by association ID in Windows 11, and removal by serial number from AMD64 WinPE. The cmdlet targets Device Association records (`tenantAssociatedDevices`) and does **not** use the classic Autopilot V1 deletion API.

## Published 0.4.4-preview1 Gallery smoke test

The actual `0.4.4-preview1` package published to PSGallery was tested after publication rather than relying only on the repository checkout.

### Windows 11 OOBE

Validated on physical AMD64 Windows 11 OOBE hardware, including local/online status and health, Device Association lifecycle states, and initializer behavior. `Preassociated` and `Associated` devices were both confirmed idempotent with `Action=None` and `Changed=False`.

### AMD64 Windows PE

The installed Gallery package was then exercised on the same physical associated device in AMD64 WinPE.

Validated findings:

- the installed module reported version `0.4.4` from the Windows PowerShell module path rather than the repository checkout;
- without `Windows.Management.Service.dll`, `Test-WindowsDeviceLinkSupport` correctly reported WinPE/AMD64/direct-DLL mode as unsupported because the runtime DLL was absent;
- after a compatible user-supplied Microsoft DLL was placed in the installed module's `Runtime` directory, support changed to `Supported=True` with `ActivationMode=DirectDll`;
- `Get-WindowsDeviceLinkFirmwareState` returned all four known variables;
- the 24-byte fractional `DeviceLinkCreationTimeUtc` value decoded and parsed successfully while the other firmware values remained undisclosed;
- `Get-WindowsDeviceLinkStatus` returned `Environment=WindowsPE`, `DeviceLinkPresent=True`, `FirmwareStateComplete=True`, `FirmwareVariablesPresent=4/4` and the parsed firmware creation time;
- `Get-WindowsDeviceLinkStatus -Online -Method DeviceCode | Test-WindowsDeviceLinkHealth` returned `State=Associated`, `CloudChecked=True`, `AssociationPresent=True`, `AssociationState=associated` and no association error.

The current WinPE `-SkipPublisherCheck` requirement remains documented as a workaround for the unsigned preview and will be retested after trusted code signing is introduced.

See [`docs/INSTALLATION.md`](docs/INSTALLATION.md) for the supported installation routes and troubleshooting guidance.

## Webhook validation

The webhook/pre-association contract has been validated end-to-end on Windows 11. The current active backend is the Azure Function App; lookup and reconcile have static contract coverage and are being validated live across configured tenants.

See [`docs/WEBHOOK-SCHEMA-v1.md`](docs/WEBHOOK-SCHEMA-v1.md).

## Notes

- Full Windows uses the registered Windows Runtime and system `Windows.Management.Service.dll`.
- WinPE uses direct DLL activation.
- The public PowerShell Gallery package does **not** redistribute `Windows.Management.Service.dll`; WinPE Gallery users must provide a compatible copy themselves.
- Native CSV generation is used; WindowsDeviceLink does not reconstruct the CSV format.
- Firmware access requires `SeSystemEnvironmentPrivilege`; the firmware cmdlets enable it in the current process.
- PowerShellGet `Save-Module` does not exercise the same install/publisher-check path as `Install-Module`; both routes were tested separately in WinPE.

## Published preview

`WindowsDeviceLink 0.8.0-preview1` is the previous preview release. The repository validation described above now covers the `0.9.0-preview1` candidate, including the operator GUI validated on physical AMD64 Windows 11 and AMD64 Windows PE hardware. The GUI lifecycle tests cover pre-association, full association, idempotency, cloud/local/full offboarding, stale local/cloud combinations, tenant-source correlation, DeviceCode token reuse and WinPE CSV export. The multitenant reconcile backend has passed static contract validation but still requires live Azure validation.

## Remaining validation / future work

- Trusted code signing; the initial SignPath Foundation application was reviewed but not approved because the project does not yet have enough external adoption/visibility signals. Revisit SignPath or another trusted signing path later.
- Retest normal WinPE `Install-Module` without `-SkipPublisherCheck` after signing.
- Retest and optimize the beta Device Association serial-number server-side lookup; the current client-side fallback is functionally correct.
- Webhook transport in AMD64 WinPE.
- Second target tenant through the Azure Function allow-list/routing configuration.
- Additional Windows 11 / WinPE builds and OEMs/models.
- Non-Global Microsoft clouds.
