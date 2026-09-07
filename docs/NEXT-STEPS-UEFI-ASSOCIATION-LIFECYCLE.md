# Next step: local Device Association lifecycle and WinPE

This document captures the next investigation area after `0.4.2-preview1`.

## Goal

Extend WindowsDeviceLink beyond server-side pre-association removal so that a device that is already **associated** can be prepared for decommissioning or tenant-to-tenant migration.

The key question is whether the local Device Association / tenant-affinity state stored in UEFI can be safely inspected and cleared from both full Windows and AMD64 Windows PE.

## Why this matters

Removing the `tenantAssociatedDevices` record from Intune is enough for a device that is only `preassociated`.

For a device that is already `associated`, the local Device Association state can remain on the device. A reset or Windows reinstall alone should not be assumed to remove that state. A complete lifecycle workflow therefore needs both:

1. local UEFI state handling on the device;
2. removal of the server-side `tenantAssociatedDevices` record.

This is especially relevant for tenant-to-tenant moves and for WinPE-based deployment workflows.

## UEFI state to investigate

Microsoft documents Device Association state in the following UEFI namespace:

```text
{B3DE75DA-819C-4FD5-9F01-C3D49E8CBBD7}
```

Variables:

```text
DeviceLinkId
DeviceLinkBlob
DeviceLinkUtc
```

Do not assume any additional variables need to be modified until validated.

## Investigation plan

### Phase 1 - Read only in full Windows

On a device that is already `associated`:

1. confirm the three documented UEFI variables exist;
2. record only safe metadata such as presence, size/type, and whether values are readable;
3. do not publish raw DeviceLink payloads or device identity values;
4. compare the local values/state with the corresponding Device Association record in Intune.

No write operation should be performed in the first test.

### Phase 2 - Read only in AMD64 WinPE

Boot the same or another known associated device into AMD64 Windows PE and verify:

1. whether UEFI variables are readable from WinPE;
2. whether the same namespace and variable names are visible;
3. what PowerShell/runtime dependencies are required;
4. whether an external `UEFI` PowerShell module is usable in WinPE, or whether WindowsDeviceLink should implement the required native UEFI access itself;
5. whether Secure Boot / firmware / privilege behavior differs from full Windows.

The first WinPE test must be read-only.

### Phase 3 - Controlled local removal

Only after read-only validation succeeds:

1. remove the three documented Device Association UEFI variables on a controlled test device;
2. verify the variables are actually absent afterward;
3. reboot and verify they do not immediately reappear;
4. verify the device does not automatically restore the old association because of an active enrollment or subsequent MDM check-in;
5. inspect the resulting Device Association state in Intune.

This step should be performed on a disposable or controlled device because it changes device identity/association state.

### Phase 4 - Server-side cleanup

After local state has been removed, use the already validated command:

```powershell
Remove-WindowsDeviceLinkAssociation \
    -SerialNumber '<serial>' \
    -Method <method> \
    -TenantId '<tenant-id>'
```

or the advanced `-AssociationId` route.

The Graph delete operation already validated by this project is:

```http
DELETE /deviceManagement/tenantAssociatedDevices/{associationId}
```

This is the Device Association API. It is not the classic Autopilot V1 device deletion API.

## Target tenant-to-tenant workflow

If local UEFI removal is proven safe in WinPE, the desired deployment flow becomes:

```text
Boot WinPE
-> inspect current Device Association / tenant-affinity state
-> clear old local Device Association UEFI variables
-> remove old tenantAssociatedDevices record
-> generate/read current DeviceLink identity as required
-> create pre-association in the target tenant
-> install Windows
-> continue OOBE / Device Preparation
```

This would make WinPE a strong control point for tenant moves before Windows OOBE starts.

## Possible module design

Do not implement these commands until the behavior has been validated.

Candidate read-only command:

```powershell
Get-WindowsDeviceLinkAssociationState
```

Candidate local-clear command:

```powershell
Clear-WindowsDeviceLinkAssociationState
```

Existing server-side command:

```powershell
Remove-WindowsDeviceLinkAssociation
```

A later higher-level workflow could combine local and server-side removal, but keeping local firmware modification and Graph deletion separate initially is safer and easier to test.

## Safety requirements

- Read-only validation comes first.
- Never log or publish raw `DeviceLinkBlob` values.
- Do not clear unrelated UEFI variables.
- Do not assume reset/reinstall removes tenant affinity.
- Do not use classic Autopilot V1 delete APIs for Device Association records.
- Be explicit about whether the device is merely `preassociated` or fully `associated` before choosing a removal workflow.
- WinPE write support must be validated separately from full Windows.

## Next test session

Start with an already associated physical device.

1. Full Windows: read the three UEFI variables only.
2. AMD64 WinPE: read the same three variables only.
3. Compare behavior and dependencies.
4. Only then design and test the local-clear implementation.
