# DeviceLink reconcile schema v1

This document defines the backend contract for the multitenant **New / Move / Update** reconciliation workflow.

It is separate from the normal `DeviceLinkPreassociation` webhook request because reconciliation includes current/source tenant state and can perform a controlled tenant move.

## Purpose

A caller can perform a lookup before showing or submitting its form, but the backend never trusts that earlier lookup as authoritative.

The supplied `sourceTenantId` is treated as the caller's **expected current state**. Immediately before any mutation, the backend searches the configured tenants again and validates the actual state.

## Request

Headers:

| Header | Required | Purpose |
|---|---:|---|
| `X-WindowsDeviceLink-Schema` | Yes | Must be `1`. |
| `X-WindowsDeviceLink-RequestId` | Yes | Correlation ID matching the body. |
| `X-WindowsDeviceLink-Key` | Yes for the reference backends | Shared receiver API key. |

Body:

```json
{
  "schemaVersion": 1,
  "requestType": "DeviceLinkReconcile",
  "requestId": "00000000-0000-0000-0000-000000000000",
  "sourceTenantId": "11111111-1111-1111-1111-111111111111",
  "targetTenantId": "22222222-2222-2222-2222-222222222222",
  "device": {
    "serialNumber": "ABC123",
    "deviceLink": "BASE64-DEVICELINK"
  }
}
```

### sourceTenantId

`sourceTenantId` is optional only when the caller's earlier lookup found no existing association.

It is required before the backend will perform a **Move**.

The backend will not delete from a tenant merely because it discovers a device there. A Move requires the supplied source tenant to match the freshly detected source tenant exactly.

### targetTenantId

`targetTenantId` is always required.

The target must be configured/allowed by the backend.

## Decision model

After a fresh lookup across all configured tenants:

```text
no association found
  + no sourceTenantId
      -> New

one association found in targetTenantId
      -> Update

one association found outside targetTenantId
  + sourceTenantId matches detected tenant
      -> Move
```

Any ambiguous or inconsistent state is blocked.

## New

`New` creates a pre-association in the target tenant and verifies that the association can be read back.

No source deletion occurs.

## Update

`Update` currently means:

```text
device is already in the requested target tenant
-> no tenant move required
-> changed = false
```

No speculative mutable properties are part of this contract yet.

Potential future properties such as device name, assigned user or group tag are tracked as capability research and will only be added after a supported Device Association API has been validated.

## Move

A Move is intentionally an internal state machine:

```text
fresh lookup
-> verify exactly one source association
-> verify sourceTenantId matches
-> re-read source immediately before mutation
-> DELETE exact source association
-> verify source is absent
-> verify target is still empty
-> POST target pre-association
-> verify target association exists
```

There is no public/raw delete endpoint in the reference backends.

## Failure behavior

The backend fails closed when:

- one or more configured tenants cannot be searched;
- the serial exists in multiple configured tenants;
- `sourceTenantId` does not match the detected source;
- a Move is required but no source tenant was supplied;
- source state changes between decision and mutation;
- post-state verification fails.

Mutation requests are never blindly retried.

If a DELETE or POST transport call fails, its commit state can be ambiguous. The backend performs read-only verification where possible and requires a fresh lookup before another mutation when final state cannot be proven.

## Local firmware

Reconcile only manages **tenant-side Device Association state**.

It never resets local DeviceLink firmware.

For a fully associated device, local `4/4` firmware state may require a deliberate device-side reset/reboot lifecycle before the device can be treated as a new identity. That remains a separate operation.

## Response examples

### New

```json
{
  "success": true,
  "decision": "New",
  "changed": true,
  "targetTenantId": "22222222-2222-2222-2222-222222222222",
  "associationId": "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa",
  "associationState": "preassociated",
  "serialNumber": "ABC123"
}
```

### Update

```json
{
  "success": true,
  "decision": "Update",
  "changed": false,
  "sourceTenantId": "22222222-2222-2222-2222-222222222222",
  "targetTenantId": "22222222-2222-2222-2222-222222222222",
  "associationId": "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa",
  "associationState": "preassociated",
  "serialNumber": "ABC123"
}
```

### Move

```json
{
  "success": true,
  "decision": "Move",
  "changed": true,
  "sourceTenantId": "11111111-1111-1111-1111-111111111111",
  "targetTenantId": "22222222-2222-2222-2222-222222222222",
  "sourceAssociationId": "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa",
  "targetAssociationId": "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb",
  "associationState": "preassociated",
  "serialNumber": "ABC123"
}
```
