# WindowsDeviceLink validation matrix

Last updated: 2026-09-07

The primary Windows Autopilot Device Preparation Device Association **pre-association** workflow has been validated successfully on both Windows 11 and AMD64 Windows PE.

## Confirmed direct functionality

| Area | Windows 11 | Windows PE |
|---|---:|---:|
| Runtime support detection | Pass | Pass |
| DeviceLink generation | Pass | Pass |
| Graph pre-association | Pass | Pass |
| Duplicate / HTTP 409 handling | Pass | Pass |
| Native `.devicelink.csv` generation | Pass | Pass |
| CSV accepted by Intune | Pass | Pass |
| Export to directory / root | Pass | Pass |
| Device-code authentication | Pass | Pass |
| Client-secret authentication | Pass | Pass |
| Existing access token | Pass | Pass |
| Environment-variable authentication | Pass | Pass |
| Certificate object | Pass | Pass |
| Certificate thumbprint | Pass | Pass |
| Certificate subject name | Pass | Pass |

## 0.4.x online method validation

The high-level `Get-WindowsDeviceLink -Online` interface requires an explicit `-Method`.

Validated parameter behavior:

| Scenario | Result |
|---|---|
| `-Online` without `-Method` | Pass - rejected before DeviceLink generation. |
| `-Method Webhook` without `-WebhookUri` | Pass - rejected with targeted error. |
| Method-incompatible parameter supplied | Pass - rejected with targeted error. |
| `-Method DeviceCode` without `-TenantId` | Pass - rejected with targeted error. |
| `-Method ClientSecret` with missing required input | Pass - rejected with targeted error. |
| `-Method AccessToken` without token | Pass - rejected with targeted error. |

The complete parameter regression set passed on 2026-09-07.

### Live direct-method regression

The following `0.4.1-preview1` flows were repeated successfully on Windows 11:

- `-Method DeviceCode` -> native OAuth -> direct Graph registration -> `preassociated`;
- `-Method ClientSecret` -> native OAuth client credentials -> direct Graph REST -> `preassociated`;
- `-Method AccessToken` -> externally obtained app-only token -> Graph -> `preassociated`;
- `-Method EnvironmentVariable` -> environment-sourced client credentials -> native OAuth -> direct Graph REST -> `preassociated`;
- `-Method Certificate` -> certificate authentication -> `preassociated`;
- `-Method CertificateThumbprint` -> certificate-store lookup -> `preassociated`;
- `-Method CertificateSubjectName` -> certificate-store lookup -> `preassociated`.

Each of these direct methods also produced the targeted HTTP 409 duplicate error when the DeviceLink pre-association already existed.

ClientSecret and EnvironmentVariable now use native OAuth + direct Graph REST on both Windows and WinPE and do not require `Microsoft.Graph.Authentication` for those methods.

`Interactive` and local `ManagedIdentity` remain lower priority because they depend on different user/host conditions and are not required for the primary endpoint and WinPE scenarios.

## Webhook validation

The webhook route has been validated end-to-end on Windows 11.

The schema contract is documented in [`docs/WEBHOOK-SCHEMA-v1.md`](docs/WEBHOOK-SCHEMA-v1.md).

Confirmed module behavior:

- HTTPS POST sent successfully;
- schema header sent;
- request ID header sent;
- `X-WindowsDeviceLink-Key` sent when supplied;
- API key absent from JSON body;
- payload contains DeviceLink plus device/runtime metadata;
- optional `tenantId` included for routing;
- Azure Automation webhook accepts request and starts a job;
- targeted client-side errors exist for common HTTP 400, 401, 403, 404, 408, 429 and 5xx failures.

Confirmed sample Azure Automation receiver behavior:

- PowerShell 7.4 Runtime Environment;
- `Microsoft.Graph.Authentication` package;
- request parsing and schema validation;
- API-key validation using `WindowsDeviceLinkWebhookApiKey`;
- correct API key accepted;
- incorrect API key rejected before Graph registration;
- `WindowsDeviceLinkTenantConfiguration` routing lookup;
- Managed Identity Graph authentication;
- successful Graph DeviceLink pre-association;
- `associationState = preassociated` returned;
- targeted duplicate / HTTP 409 handling.

The complete Windows 11 webhook route was repeated successfully against `0.4.1-preview1` on 2026-09-07.

## Notes

- Full Windows uses the registered Windows Runtime and system `Windows.Management.Service.dll`.
- WinPE uses direct DLL activation.
- The public repository and PowerShell Gallery package do **not** redistribute `Windows.Management.Service.dll`; WinPE users must provide a compatible copy themselves.
- Native CSV generation is used; WindowsDeviceLink does not reconstruct the CSV format.
- Device-code authentication uses direct OAuth 2.0 + Graph REST.
- Client-secret and environment-variable authentication use native OAuth client credentials + direct Graph REST on both Windows and WinPE.

## Remaining validation

- Validate webhook transport in AMD64 WinPE.
- Validate a second target tenant through the same webhook/runbook routing table.
- Additional Windows 11 and WinPE builds.
- Additional OEMs/models.
- Additional file-path/failure edge cases.
- Non-Global Microsoft clouds.

## Association lifecycle

Removal/decommissioning support is a desirable future addition. It must use the Device Association API rather than the classic Autopilot V1 deletion action. The correct Device Association delete operation still needs to be verified before implementation.
