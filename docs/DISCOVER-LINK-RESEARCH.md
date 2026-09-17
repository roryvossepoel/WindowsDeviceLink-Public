# DeviceLink Discover/Link research

This document records research for issue #14. It is intentionally non-implementing: no public Discover/Link command is introduced here.

## Current module boundary

The current native wrapper activates the WinRT runtime class:

`ModernDeployment.Autopilot.Core.DeviceLinkUtilities`

and queries interface IID:

`6410BEE7-60A9-5627-9EB2-FEDA7518A4EB`

The wrapper currently calls only:

- vtable slot 6: `ExportDeviceLinkInfoCsvAsync`
- vtable slot 7: `GetDeviceLinkInfoAsync`

These are sufficient for generating/exporting the TPM-backed DeviceLink identity package but do not complete tenant association.

## Live runtime inventory

Live read-only inventory on the controlled Surface Laptop 3 / Windows 11 build `10.0.26100.8875` reported three IInspectable interfaces on `ModernDeployment.Autopilot.Core.DeviceLinkUtilities`:

- `6410BEE7-60A9-5627-9EB2-FEDA7518A4EB` - the interface already used by WindowsDeviceLink for identity export/generation;
- `00000038-0000-0000-C000-000000000046` - standard `IWeakReferenceSource`;
- `8A3B7C2E-5D1F-4E9A-B6C8-2F0E1D3A4B5C` - additional interface reported directly by `IInspectable.GetIids()` and not injected by the research tool.

Binary IID-context inspection did **not** correlate the third IID with DeviceLink orchestration. Its nearby strings were dominated by `ApplyProperties`, `ConfigureProperties` and `Windows.Management.Service.Autopilot.AutopilotSurfaceHubHelper.*`, so it is no longer treated as the primary Discover/Link candidate.

The runtime is registered under `WindowsManagementService` with `ActivationType=1` and `TrustLevel=0`.

A second live read-only inventory of `ModernDeployment.Autopilot.Core.DeviceLinkManager` succeeded and reported exactly two interfaces:

- `1F79101B-A792-5008-A82A-A4B232229026` - the sole functional interface currently associated with the `DeviceLinkManager` runtime class;
- `00000038-0000-0000-C000-000000000046` - standard `IWeakReferenceSource`.

`DeviceLinkManager` activation returned HRESULT `0x00000000`, `TrustLevel=0`, and runtime class name `ModernDeployment.Autopilot.Core.DeviceLinkManager`. This interface is now the primary candidate for the higher-level DeviceLink orchestration surface.

## Observed successful lifecycle

The current research model is:

1. Generate local DeviceLink identity.
2. Import/preassociate identity in Intune.
3. Tenant-side state becomes `preassociated`.
4. Device performs preassociation discovery against the global Autopilot association service.
5. Discovery returns tenant context and enrollment discovery routing information.
6. Windows resolves the tenant-specific association/attestation endpoints.
7. Windows proves possession of the TPM-backed device identity through Microsoft Azure Attestation.
8. Windows requests the signed tenant association using device/link context plus attestation evidence.
9. Windows receives the signed association JWT.
10. Windows writes the association to UEFI (`DeviceLinkJwtCompressed` plus timestamp/related state).
11. Windows acknowledges successful local apply to the service.
12. Tenant-side association progresses from `preassociated` to `associated`.
13. OOBE can then retrieve current device-targeted Device Preparation settings before user sign-in.

This is distinct from Intune enrollment and Microsoft Entra join.

## Live binary evidence

Read-only string inventory of `C:\Windows\System32\Windows.Management.Service.dll` version `10.0.26100.8875` exposed direct DeviceLink implementation evidence including:

- `AcquireApplyAckDeviceLink`
- `ApplyDeviceLink`
- `AcknowledgeDeviceLink`
- `RetrieveDeviceLinkFromUrl`
- `GetSignedDeviceAssociationInfo`
- `GetDiscoveryResults`
- `AcquireEnrollmentDiscoveryEndpoint`
- `PerformAttestation`
- `GenerateMaaAttestationClaims`
- `DeviceLinkPreassociateDiscoveryUri`
- `DeviceLinkJwtDownloadUri`
- `AcknowledgeDeviceLinkUri`
- `DeviceLinkManager`
- `DeviceLinkUtilities`
- `https://aps.windowsautopilot.microsoft.com/ztd/devicelink/preassociationDiscovery`

The same binary exposes WinRT generic type strings for `Windows.Foundation.IAsyncOperationWithProgress<ModernDeployment.Autopilot.Core.ConfigureDeviceLinkResult, ...>` and its completed handler. This strongly suggests a higher-level asynchronous DeviceLink configuration/orchestration operation exists in addition to the internal discovery/apply/ack functions.

This does not yet establish the public ABI, method name, interface IID, vtable slot, or call safety. Those must be recovered before invocation.

## DevicePreparation CSP / MDM Bridge observation

Live metadata enumeration of `root\cimv2\mdm\dmmap` found three DevicePreparation-related classes:

- `MDM_DevicePreparation_MDMProvider01`
- `MDM_DevicePreparation_BootstrapperAgent01`
- `MDM_DevicePreparation`

On the tested build these classes exposed properties only; no callable CIM methods were returned by `CimClassMethods` for `RefreshTenantAssociationInfo` or another tenant-association Exec surface.

Therefore the documented DevicePreparation CSP remains useful as a lifecycle/status model, but the local MDM Bridge does not currently provide an obvious direct callable association-completion method on this device. The WinRT/native route remains the primary implementation research path unless another bridge class is discovered.

## Known service/routing observations

The binary and community research both identify the global preassociation discovery endpoint:

`https://aps.windowsautopilot.microsoft.com/ztd/devicelink/preassociationDiscovery`

Observed routing state is stored under:

`HKLM\SOFTWARE\Microsoft\Provisioning\AutopilotSettings`

with values whose names are based on the DeviceLink identifier and include tenant/discovery hints.

Microsoft documentation separately confirms that Device Association requires network access to Autopilot/device-association services and Microsoft Azure Attestation endpoints.

These observations are research inputs, not a supported network contract for WindowsDeviceLink. Regional/service endpoints must not be hard-coded from one lab capture.

## Firmware transition model

Known local base state before completed association:

- `DeviceLinkId`
- `DeviceLinkCreationTimeUtc`

Known completed-state variables observed by this project:

- `DeviceLinkId`
- `DeviceLinkJwtCompressed`
- `DeviceLinkJwtLastWrite`
- `DeviceLinkCreationTimeUtc`

The expected research transition is therefore:

`Preassociated + 2/4` -> discovery/attestation/link -> `Associated + 4/4`

The precise point at which each firmware variable is committed and how rollback behaves after a partial failure still needs live validation.

## Signed association contents

Published research indicates that the resulting association JWT can contain context such as:

- LinkId
- TPM key identifier
- tenant identifier
- device inventory
- discovery URL
- issuer/audience/time claims

WindowsDeviceLink already treats this material as sensitive. The raw JWT must not appear in normal output, verbose/debug output, logs or errors.

The current `Test-WindowsDeviceLinkAssociationJwt` validates only structure/time/identity correlation unless signature validation is explicitly implemented from a trustworthy documented key source in the future.

## Requirements relevant to Discover/Link

Microsoft currently documents Device Association as requiring:

- a physical device (VMs unsupported)
- Windows 11 24H2 or 25H2 with the required servicing level
- a supported Windows edition
- TPM 2.0 enabled and in a good state (not Reduced Functionality Mode)
- network access to Device Association and Azure Attestation endpoints

Our existing preflight covers runtime activation, elevation, firmware access, TPM 2.0 indication, Secure Boot and local DeviceLink identity. Build/edition/virtual-machine/network checks should be considered before any future live Discover/Link implementation.

## Known failure signals from public research

Published tooling/research reports useful native HRESULT categories including:

- `0x80004001` (`E_NOTIMPL`) - required DeviceLink API unavailable on the build
- `0x8103C00F` - missing attestation material
- `0x80090029` / `0x80090016` - TPM/key operation failure
- `0x80070005` - access denied / insufficient elevation

These must be independently reproduced before WindowsDeviceLink treats them as stable public error classifications.

## Safety boundary for experiments

Any experimental call must:

1. require an already validated preflight;
2. capture local firmware/JWT/cloud association state before invocation;
3. invoke one narrow native operation only;
4. expose exact safe HRESULT/status output;
5. perform no destructive cleanup on failure;
6. perform no automatic retry unless proven idempotent;
7. never delete the tenant record or reset firmware;
8. never reboot automatically;
9. re-read local firmware/JWT/cloud state after the operation;
10. stop immediately on a partial or unknown transition.

## Next research task

Correlate `DeviceLinkManager` interface IID `1F79101B-A792-5008-A82A-A4B232229026` with binary/WinRT type metadata and recover the exact higher-level DeviceLink configuration contract, including:

- interface/type name;
- vtable slot(s) and ABI signature;
- `ConfigureDeviceLinkResult` values;
- progress type/values;
- async error contract;
- whether the high-level operation performs Discover + attestation + apply + acknowledge as one orchestration;
- whether lower-level Discover/Link calls remain independently exposed.

Only after that mapping is reproducible should a controlled private experimental call be considered.
