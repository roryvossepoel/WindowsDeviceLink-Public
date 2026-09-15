function Initialize-WindowsDeviceLink {
    <#
    .SYNOPSIS
    Safely ensures that the local DeviceLink has a tenant-side preassociation when appropriate.

    .DESCRIPTION
    Orchestrates existing WindowsDeviceLink operations without performing destructive repair.
    The cmdlet obtains the local DeviceLink, checks the tenant-side Device Association, classifies
    health, and creates a preassociation only when the validated state is LocalOnly.

    Existing preassociated or associated records are left unchanged. Unexpected, incomplete,
    unsupported, or unknown states are blocked rather than repaired automatically.

    This cmdlet never resets firmware state, removes an association, or reboots the device.

    .EXAMPLE
    Initialize-WindowsDeviceLink -Method DeviceCode -TenantId '<tenant-id>'

    Checks current state and creates a preassociation only when one is absent and the local base
    DeviceLink state is valid.

    .EXAMPLE
    Initialize-WindowsDeviceLink -Method DeviceCode -TenantId '<tenant-id>' -WhatIf

    Performs the read-only checks and reports whether registration would be performed.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory)]
        [ValidateSet(
            'DeviceCode','Interactive','ClientSecret','AccessToken','Certificate',
            'CertificateThumbprint','CertificateSubjectName','EnvironmentVariable','ManagedIdentity'
        )]
        [string]$Method,

        [ValidateNotNullOrEmpty()]
        [string]$TenantId,

        [ValidateNotNullOrEmpty()]
        [string]$ClientId,

        [securestring]$AccessToken,

        [System.Security.Cryptography.X509Certificates.X509Certificate2]$Certificate,

        [ValidateNotNullOrEmpty()]
        [string]$CertificateThumbprint,

        [ValidateNotNullOrEmpty()]
        [string]$CertificateSubjectName,

        [bool]$SendCertificateChain = $false,

        [securestring]$ClientSecret,

        [ValidateNotNullOrEmpty()]
        [string]$Environment = 'Global',

        [ValidateRange(1, 600)]
        [double]$ClientTimeout = 100,

        [ValidateNotNullOrEmpty()]
        [string]$WindowsManagementServicePath,

        [ValidateRange(5, 600)]
        [int]$TimeoutSeconds = 120
    )

    $commonOnline = @{
        Method        = $Method
        Environment   = $Environment
        ClientTimeout = $ClientTimeout
    }
    foreach ($name in @(
        'TenantId','ClientId','AccessToken','Certificate','CertificateThumbprint',
        'CertificateSubjectName','SendCertificateChain','ClientSecret'
    )) {
        if ($PSBoundParameters.ContainsKey($name)) {
            $commonOnline[$name] = $PSBoundParameters[$name]
        }
    }

    $statusParameters = @{
        Online         = $true
        Method         = $Method
        Environment    = $Environment
        ClientTimeout  = $ClientTimeout
        TimeoutSeconds = $TimeoutSeconds
    }
    foreach ($name in @(
        'TenantId','ClientId','AccessToken','Certificate','CertificateThumbprint',
        'CertificateSubjectName','SendCertificateChain','ClientSecret','WindowsManagementServicePath'
    )) {
        if ($PSBoundParameters.ContainsKey($name)) {
            $statusParameters[$name] = $PSBoundParameters[$name]
        }
    }

    $beforeStatus = Get-WindowsDeviceLinkStatus @statusParameters
    $beforeHealth = $beforeStatus | Test-WindowsDeviceLinkHealth

    $action = 'Blocked'
    $changed = $false
    $registration = $null
    $afterStatus = $beforeStatus
    $afterHealth = $beforeHealth
    $message = $beforeHealth.Summary

    switch ($beforeHealth.State) {
        'Preassociated' {
            $action = 'None'
            $message = 'The DeviceLink is already preassociated. No change was made.'
        }
        'Associated' {
            $action = 'None'
            $message = 'The DeviceLink is already associated. No change was made.'
        }
        'LocalOnly' {
            $action = 'Register'
            $deviceLinkParameters = @{ TimeoutSeconds = $TimeoutSeconds }
            if ($PSBoundParameters.ContainsKey('WindowsManagementServicePath')) {
                $deviceLinkParameters.WindowsManagementServicePath = $WindowsManagementServicePath
            }
            $deviceLink = Get-WindowsDeviceLink @deviceLinkParameters

            if ($PSCmdlet.ShouldProcess($deviceLink.SerialNumber, 'Create the missing tenant-side DeviceLink preassociation')) {
                $registerParameters = @{}
                foreach ($key in $commonOnline.Keys) { $registerParameters[$key] = $commonOnline[$key] }
                $registerParameters.InputObject = $deviceLink
                $registerParameters.Confirm = $false
                $registration = Register-WindowsDeviceLink @registerParameters
                $changed = $true

                # Verify through the explicit read path rather than assuming the POST response is sufficient.
                $afterStatus = Get-WindowsDeviceLinkStatus @statusParameters
                $afterHealth = $afterStatus | Test-WindowsDeviceLinkHealth

                if ($afterHealth.State -notin @('Preassociated','Associated')) {
                    throw "DeviceLink registration returned, but verification did not reach Preassociated or Associated. Verified state: $($afterHealth.State)."
                }
                $message = "DeviceLink registration completed and was verified as $($afterHealth.State)."
            }
            else {
                $message = 'The DeviceLink is locally valid and not associated; registration would be performed.'
            }
        }
        default {
            $message = "Initialization was blocked because the current health state is '$($beforeHealth.State)'. $($beforeHealth.RecommendedAction)"
        }
    }

    [pscustomobject]@{
        PSTypeName         = 'Windows.DeviceLink.InitializationResult'
        Action             = $action
        Changed            = $changed
        BeforeState        = $beforeHealth.State
        AfterState         = $afterHealth.State
        Severity           = $afterHealth.Severity
        Message            = $message
        SerialNumber       = $beforeStatus.SerialNumber
        LinkId             = $beforeStatus.LinkId
        AssociationId      = if ($afterStatus.AssociationId) { $afterStatus.AssociationId } elseif ($registration) { $registration.Id } else { $null }
        AssociationState   = $afterStatus.AssociationState
        FirmwareVariables  = $afterStatus.FirmwareVariablesPresent
        RegistrationResult = $registration
        BeforeStatus       = $beforeStatus
        AfterStatus        = $afterStatus
    }
}
