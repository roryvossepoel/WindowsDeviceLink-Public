# DeviceLink Discover/Link research

This document records the research that led to device-side Device Association completion support in WindowsDeviceLink.

## Outcome

The DeviceLink association lifecycle has been reproduced end to end on a controlled physical Windows 11 test device.

Validated transition:

`Preassociated + firmware 2/4` -> discovery -> `ConfigureDeviceLinkAsync` -> `Associated + firmware 4/4`

The successful live run produced all of the following:

- tenant-side Device Association state changed from `preassociated` to `associated`;
- `DeviceLinkJwtCompressed` was written to UEFI;
- `DeviceLinkJwtLastWrite` was written to UEFI;
- all four known DeviceLink firmware variables were present;
- the resulting association JWT parsed successfully as RS256/GZip, was temporally valid, and matched the local DeviceLink identity;
- no retry, reboot, reset, cleanup, or cloud deletion was required.

Cryptographic signature validation of the association JWT remains a separate concern; local validation reports `SignatureValidation = NotPerformed` unless a trusted signature-validation path is explicitly used.

## Runtime contracts

### DeviceLinkUtilities

Existing identity generation/export continues to use:

- runtime class: `ModernDeployment.Autopilot.Core.DeviceLinkUtilities`
- interface IID: `6410BEE7-60A9-5627-9EB2-FEDA7518A4EB`
- slot 6: `ExportDeviceLinkInfoCsvAsync`
- slot 7: `GetDeviceLinkInfoAsync`

### DeviceLinkManager

Live runtime inventory and independent public implementation evidence converged on:

- runtime class: `ModernDeployment.Autopilot.Core.DeviceLinkManager`
- interface IID: `1F79101B-A792-5008-A82A-A4B232229026`

Validated functional contract:

- slot 6: `GetDiscoveryUrlRequestInfo`
- slot 7: `RequestDiscoveryUrlAsync(HSTRING deviceLinkInfo, out asyncOperation)`
- slot 8: `GetConfigureDeviceLinkResult(out int result)`
- slot 9: `ConfigureDeviceLinkAsync(HSTRING discoveryUrl, HSTRING tenantId, null, out asyncOperation)`

The configure async operation exposes the WinRT generic shape:

`IAsyncOperationWithProgress<ConfigureDeviceLinkResult, DeviceLinkConfigurationStatus>`

The completed configure operation returns its result value from the operation's `GetResults` slot.

An important live observation is that `GetConfigureDeviceLinkResult` remained `0` immediately after a successful configure operation even though the async operation completed successfully with result `1` and the firmware/cloud post-state transitioned to complete. WindowsDeviceLink therefore does not use that getter alone as proof of success.

## Discovery validation

A live discovery call on the preassociated test device returned:

- discovery result: `1`
- discovery URL: `https://enrollment.manage.microsoft.com/EnrollmentServer/Discovery.svc`
- tenant ID: the expected tenant
- async status: completed
- configure result before/after discovery: `0`

Discovery did not write association firmware state and did not change the tenant-side association state.

## Configure validation

A single guarded configure operation was then invoked with the discovery URL and tenant ID returned by Windows, with the headers parameter set to null.

Observed result:

- configure async status: completed;
- configure async HRESULT: `0x00000000`;
- configure operation result: `1`;
- retry count: `0`;
- cleanup invoked: false;
- reboot invoked: false.

Immediately afterward the local firmware state was `4/4` and Intune reported the association state as `associated`.

## Public module implementation

The research has been converted into the normal module implementation rather than retained as standalone experimental invocation scripts.

### `Test-WindowsDeviceLinkDiscovery`

Read-only/public discovery command. It:

- obtains the local DeviceLink identity;
- invokes `RequestDiscoveryUrlAsync`;
- returns discovery result, URL, tenant ID, async status, and configure-result observations;
- does not invoke configure or write association state.

### `Complete-WindowsDeviceLinkAssociation`

Guarded state-changing completion command. It:

- runs preflight checks;
- refuses unsupported or unexpected states;
- returns `AlreadyComplete` without invoking configure when firmware/JWT state is already complete;
- performs one discovery followed by at most one `ConfigureDeviceLinkAsync` call;
- performs no automatic retry;
- performs no reset, cleanup, cloud deletion, or reboot;
- verifies firmware `4/4` and a valid identity-matching association JWT after completion.

### `Initialize-WindowsDeviceLink -FullAssociation`

The initializer keeps its previous safe default behavior: create/verify tenant-side preassociation only when appropriate.

Device-side association completion is opt-in through `-FullAssociation`.

With that switch, the supported path is:

`LocalOnly -> Register -> Preassociated -> Complete -> Associated`

Already-associated devices remain idempotent and report `FullAssociationResult = AlreadyAssociated` without invoking configure again.

## Firmware state model

Known variables in namespace `{B3DE75DA-819C-4FD5-9F01-C3D49E8CBBD7}`:

- `DeviceLinkId`
- `DeviceLinkJwtCompressed`
- `DeviceLinkJwtLastWrite`
- `DeviceLinkCreationTimeUtc`

Validated pre-completion state:

- `DeviceLinkId`
- `DeviceLinkCreationTimeUtc`

Validated completed state:

- all four variables present.

## Safety boundary retained in production code

The permanent implementation preserves the safeguards used during research:

1. no destructive automatic repair;
2. no automatic firmware reset;
3. no automatic tenant-record deletion;
4. no reboot;
5. no configure retry;
6. explicit `SupportsShouldProcess` on state-changing public commands;
7. preflight before configure;
8. local post-state verification after configure;
9. raw JWT/device identity material is not written to normal output or logs.

## Test environment

The end-to-end validation was performed on a physical Microsoft Surface Laptop 3 running the registered Windows DeviceLink runtime from:

`C:\Windows\System32\Windows.Management.Service.dll`

Validated DLL version:

`10.0.26100.8875 (WinBuild.160101.0800)`

The exact private/native ABI should still be treated as Windows implementation detail and may change in future Windows builds. Runtime support checks and guarded failure behavior remain required.

## Conclusion

Issue #14's central question is resolved: WindowsDeviceLink can complete the device-side Windows Autopilot Device Association flow after tenant-side preassociation using the native `DeviceLinkManager` contract, and can verify the resulting local association state safely.
