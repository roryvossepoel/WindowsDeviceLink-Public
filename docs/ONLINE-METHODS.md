# Choosing an online method

Starting with `0.4.4-preview1`, WindowsDeviceLink separates local DeviceLink identity from tenant-side Device Association operations.

```text
Get-WindowsDeviceLink
    Local DeviceLink identity only

Get-WindowsDeviceLinkFirmwareState
    Local UEFI / firmware state only

Get-WindowsDeviceLinkAssociation
    Read the tenant-side Intune Device Association

Register-WindowsDeviceLink
    Create the tenant-side Intune pre-association

Remove-WindowsDeviceLinkAssociation
    Remove the tenant-side Intune Device Association

Get-WindowsDeviceLinkStatus -Online
    Combine local diagnostics with tenant-side state

Initialize-WindowsDeviceLink
    Safely ensure a validated LocalOnly device is preassociated
```

`Get-WindowsDeviceLink -Online` has been removed. This is an intentional breaking preview change: local identity retrieval no longer changes meaning when a switch is supplied.

## Authentication methods

The cloud cmdlets accept an explicit authentication `-Method` where authentication is required.

| Method | Best fit | Credentials on device | Required input |
|---|---|---:|---|
| `DeviceCode` | Interactive admin/test workflow | No persistent secret | Optional `TenantId`, optional `ClientId` |
| `Interactive` | Interactive Graph SDK workflow | No persistent secret | Optional `TenantId`, optional `ClientId` |
| `ClientSecret` | Unattended direct Graph call | Yes | `TenantId`, `ClientId`, `ClientSecret` |
| `AccessToken` | Caller already has a Graph token | Token in memory | `AccessToken`; optional `TenantId` |
| `Certificate` | Unattended Graph SDK call | Certificate/private key | `TenantId`, `ClientId`, `Certificate` |
| `CertificateThumbprint` | Certificate already installed locally | Certificate/private key | `TenantId`, `ClientId`, `CertificateThumbprint` |
| `CertificateSubjectName` | Certificate already installed locally | Certificate/private key | `TenantId`, `ClientId`, `CertificateSubjectName` |
| `EnvironmentVariable` | Existing client-credential automation | Yes | `AZURE_TENANT_ID`, `AZURE_CLIENT_ID`, `AZURE_CLIENT_SECRET` |
| `ManagedIdentity` | Azure-hosted execution with an identity | No | Optional `ClientId` |
| `Webhook` | Registration through the Azure Function backend | No Graph credential | `WebhookUri`; optional `WebhookApiKey`, `TenantId` |

`Webhook` applies to `Register-WindowsDeviceLink`. Association lookup/removal and online diagnostics are direct tenant-side Graph operations. `Initialize-WindowsDeviceLink` intentionally excludes Webhook because it must read and verify tenant-side state as part of its idempotent workflow.

## Tenant selection

For delegated authentication (`Interactive` and `DeviceCode`) and caller-supplied `AccessToken` authentication, `-TenantId` is optional.

When delegated authentication is used without `-TenantId`, the sign-in context determines the tenant. Native `DeviceCode` uses the Microsoft identity platform `organizations` authority. For `DeviceCode` and `AccessToken`, WindowsDeviceLink resolves the token `tid` claim on a best-effort basis for result metadata and tenant-side correlation.

Specify `-TenantId` when you intentionally need to target a particular tenant, especially in multitenant or guest-account scenarios. App-only client-credential and certificate authentication remain tenant-specific because their token authority must identify the target tenant.

WindowsDeviceLink does not prescribe one delegated authentication method. Use the method compatible with the runtime and the tenant's access policies.


## DeviceCode client ID

When `-Method DeviceCode` is used without an explicit `-ClientId`, WindowsDeviceLink uses this well-known Microsoft public client ID:

```text
14d82eec-204b-4c2f-b7e8-296a70dab67e
```

This is the Microsoft Graph PowerShell / Graph Command Line Tools public client ID. It is not a customer-specific application registration, tenant identifier, client secret, certificate, or confidential credential. Public client IDs are identifiers, not secrets.

You can override it with your own public client application ID.

## Manual pre-association

First obtain the local identity, then explicitly register it:

```powershell
$deviceLink = Get-WindowsDeviceLink

$deviceLink | Register-WindowsDeviceLink `
    -Method DeviceCode `
    -TenantId '<tenant-id>'
```

This makes the state-changing cloud operation visible in the command name and pipeline.

## Query the tenant-side association

By serial number:

```powershell
Get-WindowsDeviceLinkAssociation `
    -SerialNumber '<serial-number>' `
    -Method DeviceCode `
    -TenantId '<tenant-id>'
```

Or by the exact association ID:

```powershell
Get-WindowsDeviceLinkAssociation `
    -AssociationId '<association-id>' `
    -Method DeviceCode `
    -TenantId '<tenant-id>'
```

The returned object uses the type name `Windows.DeviceLink.Association` and contains the association state, managed-device linkage, timestamps and Device Preparation policy information returned by Microsoft Graph.

### Serial-number lookup note

Live validation showed that the Graph beta endpoint can accept a `serialNumber` filter yet return no match for a record that is present. The module therefore retains a paged client-side matching fallback. This produced correct results for both existing and absent associations, but may be inefficient with large Device Association populations. The behavior is tracked in GitHub issue #1 and should be retested as the beta API evolves.

## Combined online status

`Get-WindowsDeviceLinkStatus` is local by default. Add `-Online` only when tenant correlation is required:

```powershell
Get-WindowsDeviceLinkStatus `
    -Online `
    -Method DeviceCode `
    -TenantId '<tenant-id>'
```

A confirmed lookup with no record returns `CloudChecked=True`, `AssociationPresent=False`, and `AssociationState=NotAssociated`. Authentication/Graph failures instead return `AssociationState=Unknown` plus `AssociationError`; they are not treated as proof that no association exists.

## Safe initialization

For the common workflow “preassociate this device if it is locally healthy and not already known to the tenant”:

```powershell
Initialize-WindowsDeviceLink `
    -Method DeviceCode `
    -TenantId '<tenant-id>'
```

The initializer obtains combined status, classifies it, and only registers from the validated `LocalOnly` state. It then verifies the result using the read path. `Preassociated` and `Associated` return `Action=None`; unexpected or incomplete states are blocked. It never resets firmware, removes associations, or reboots.

With `-Method DeviceCode`, one access token is obtained at the start and reused for lookup, registration, and verification. The token is kept in memory only for the run and is not included in the result object.

`-WhatIf` still performs the required read-only cloud lookup so it can determine whether registration would be needed, but it suppresses the registration write.

## Unattended endpoint or WinPE

Prefer `Webhook` for direct registration when Graph secrets or certificates should not be stored on the endpoint:

```powershell
$deviceLink = Get-WindowsDeviceLink

$deviceLink | Register-WindowsDeviceLink `
    -Method Webhook `
    -WebhookUri '<webhook-url>' `
    -WebhookApiKey $env:WINDOWSDEVICELINK_WEBHOOK_API_KEY `
    -TenantId '<target-tenant-id>'
```

The Azure Function backend owns tenant routing and Graph authentication.

For idempotent `Initialize-WindowsDeviceLink`, use one of its supported direct authentication methods because initialization requires tenant-side lookup and verification.

## Existing Graph SDK session

`Register-WindowsDeviceLink` retains the advanced connected-session pattern. If `Connect-WindowsDeviceLink` has already established a Microsoft Graph session, `-Method` can be omitted:

```powershell
Connect-WindowsDeviceLink -TenantId '<tenant-id>'
Get-WindowsDeviceLink | Register-WindowsDeviceLink
```

## Parameter validation

WindowsDeviceLink rejects missing required method inputs and parameters that do not belong to the selected authentication method. `Get-WindowsDeviceLinkAssociation` also requires exactly one of `-SerialNumber` or `-AssociationId`.
