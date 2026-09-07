# WindowsDeviceLink webhook schema v1

This document defines the schema contract used by `Get-WindowsDeviceLink -Online -Method Webhook`.

## Compatibility policy

`schemaVersion = 1` is the current contract.

Within schema version 1:

- existing fields will not be renamed or removed;
- new optional fields may be added;
- receivers should ignore unknown fields;
- receivers should validate `schemaVersion`, `requestType`, and `device.deviceLink` before processing;
- a breaking payload change requires a new schema version.

## Request headers

| Header | Required | Purpose |
|---|---:|---|
| `X-WindowsDeviceLink-Schema` | Yes | Schema version. Currently `1`. |
| `X-WindowsDeviceLink-RequestId` | Yes | Correlation ID matching `requestId` in the body. |
| `X-WindowsDeviceLink-Key` | No | Optional additional webhook API key. Strongly recommended when the receiver has no equivalent request protection. |

The webhook API key is never included in the JSON body.

## JSON body

```json
{
  "schemaVersion": 1,
  "requestType": "DeviceLinkPreassociation",
  "requestId": "00000000-0000-0000-0000-000000000000",
  "tenantId": "00000000-0000-0000-0000-000000000000",
  "generatedAtUtc": "2026-09-07T19:00:00.0000000Z",
  "device": {
    "serialNumber": "SERIAL",
    "manufacturer": "Manufacturer",
    "model": "Model",
    "smbiosUuid": "00000000-0000-0000-0000-000000000000",
    "linkId": "00000000-0000-0000-0000-000000000000",
    "deviceLinkCreationTimeUtc": "2026-09-07T19:00:00Z",
    "deviceLink": "BASE64-DEVICELINK"
  },
  "source": {
    "computerName": "COMPUTER",
    "environment": "Windows",
    "architecture": "AMD64",
    "moduleVersion": "0.4.x",
    "powerShellVersion": "5.1.0",
    "dllSource": "System",
    "dllVersion": "10.0.x",
    "activationMode": "RegisteredWinRT"
  }
}
```

## Required fields

A compatible receiver must require:

- `schemaVersion = 1`;
- `requestType = DeviceLinkPreassociation`;
- non-empty `requestId`;
- non-empty `device.deviceLink`.

`tenantId` is optional because a single-tenant receiver may use a configured default tenant. Multi-tenant receivers should require or otherwise resolve a target tenant before calling Microsoft Graph.

## Sensitive data

The payload contains device identity data including the complete TPM-backed DeviceLink. Do not write the full request body to unrestricted operational logs.

The recommended correlation value for diagnostics is `requestId`.
