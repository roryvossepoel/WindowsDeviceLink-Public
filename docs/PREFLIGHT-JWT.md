# DeviceLink preflight and Association JWT validation

This document describes the read-only readiness and local Association JWT validation model.

## Test-WindowsDeviceLinkPreflight

`Test-WindowsDeviceLinkPreflight` collects independent observations and returns an overall state of `Ready`, `Warning`, or `Blocked`.

Current checks:

- DeviceLink runtime/native activation support;
- process elevation;
- ability to query the known DeviceLink firmware variables;
- TPM observation and TPM 2.0 indication where available;
- Secure Boot observation where available;
- ability to obtain a local DeviceLink identity.

Unknown TPM or Secure Boot state is a warning, not success. Runtime, firmware-read, or local-identity failure is blocking.

The preflight command is read-only. It does not register a DeviceLink, remove a tenant association, reset firmware, perform Discover/Link, or reboot the device.

## Test-WindowsDeviceLinkAssociationJwt

`Test-WindowsDeviceLinkAssociationJwt` reads `DeviceLinkJwtCompressed` privately and never returns the raw firmware value or raw JWT payload.

The current parser attempts supported local encodings and validates:

- JWT three-segment structure;
- parseable JSON header and payload;
- `iat`, `nbf`, and `exp` temporal claims when present;
- a known LinkId claim (`linkId`, `deviceLinkId`, or `device_link_id`) against the observed local LinkId when available.

Possible states include:

- `NotPresent`
- `Valid`
- `Expired`
- `NotYetValid`
- `IdentityMismatch`
- `Malformed`
- `Unknown`

## Important cryptographic boundary

`Valid` currently means only that the JWT is structurally parseable, its observed temporal claims are acceptable, and an observed supported LinkId claim does not conflict with the local LinkId.

It does **not** mean the JWT signature or signing chain has been cryptographically validated. The returned property therefore remains:

`SignatureValidation = NotPerformed`

The module must not claim cryptographic trust until the signing keys/trust chain and verification procedure can be validated from a documented source.

## Sensitive-data boundary

The following are intentionally not returned or logged:

- raw `DeviceLinkJwtCompressed` bytes;
- raw JWT text;
- raw JWT payload JSON;
- arbitrary JWT claims;
- signing material.

Only selected non-sensitive validation metadata is returned.
