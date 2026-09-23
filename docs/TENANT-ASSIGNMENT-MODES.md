# Tenant assignment modes

WindowsDeviceLink uses one module and one lifecycle model with two explicit execution
routes.

## Direct mode

Direct mode talks to Microsoft Graph from the device. TenantId is optional for
Interactive and DeviceCode authentication. When omitted, the authenticated sign-in
context determines the tenant. A JSON catalog is only an address book for selecting one
explicit tenant.

Direct mode can prove state only inside that one tenant. It supports New or no-op and
never claims that the device is absent from other tenants.

## Backend mode

Backend mode is activated only with BackendUri and BackendApiKey. It obtains an
authenticated catalog, proves complete lookup coverage across every configured tenant,
and supports New, no-op, or Move. A target tenant is always explicit. Backend failure
never falls back to Direct mode.

## Decision contract

| Proven state | Decision | Renew local identity |
|---|---|---|
| Direct target absent, firmware 2/4 | New | No |
| Direct target present | None | No |
| Backend: absent everywhere, firmware 2/4 | New | Yes |
| Backend: absent everywhere, stale firmware 4/4 | New | Yes |
| Backend: present in target | None | No |
| Backend: present in another tenant | Move | Yes |
| Backend lookup incomplete or ambiguous | Block | No mutation |

Assignment results expose OperationMode, Decision, ReasonCode, Changed, RetrySafe, and
RecommendedAction. An uncertain mutation requires a fresh read; it is never blindly
retried.
