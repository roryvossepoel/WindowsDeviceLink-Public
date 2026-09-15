# Privacy policy

WindowsDeviceLink does not collect telemetry, analytics, crash reports, or usage data for the project maintainer.

**This program will not transfer any information to other networked systems unless specifically requested by the user or the person installing or operating it.**

## Administrator-initiated network operations

WindowsDeviceLink can perform network operations only when the administrator explicitly chooses an online workflow or installs the module from an online repository.

### Microsoft Graph and Microsoft identity services

When an administrator explicitly uses an online Device Association workflow, WindowsDeviceLink can authenticate to Microsoft identity services and communicate with Microsoft Graph. Depending on the selected operation, information required for Device Association can include device identifiers and DeviceLink data such as the serial number, SMBIOS UUID, DeviceLink ID, tenant ID, and the DeviceLink payload required by the Microsoft API.

These operations are initiated by the administrator and are subject to Microsoft's applicable privacy and service terms.

### Administrator-configured webhook

When the administrator explicitly selects the webhook method, WindowsDeviceLink sends the DeviceLink payload and associated operational metadata to the webhook URI configured by that administrator. If an API key is supplied, it is used only for the configured webhook request.

The WindowsDeviceLink project does not operate a default collection endpoint and does not receive webhook data unless an administrator deliberately configures an endpoint controlled by the project maintainer, which is not part of the normal project design.

### PowerShell Gallery

Installing or updating WindowsDeviceLink from the PowerShell Gallery uses PowerShellGet/PackageManagement and communicates with the PowerShell Gallery infrastructure. This behavior is provided by the user's PowerShell tooling rather than by WindowsDeviceLink itself and is subject to the applicable PowerShell Gallery and Microsoft terms.

## Local data

WindowsDeviceLink can create local output such as an exported `.devicelink.csv` when explicitly requested by the administrator. DeviceLink payloads, serial numbers, SMBIOS UUIDs, Link IDs, firmware JWT data, tenant identifiers, API keys, and exported identity files should be treated as sensitive operational data.

WindowsDeviceLink does not transmit locally generated output to the project maintainer.

## Third-party components and services

WindowsDeviceLink may use Microsoft Graph, Microsoft identity services, the PowerShell Gallery, and an administrator-configured webhook. The privacy policies and operational controls of those third-party or administrator-controlled services apply to data sent to them.

A compatible `Windows.Management.Service.dll` may be supplied by the administrator for Windows PE scenarios. This Microsoft binary is not redistributed by the WindowsDeviceLink project.

## Changes to this policy

Material privacy-related changes will be documented in this repository. The version of this file in the source repository is the authoritative project privacy policy.

## Contact

Questions about this policy can be raised through the WindowsDeviceLink GitHub repository.
