# Windows Autopilot vs Windows Autopilot device preparation

This page explains the practical differences between **classic Windows Autopilot** (often called "Autopilot v1") and **Windows Autopilot device preparation**, with special attention to the newer **Device Association** model used by WindowsDeviceLink.

> [!NOTE]
> Microsoft documentation normally calls the older product simply **Windows Autopilot**. This project uses **Autopilot v1** only as a convenient shorthand when contrasting it with Windows Autopilot device preparation and Device Association.

## Short version

Classic Windows Autopilot is based on a device being **registered with the Windows Autopilot service before deployment**. The registered hardware identity is then matched to an Autopilot deployment profile.

Windows Autopilot device preparation changes that model. A device can deploy without classic Autopilot registration, and newer **Device Association** can bind a physical device to a tenant before enrollment using a TPM-backed DeviceLink identity.

WindowsDeviceLink is built for this **Device Association** workflow. It does not manage classic Autopilot v1 registrations.

## Comparison

| Area | Windows Autopilot (classic / "v1") | Windows Autopilot device preparation |
|---|---|---|
| Device registration required before deployment | Yes for the normal Autopilot flow | No |
| Pre-bind device to tenant | Autopilot registration | Device Association |
| Primary device identity | Autopilot registered hardware identity / hardware hash | TPM-backed DeviceLink identity for Device Association |
| Deployment configuration | Autopilot deployment profile + Enrollment Status Page | Device preparation policy + assigned device security group |
| Microsoft Entra join | Supported | Supported |
| Microsoft Entra hybrid join | Supported | Not supported |
| User-driven | Supported | Supported |
| Pre-provisioning | Supported | Not currently equivalent to classic pre-provisioning |
| Self-deploying | Supported | Not currently equivalent to classic self-deploying mode |
| Existing devices scenario | Supported | Not the same classic scenario |
| Automatic mode | No equivalent classic mode | Supported for specific device preparation scenarios |
| Windows 10 | Supported while the Windows version remains supported | Windows 11 only |
| OOBE app targeting | Device and user ESP phases | Device-based during OOBE |
| App limit during OOBE | Up to 100 apps through classic ESP behavior | Up to 25 essential apps |
| PowerShell scripts during OOBE | Classic Intune processing model | Up to 10 essential PowerShell scripts |
| Win32 + LOB in same provisioning flow | Classic restrictions apply | Supported |
| Reporting | Classic Autopilot deployment report | Near real-time device preparation deployment reporting |
| Device reset scenario | Windows Autopilot Reset supported | No equivalent Windows Autopilot Reset support |
| DFCI / some specialized scenarios | Supported in classic Autopilot scenarios | Not currently equivalent |

Microsoft maintains the authoritative comparison and can change these capabilities over time. Always check the current Microsoft Learn comparison before designing a new production deployment.

## Classic Autopilot registration

In classic Autopilot, the device is registered in the tenant before OOBE. Common registration paths include:

- OEM / reseller registration;
- hardware hash import;
- existing device registration workflows;
- partner APIs.

The service then recognizes the device during OOBE and assigns an Autopilot deployment profile.

A classic registration is **tenant-side state**. Removing it is a different operation from removing a Device Association or resetting the local DeviceLink firmware state.

WindowsDeviceLink deliberately does **not** delete classic Autopilot registrations.

## Device preparation without Device Association

Windows Autopilot device preparation was designed so a device does not need to be pre-registered with classic Autopilot.

The administrator mainly configures:

- automatic Intune enrollment;
- a device security group;
- the Intune Provisioning Client as owner of that group;
- a Windows Autopilot device preparation policy;
- required apps and scripts for the provisioning phase.

The first user must also be allowed to perform Microsoft Entra join for user-driven scenarios.

## Device Association

Device Association adds a pre-enrollment device-to-tenant binding to Windows Autopilot device preparation.

For Device Association, Windows generates a TPM-backed DeviceLink identity on the physical device. That identity can be pre-associated with a tenant. Windows can then discover the tenant association, perform TPM-backed attestation, and complete the local association.

A useful mental model is:

```text
Physical device
    |
    +-- local DeviceLink identity
    |       DeviceLinkId
    |       DeviceLinkCreationTimeUtc
    |
    +-- tenant-side Device Association
    |       preassociated -> associated
    |
    +-- completed local association
            DeviceLinkJwtCompressed
            DeviceLinkJwtLastWrite
```

WindowsDeviceLink exposes these layers separately so an administrator can inspect and control each one.

## Device Association lifecycle

A normal WindowsDeviceLink lifecycle looks like:

```text
LocalOnly
    |
    | Register-WindowsDeviceLink
    v
Preassociated
    |
    | Complete-WindowsDeviceLinkAssociation
    v
Associated
```

Or as one guarded operation:

```powershell
Initialize-WindowsDeviceLink `
    -Method DeviceCode `
    -TenantId '<tenant-id>' `
    -CompleteAssociation
```

The initializer verifies the state before and after each transition and remains idempotent on an already-associated device.

## What happens if a device is both Autopilot-registered and Device Associated?

Microsoft supports Windows Autopilot and Windows Autopilot device preparation side by side in the same tenant.

For a device that is already registered with classic Windows Autopilot:

- if the device is **not associated**, the classic Autopilot profile takes precedence;
- if the device **is associated**, Device Association takes precedence and the Windows Autopilot device preparation deployment runs.

If the goal is to use device preparation on a classically registered device **without** Device Association, Microsoft guidance is to deregister the classic Autopilot device first.

This distinction is important: **classic Autopilot registration** and **Device Association** are independent tenant-side objects.

## Terminology used in this project

| Term | Meaning |
|---|---|
| Local DeviceLink identity | TPM-backed identity generated by Windows on the device |
| Firmware `2/4` | `DeviceLinkId` and `DeviceLinkCreationTimeUtc` present; no association JWT yet |
| Preassociated | Tenant-side Device Association record exists, but local association is not yet completed |
| Firmware `4/4` | All four known DeviceLink firmware variables are present |
| Associated | Tenant-side Device Association is associated and the local association has been completed |
| Reset local DeviceLink state | Remove the four known local UEFI DeviceLink variables |
| Remove Device Association | Delete the tenant-side `tenantAssociatedDevices` record |
| Deregister Autopilot v1 | Remove the classic Windows Autopilot registration; outside the scope of WindowsDeviceLink |

## Current Device Association requirements

Device Association has stricter requirements than general Windows Autopilot device preparation. Current Microsoft documentation requires a physical Windows 11 device, supported Windows 11 servicing levels, TPM 2.0 in a healthy state, and network access to the Device Association / attestation endpoints.

Because these requirements are actively evolving, do not hard-code OS build assumptions into deployment design without checking current Microsoft documentation.

## References

Authoritative Microsoft documentation:

- [Compare Windows Autopilot device preparation and Windows Autopilot](https://learn.microsoft.com/autopilot/device-preparation/compare)
- [Overview of Windows Autopilot device preparation](https://learn.microsoft.com/autopilot/device-preparation/overview)
- [Windows Autopilot device preparation requirements](https://learn.microsoft.com/autopilot/device-preparation/requirements)
- [Requirements for Windows Autopilot device association](https://learn.microsoft.com/autopilot/device-preparation/device-association/requirements)

For WindowsDeviceLink operations, continue with [FAQ.md](FAQ.md) and [DISCOVER-LINK-RESEARCH.md](DISCOVER-LINK-RESEARCH.md).
