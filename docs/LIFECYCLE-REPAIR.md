# DeviceLink lifecycle repair model

WindowsDeviceLink deliberately separates observation, planning, and mutation.

## Public planning surface

`Get-WindowsDeviceLinkRepairPlan` converts a `Windows.DeviceLink.Health` assessment into a read-only `Windows.DeviceLink.RepairPlan` object.

The planner never registers, removes, resets, or reboots a device.

For tenant-aware planning, collect combined status first:

```powershell
Get-WindowsDeviceLinkStatus -Online -Method DeviceCode |
    Test-WindowsDeviceLinkHealth |
    Get-WindowsDeviceLinkRepairPlan |
    Format-List *
```

## Safety boundary

Health classification alone is never sufficient authorization for destructive lifecycle work.

The planner therefore never sets any of these properties to `True`:

- `RequiresCloudDelete`
- `RequiresFirmwareReset`
- `RequiresReboot`
- `DestructiveActionsAllowed`

Unknown, unsupported, cloud-error, firmware-error, incomplete and lifecycle-mismatch states always stop at investigation or re-check guidance.

## Safe non-destructive states

- `LocalOnly` -> `UseInitialize`; use the existing `Initialize-WindowsDeviceLink` path when preassociation is intended.
- `Preassociated` -> `NoAction`.
- `Associated` -> `NoAction`.
- `LocalBaseIdentity` -> `NoLocalRepair`; tenant-side state was not checked.
- `LocalCompleteFirmwareState` -> `CheckCloudState`; correlate with tenant state before lifecycle decisions.

## States that require investigation

Examples include:

- `CloudUnknown`
- `IncompleteFirmwareState`
- `CloudAssociationMissingWithCompleteFirmware`
- `PreassociatedUnexpectedFirmwareState`
- `AssociatedIncompleteFirmwareState`
- `UnclassifiedAssociationState`
- any future or unknown health state

These states must never trigger association removal or firmware reset solely because the state was observed.

## Explicit destructive lifecycle workflow

When an administrator intentionally wants to reinstall, regenerate identity, or move a device between tenants, use the existing explicit commands and verify every phase:

1. collect combined status and health;
2. resolve and confirm the exact tenant association record;
3. when intentional, remove that exact association with `Remove-WindowsDeviceLinkAssociation` and verify tenant-side absence;
4. inspect local firmware state again;
5. only when intentional, reset firmware with `Reset-WindowsDeviceLinkFirmwareState` using `-WhatIf` first;
6. verify the expected clean firmware state;
7. reboot only through an explicitly authorized administrator action;
8. verify that Windows generated the expected new local identity after reboot;
9. explicitly preassociate the new identity using `Initialize-WindowsDeviceLink` or `Register-WindowsDeviceLink`;
10. verify the final tenant and local state.

A future mutation orchestrator may automate selected phases only if it preserves these verification boundaries and never infers destructive intent from health classification alone.
