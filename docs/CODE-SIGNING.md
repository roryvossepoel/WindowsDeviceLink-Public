# Code signing policy

WindowsDeviceLink is currently unsigned.

The project applied to the SignPath Foundation program in September 2026. SignPath reviewed the application but did not approve it at this stage because the project does not yet show enough external trust/visibility signals such as community adoption, independent references, institutional backing, or sustained external engagement.

The project may reapply when those signals have grown or adopt another suitable signing path. Until a signing solution is active, preview packages remain unsigned.

## Signing scope

If code signing is introduced, only WindowsDeviceLink artifacts built from source maintained by the WindowsDeviceLink project are eligible for signing. The team responsible for signing is the same team responsible for development and maintenance of the project.

The canonical public source repository for releases is:

- https://github.com/roryvossepoel/WindowsDeviceLink-Public

WindowsDeviceLink does not redistribute or sign Microsoft's `Windows.Management.Service.dll`. Windows PE users must supply a compatible Microsoft copy themselves where required.

## Team roles

WindowsDeviceLink is currently maintained by a single maintainer.

- **Committer and reviewer:** Rory Vossepoel (`@roryvossepoel`)
- **Signing approver:** Rory Vossepoel (`@roryvossepoel`) if a signing service is introduced

Changes submitted by contributors who do not have direct commit access are reviewed before merge. Any future signing request must be explicitly approved before a signature is issued.

## Build and provenance

Official release artifacts are built from the project's source repository using automated GitHub Actions workflows. Source code, build scripts, packaging scripts, and workflow definitions are version controlled together.

Any future signed artifacts must be traceable to the corresponding source revision and automated build. Signing must not be used for locally modified, manually assembled, third-party, or unrelated artifacts.

## Release policy

Official releases are distributed through the WindowsDeviceLink GitHub repository and/or the PowerShell Gallery. Product and version metadata must identify WindowsDeviceLink and match the corresponding release.

Unsigned releases must not be represented as signed releases. If signing is introduced later, the release process and documentation will be updated to distinguish signed artifacts clearly.

## Privacy

WindowsDeviceLink does not collect telemetry or transmit information to systems operated by the project maintainer as part of normal operation. Network operations occur only when explicitly requested or configured by the administrator.

See the full [privacy policy](../PRIVACY.md).

## Security-sensitive material

Signing credentials, private keys, API keys, DeviceLink payloads, raw firmware JWT data, tenant secrets, and exported identity files must not be committed to the repository or included in public build logs.

## Policy status

The SignPath Foundation application is not active. This document records the controls that should continue to apply if code signing is introduced in the future.
