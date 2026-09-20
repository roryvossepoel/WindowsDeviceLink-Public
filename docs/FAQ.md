# WindowsDeviceLink FAQ

This FAQ is intended as a practical operator guide: **what should I run to achieve a specific DeviceLink / Device Association state?**

> [!IMPORTANT]
> WindowsDeviceLink manages the local DeviceLink identity and Windows Autopilot device preparation **Device Association**. It does **not** remove classic Windows Autopilot registrations.

## Start here: what state is the device in?

For local state only:

```powershell
Get-WindowsDeviceLinkStatus | Format-List *
```

For local + tenant-side Device Association state:

```powershell
Get-WindowsDeviceLinkStatus `
    -Online `
    -Method DeviceCode `
    -TenantId '<tenant-id>' |
    Format-List *
```

For readiness before a completion operation:

```powershell
Test-WindowsDeviceLinkPreflight | Format-List *
```

## What are the common states?

### LocalOnly

Typical state:

```text
Firmware: 2/4
Cloud Device Association: absent
```

The device has a local DeviceLink identity but has not been pre-associated with a tenant.

### Preassociated

Typical state:

```text
Firmware: 2/4
Cloud Device Association: preassociated
```

The tenant knows the DeviceLink identity, but the device-side association has not yet completed.

### Associated

Typical state:

```text
Firmware: 4/4
Cloud Device Association: associated
JWT: present and identity-matching
```

The complete Device Association flow has finished.

## I only want to generate/read the local DeviceLink identity

Use:

```powershell
Get-WindowsDeviceLink
```

This is a local operation. It does not create a tenant-side Device Association.

To export the Windows-generated DeviceLink CSV:

```powershell
Get-WindowsDeviceLink -OutputDirectory 'C:\DeviceLink'
```

## I want to pre-associate the current device with a tenant

Use:

```powershell
$deviceLink = Get-WindowsDeviceLink

$deviceLink | Register-WindowsDeviceLink `
    -Method DeviceCode `
    -TenantId '<tenant-id>'
```

Expected transition:

```text
LocalOnly -> Preassociated
```

This creates tenant-side Device Association state. It does not force local completion.

## I already have a preassociation and want to complete the local association

First verify readiness:

```powershell
Test-WindowsDeviceLinkPreflight | Format-List *
```

Then:

```powershell
Complete-WindowsDeviceLinkAssociation | Format-List *
```

Expected transition:

```text
Preassociated + firmware 2/4
    -> native discovery
    -> ConfigureDeviceLinkAsync
    -> firmware 4/4
    -> association JWT valid
    -> Associated
```

The cmdlet does not retry, reset firmware, delete cloud state, or reboot automatically.

## I want to go from a clean local identity to fully associated in one command

Use:

```powershell
Initialize-WindowsDeviceLink `
    -Method DeviceCode `
    -TenantId '<tenant-id>' `
    -CompleteAssociation |
    Format-List *
```

Expected lifecycle:

```text
LocalOnly -> Register -> Preassociated -> Complete -> Associated
```

If the device is already associated, the command is idempotent and does not run configure again.

## I only want a preassociation, not full completion

Use the initializer **without** `-CompleteAssociation`:

```powershell
Initialize-WindowsDeviceLink `
    -Method DeviceCode `
    -TenantId '<tenant-id>' |
    Format-List *
```

For a validated `LocalOnly` device this creates the preassociation and stops there.

## Is deleting the Device Association record from Intune enough to offboard the device?

It depends on the current association state.

### Pre-associated

Yes. If the device is still **Pre-associated** and has not completed association in OOBE, deleting the tenant-side Device Association record is sufficient.

```text
Pre-associated
    -> delete Device Association record
    -> done
```

### Associated

No. Once the device is **Associated**, trusted tenant affinity is stored locally in UEFI. Deleting only the tenant-side record does not remove that local affinity.

Use this order:

```text
Associated
    -> ensure the device is no longer enrolled with MDM
    -> clear local Device Link UEFI state
    -> delete Device Association record
    -> done
```

WindowsDeviceLink provides separate commands for the local and tenant-side operations:

```powershell
Reset-WindowsDeviceLinkFirmwareState -Confirm:$false -PassThru

Remove-WindowsDeviceLinkAssociation -Method Interactive
```

The operations are intentionally not combined automatically. See [OFFBOARDING.md](OFFBOARDING.md) for the complete flow.

## I want to remove only the tenant-side Device Association

Use:

```powershell
Remove-WindowsDeviceLinkAssociation `
    -SerialNumber '<serial-number>' `
    -Method DeviceCode `
    -TenantId '<tenant-id>'
```

Or when the exact association ID is known:

```powershell
Remove-WindowsDeviceLinkAssociation `
    -AssociationId '<association-id>' `
    -Method DeviceCode `
    -TenantId '<tenant-id>'
```

This deletes the Device Association record in the tenant.

It does **not** remove the local DeviceLink firmware variables.

## I want to remove/reset only the local DeviceLink identity

Use:

```powershell
Reset-WindowsDeviceLinkFirmwareState
```

For unattended / controlled automation:

```powershell
Reset-WindowsDeviceLinkFirmwareState -Confirm:$false -PassThru
```

Immediately after a successful reset, all four known DeviceLink firmware variables should be absent (`0/4`).

After a reboot, Windows can generate a **new** local DeviceLink base identity, typically returning to `2/4`.

This operation does **not** delete the tenant-side Device Association.

## I want to completely start over with Device Association

Treat cloud state and local firmware state as two separate layers.

Recommended controlled sequence:

```text
1. Remove tenant-side Device Association
2. Verify that no Device Association record remains
3. Reset local DeviceLink firmware state
4. Verify local firmware is 0/4
5. Reboot
6. Verify Windows generated a new local identity (normally 2/4)
7. Register / initialize again
8. Complete association if required
```

Example:

```powershell
Remove-WindowsDeviceLinkAssociation `
    -SerialNumber '<serial-number>' `
    -Method DeviceCode `
    -TenantId '<tenant-id>'

Reset-WindowsDeviceLinkFirmwareState -Confirm:$false -PassThru

Restart-Computer
```

After reboot:

```powershell
Get-WindowsDeviceLinkStatus

Initialize-WindowsDeviceLink `
    -Method DeviceCode `
    -TenantId '<tenant-id>' `
    -CompleteAssociation
```

Do not combine destructive cleanup steps blindly. Verify the state between operations, especially on production devices.

## I want to move a device to another tenant

A tenant move requires both the old tenant-side association and the old local association identity to be handled deliberately.

High-level sequence:

```text
Old tenant Device Association
    -> remove
Local DeviceLink firmware state
    -> reset
Reboot
    -> new DeviceLink identity
New tenant
    -> preassociate
Device-side completion
    -> associated
```

WindowsDeviceLink does not automatically delete the old tenant association or reset firmware as part of registration. This separation is intentional.

## I want to remove the classic Windows Autopilot registration

WindowsDeviceLink does not manage classic Autopilot registration objects.

A classic Autopilot registration (often called "Autopilot v1") and a Device Association are different objects.

If a device is classically Autopilot-registered and the goal is to remove that registration, use the supported Intune / Windows Autopilot administration route for deregistration.

Do **not** assume that:

```text
Remove-WindowsDeviceLinkAssociation
```

removes the classic Autopilot registration. It does not.

See [AUTOPILOT-V1-VS-DEVICE-PREPARATION.md](AUTOPILOT-V1-VS-DEVICE-PREPARATION.md).

## My device is registered in classic Autopilot. Can Device Association still be used?

Yes. Microsoft supports both solutions side by side.

For an Autopilot-registered device:

- if there is no Device Association, the classic Autopilot profile takes precedence;
- if the device is Device Associated, Windows Autopilot device preparation takes precedence.

If you want device preparation **without** Device Association on a device that is still classically registered, Microsoft guidance is to deregister the classic Autopilot device first.

## What does firmware 2/4 mean?

The validated base DeviceLink state contains:

```text
DeviceLinkId
DeviceLinkCreationTimeUtc
```

and does not yet contain:

```text
DeviceLinkJwtCompressed
DeviceLinkJwtLastWrite
```

This is the expected local state before completed association.

## What does firmware 4/4 mean?

All four known DeviceLink firmware variables are present:

```text
DeviceLinkId
DeviceLinkJwtCompressed
DeviceLinkJwtLastWrite
DeviceLinkCreationTimeUtc
```

This is the expected local firmware state after successful association completion.

`4/4` alone is not treated as sufficient proof of a healthy association: WindowsDeviceLink also validates the local JWT structure/time/identity correlation and can correlate the tenant-side state.

## Does WindowsDeviceLink validate the cryptographic JWT signature?

No.

`Test-WindowsDeviceLinkAssociationJwt` validates structure, time-related claims, and identity correlation without exposing the raw JWT.

The module explicitly reports:

```text
SignatureValidation = NotPerformed
```

unless a trustworthy cryptographic validation mechanism is implemented in the future.

## Why does completion sometimes appear to take a while?

The native Windows Device Association operation can take tens of seconds or longer while Windows performs discovery, attestation, retrieval, and configuration.

Starting with `0.5.1-preview1`, completion emits visible phase information plus a 15-second heartbeat while the native configure operation is still running.

Example:

```text
Starting native DeviceLink configuration...
Waiting for Windows to retrieve, attest and apply the DeviceLink association... 15 seconds elapsed.
Native DeviceLink configuration completed in 28.0 seconds. Operation result: 1.
```

The timing values are operational telemetry, not a percentage-complete estimate.

## Does completion retry automatically when something fails?

No.

The guarded completion operation intentionally performs:

- at most one native configure invocation;
- zero automatic retries;
- no automatic firmware reset;
- no automatic cloud cleanup;
- no automatic reboot.

If completion returns an unexpected or partial state, inspect the local firmware, JWT, and cloud association before taking another state-changing action.

## What should I run before troubleshooting?

Recommended read-only collection:

```powershell
Test-WindowsDeviceLinkSupport | Format-List *
Test-WindowsDeviceLinkPreflight | Format-List *
Get-WindowsDeviceLinkStatus | Format-List *
Get-WindowsDeviceLinkFirmwareState | Format-List *
Test-WindowsDeviceLinkAssociationJwt | Format-List *
```

When tenant correlation is required:

```powershell
Get-WindowsDeviceLinkStatus `
    -Online `
    -Method DeviceCode `
    -TenantId '<tenant-id>' |
    Format-List *
```

These commands make it much easier to distinguish:

- runtime/OS support problems;
- local firmware state problems;
- missing tenant association;
- preassociated state;
- completed local association;
- cloud lookup/authentication problems.

## Can I use `-WhatIf`?

State-changing cmdlets support PowerShell safety semantics where documented.

Examples:

```powershell
Reset-WindowsDeviceLinkFirmwareState -WhatIf
Complete-WindowsDeviceLinkAssociation -WhatIf

Initialize-WindowsDeviceLink `
    -Method DeviceCode `
    -TenantId '<tenant-id>' `
    -CompleteAssociation `
    -WhatIf
```

Use `-WhatIf` when validating intended transitions before modifying state.

## Does reset restore the previous DeviceLink identity after reboot?

No. Live testing showed that reset removes the old local DeviceLink identity. After reboot, Windows can generate a **new** identity.

The reappearance of `DeviceLinkId` and `DeviceLinkCreationTimeUtc` after reboot is expected regeneration, not restoration of the removed identity.

## Can the module be used in WinPE?

Yes. The identity, firmware and tenant-side Device Association operations have been validated in AMD64 WinPE when a compatible administrator-supplied `Windows.Management.Service.dll` is provided.

The Microsoft DLL is intentionally not redistributed by this project.

The normal WinPE deployment flow is:

```text
WinPE
  -> generate/read DeviceLink identity
  -> create tenant-side pre-association
  -> install Windows 11
  -> OOBE connects to the network
  -> Windows completes Device Association automatically
```

Microsoft documents that pre-associated devices complete Device Association automatically when they connect to a network during OOBE. Because WinPE is normally used before installing Windows 11, native association completion inside WinPE is not required for this standard flow.

Direct DeviceLinkManager activation has been validated in WinPE, but native discovery currently fails at `RequestDiscoveryUrlAsync` with HRESULT `0x81036C00`. Native discovery/completion in WinPE is therefore experimental and not currently treated as a supported workflow.

Full Windows remains the validated environment for explicit native discovery and `ConfigureDeviceLinkAsync`.

See [WINPE-WORKFLOW.md](WINPE-WORKFLOW.md) and [INSTALLATION.md](INSTALLATION.md).

## Which command changes which layer?

| Goal | Command | Local firmware | Tenant Device Association | Classic Autopilot registration |
|---|---|---:|---:|---:|
| Read local identity | `Get-WindowsDeviceLink` | Read / Windows may materialize base identity | No change | No change |
| Inspect firmware | `Get-WindowsDeviceLinkFirmwareState` | Read only | No change | No change |
| Create preassociation | `Register-WindowsDeviceLink` | No destructive change | Creates / preassociates | No change |
| Complete association | `Complete-WindowsDeviceLinkAssociation` | `2/4 -> 4/4` on success | Becomes associated | No change |
| Safe full initialization | `Initialize-WindowsDeviceLink -CompleteAssociation` | May complete to `4/4` | May create + associate | No change |
| Remove Device Association | `Remove-WindowsDeviceLinkAssociation` | No change | Deletes record | No change |
| Reset local DeviceLink | `Reset-WindowsDeviceLinkFirmwareState` | Removes known DeviceLink variables | No change | No change |
| Remove classic Autopilot registration | Not provided by this module | No change | No change | Use supported Autopilot administration tooling |

## Further reading

- [AUTOPILOT-V1-VS-DEVICE-PREPARATION.md](AUTOPILOT-V1-VS-DEVICE-PREPARATION.md)
- [OFFBOARDING.md](OFFBOARDING.md)
- [FIRMWARE-STATE.md](FIRMWARE-STATE.md)
- [REMOVE-ASSOCIATION.md](REMOVE-ASSOCIATION.md)
- [DISCOVER-LINK-RESEARCH.md](DISCOVER-LINK-RESEARCH.md)
- [INSTALLATION.md](INSTALLATION.md)
- [WINPE-WORKFLOW.md](WINPE-WORKFLOW.md)
