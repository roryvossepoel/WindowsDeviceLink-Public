# Code signing policy

WindowsDeviceLink is applying for code signing through the SignPath Foundation. Until that application is approved and the signing integration is complete, preview packages may remain unsigned.

> **Free code signing provided by SignPath.io, certificate by SignPath Foundation.**

## Signing scope

Only WindowsDeviceLink artifacts built from source maintained by the WindowsDeviceLink project are eligible for signing. The team responsible for signing is the same team responsible for development and maintenance of the project.

The canonical public source repository for signed releases is:

- https://github.com/roryvossepoel/WindowsDeviceLink-Public

WindowsDeviceLink does not redistribute or sign Microsoft's `Windows.Management.Service.dll`. Windows PE users must supply a compatible Microsoft copy themselves where required.

## Team roles

WindowsDeviceLink is currently maintained by a single maintainer.

- **Committer and reviewer:** Rory Vossepoel (`@roryvossepoel`)
- **Signing approver:** Rory Vossepoel (`@roryvossepoel`)

Changes submitted by contributors who do not have direct commit access are reviewed before merge. Every signing request must be explicitly approved before a signature is issued.

## Build and provenance

Official release artifacts are built from the project's source repository using automated GitHub Actions workflows. Source code, build scripts, packaging scripts, and workflow definitions are version controlled together.

Signed artifacts must be traceable to the corresponding source revision and automated build. Signing must not be used for locally modified, manually assembled, third-party, or unrelated artifacts.

## Release policy

Official releases are distributed through the WindowsDeviceLink GitHub repository and/or the PowerShell Gallery. Product and version metadata for signed artifacts must identify WindowsDeviceLink and match the corresponding release.

Releases created before SignPath Foundation approval or before completion of the signing integration can be unsigned and will not be represented as SignPath-signed releases.

## Privacy

WindowsDeviceLink does not collect telemetry or transmit information to systems operated by the project maintainer as part of normal operation. Network operations occur only when explicitly requested or configured by the administrator.

See the full [privacy policy](../PRIVACY.md).

## Security-sensitive material

Signing credentials, private keys, API keys, DeviceLink payloads, raw firmware JWT data, tenant secrets, and exported identity files must not be committed to the repository or included in public build logs.

## Policy status

This policy is intended to satisfy the project's SignPath Foundation application and will be updated if SignPath requires additional controls or once the signing service is activated.
