# Local source-tenant discovery

WindowsDeviceLink can determine the source tenant from local DeviceLink state without first searching every managed tenant through Microsoft Graph.

Use:

```powershell
Get-WindowsDeviceLinkLocalAssociation |
    Format-List *
```

The command is read-only and performs no Graph or other cloud request.

## Why this matters

Multitenant workflows previously had to search configured tenants to answer a basic question:

```text
Which tenant does this device belong to?
```

Local DeviceLink metadata can now answer that question earlier:

```text
device
-> local DeviceLink metadata
-> source TenantId
-> authenticate only when cloud verification or mutation is required
```

Tenant-wide lookup remains useful as a fallback and as cloud-state verification, but is no longer the preferred source-tenant discovery path when the device itself exposes usable local metadata.

## Local sources

WindowsDeviceLink correlates two known local sources.

### Current-LinkId registry hint

Windows can write values under:

```text
HKLM\SOFTWARE\Microsoft\Provisioning\AutopilotSettings
```

using the current DeviceLink ID as the prefix:

```text
<DeviceLinkId>_TenantIdHint
<DeviceLinkId>_DiscoveryUrl
```

Only values whose prefix exactly matches the **current UEFI DeviceLinkId** are eligible.

Historical entries are not treated as active tenant state.

### Association JWT

After full Device Association completion, the UEFI variable:

```text
DeviceLinkJwtCompressed
```

contains a GZip-compressed JWT.

Validated physical-device testing showed an explicit:

```text
tenantId
```

claim in that JWT.

The raw JWT, signature, TPM material and unrelated claim values are not returned by the public local-association command.

## Trust model

`Get-WindowsDeviceLinkLocalAssociation` reports the source and trust level explicitly.

### CorrelatedLocalSources

Both the exact current-LinkId registry hint and the Association JWT tenant claim exist and agree.

```text
Source     : RegistryAndAssociationJwt
TrustLevel : CorrelatedLocalSources
```

This is the strongest currently implemented local correlation state.

### LocalRegistryHint

Only the exact current-LinkId registry hint is available.

```text
Source     : CurrentLinkIdRegistryHint
TrustLevel : LocalRegistryHint
```

This state has been observed after successful native DeviceLink discovery while firmware remained `2/4`.

### StructurallyObservedJwtClaim

Only the Association JWT tenant claim is available.

```text
Source     : AssociationJwt
TrustLevel : StructurallyObservedJwtClaim
```

The JWT is parsed locally, but signature verification is not currently performed.

### Conflict

Registry and JWT tenant identifiers are both present but disagree.

WindowsDeviceLink fails closed:

```text
TenantId          :
Source            : Conflict
TrustLevel        : Conflict
ConflictDetected  : True
```

No source tenant is selected automatically.

### Unavailable

No eligible local tenant source exists.

This is expected for a fresh base DeviceLink identity before native discovery.

## Validated lifecycle

Physical-device validation established the following sequence.

```text
0/4
-> no current DeviceLinkId
-> historical registry hints can remain
-> no tenant is selected

Get-WindowsDeviceLink
-> new base identity
-> 2/4
-> no matching TenantIdHint yet

Graph preassociation
-> still 2/4
-> no local TenantIdHint yet

Test-WindowsDeviceLinkDiscovery
-> still 2/4
-> writes <current LinkId>_TenantIdHint and _DiscoveryUrl
-> source tenant becomes locally discoverable

native completion
-> 4/4
-> DeviceLinkJwtCompressed appears
-> JWT tenantId can be correlated with the registry hint
```

## Historical registry entries

A firmware reset removes the known DeviceLink UEFI variables but does **not** necessarily remove historical AutopilotSettings values.

Live testing showed old:

```text
<LinkId>_TenantIdHint
<LinkId>_DiscoveryUrl
```

entries still present after the device had returned to `0/4`.

Therefore a registry-wide lookup such as "use the first TenantIdHint" is unsafe.

The public command instead uses:

```text
current UEFI DeviceLinkId
-> exact <DeviceLinkId>_TenantIdHint
```

If there is no current LinkId, historical hints are not eligible.

## Cloud deletion

Deleting the tenant-side Device Association does not immediately remove local tenant-identifying metadata.

Live testing showed that after cloud deletion:

- firmware remained `4/4`;
- `DeviceLinkJwtCompressed` remained present;
- the JWT `tenantId` remained readable;
- the current-LinkId registry `TenantIdHint` remained present.

This is why cloud-side deletion alone is not complete local offboarding for an associated device.

## Signature-validation boundary

The observed Association JWT uses `RS256` and exposes `kid` / `x5t` signing-key identifiers.

Research attempted online signing-key discovery through the issuer/discovery metadata and with an independent DeviceLink validation script. For the observed `DeviceTag_<guid>` issuer, no published signing-key set was located.

The module therefore reports:

```text
SignatureValidation : NotPerformed
```

and does not claim cryptographic verification of the JWT.

The local tenant ID remains useful as observed/correlated local state, but the trust boundary is explicit.

## Friendly tenant name and domain

The local DeviceLink metadata reliably provides the tenant ID, not a friendly tenant display name or default domain.

Friendly tenant information requires a separate authenticated cloud lookup. This is intentionally kept out of `Get-WindowsDeviceLinkLocalAssociation` so that the command remains:

- local;
- read-only;
- cloud-independent;
- usable before Graph authentication.

## Recommended multitenant flow

```text
Get-WindowsDeviceLinkLocalAssociation
-> local source tenant available?
     yes:
       use TenantId as expected source context
       authenticate only when cloud verification/mutation is required

     no:
       use multitenant lookup fallback

-> before any mutation:
     backend performs fresh Graph lookup
     verify source state
     mutate
     verify post-state
```

Local source discovery improves intent selection, but it does not replace fresh cloud-state verification immediately before a state-changing tenant operation.

## Related documentation

- [MULTITENANT-LOOKUP.md](MULTITENANT-LOOKUP.md)
- [RECONCILE-SCHEMA-v1.md](RECONCILE-SCHEMA-v1.md)
- [FIRMWARE-STATE.md](FIRMWARE-STATE.md)
- [OFFBOARDING.md](OFFBOARDING.md)
- [FAQ.md](FAQ.md)
- [TESTING.md](../TESTING.md)
