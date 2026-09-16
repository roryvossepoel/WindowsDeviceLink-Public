# Microsoft Graph API resilience

WindowsDeviceLink uses the Microsoft Graph beta `deviceManagement/tenantAssociatedDevices` API for Device Association lookup, preassociation and removal.

Because this API is beta, WindowsDeviceLink treats transport failures, malformed responses and unknown states conservatively. A failed or indeterminate cloud operation must never be interpreted as confirmed absence of a Device Association.

## Read operations

Idempotent Microsoft Graph `GET` requests may be retried automatically, up to three attempts by default, for:

- HTTP `429 Too Many Requests`;
- HTTP `500 Internal Server Error`;
- HTTP `502 Bad Gateway`;
- HTTP `503 Service Unavailable`;
- HTTP `504 Gateway Timeout`;
- selected transient network failures such as timeout, connection loss and name-resolution failure.

Authentication, authorization, not-found and conflict responses such as HTTP 401, 403, 404 and 409 are not treated as transient GET failures and are not automatically retried.

### Retry-After

For HTTP 429, WindowsDeviceLink honors both standard `Retry-After` forms:

- delay in seconds;
- HTTP-date.

The delay is bounded by `MaxRetryAfterSeconds`, which defaults to 30 seconds. If `Retry-After` is missing or invalid, bounded exponential backoff is used instead.

## Paging safety

Paged Device Association reads:

- follow `@odata.nextLink` only over HTTPS to `graph.microsoft.com`;
- reject repeated next links to prevent loops;
- enforce a maximum page count;
- reject null collection responses;
- reject collection responses where the required `value` property is missing or null;
- accept an explicitly empty `value` array as a valid empty page.

A server-provided next link is never allowed to redirect bearer-token traffic to another host.

## Serial-number lookup

The beta API has been observed to return no result for a server-side `serialNumber` filter even when a matching Device Association exists. WindowsDeviceLink therefore:

1. attempts the server-side serial-number filter;
2. validates returned records locally against the exact requested serial number;
3. if there is no exact match, enumerates the collection using bounded paging;
4. performs exact client-side serial matching.

The fallback is fail-safe:

- more than one exact serial match is treated as ambiguous and rejected;
- if full enumeration contains records with no `serialNumber`, absence of the requested serial number is not considered proven;
- an ambiguous or malformed result must not become `NotAssociated` / `LocalOnly`.

## Response validation

Device Association records used by WindowsDeviceLink must contain a non-empty, non-zero association ID and a non-empty `associationState`.

Optional Graph identifiers such as `managedDeviceId` and `devicePreparationPolicyId` may legitimately be absent or represented as an empty GUID. WindowsDeviceLink normalizes those values to `$null` rather than treating the empty GUID as a real resource identifier.

Unknown or future `associationState` values are preserved as returned. They are not coerced to a known healthy state. The health layer classifies an unrecognized state conservatively and safe initialization remains blocked.

## Write operations

### Preassociation POST

`Register-WindowsDeviceLink` does not blindly retry the preassociation POST. A timeout or transport interruption can occur after the server committed the operation, so repeating the POST could create ambiguity or a conflict.

HTTP 409 is surfaced as an explicit duplicate/conflict condition. Successful registration responses are validated using the same Device Association response contract as read operations.

### Association DELETE

`Remove-WindowsDeviceLinkAssociation` does not automatically retry DELETE. A transport timeout can happen after the association was already deleted, so a blind retry cannot safely distinguish an uncommitted operation from a committed one.

When removal is requested by serial number, WindowsDeviceLink first resolves exactly one association ID. Ambiguous serial matches are rejected; the DELETE is never issued against an unresolved record.

## State semantics

A successful lookup that definitively returns no matching association can be reported as `NotAssociated`.

Authentication failures, transport failures, malformed responses, ambiguous duplicate matches and other indeterminate results remain cloud-unknown. `Initialize-WindowsDeviceLink` must not create tenant state when the prior cloud state is unknown.

## Regression coverage

Hardware-independent CI covers the Graph contract against the staged PowerShell Gallery package, including:

- transient and non-transient HTTP behavior;
- timeout/network retry behavior;
- bounded `Retry-After` parsing;
- paging and next-link safety;
- malformed collection responses;
- missing optional properties;
- zero/empty GUID normalization;
- duplicate and incomplete serial results;
- unknown association states;
- registration conflict and response validation;
- the invariant that cloud failures cannot authorize initialization.

Live tenant smoke testing remains separate from deterministic CI because it requires Microsoft Entra/Intune infrastructure and permissions.
