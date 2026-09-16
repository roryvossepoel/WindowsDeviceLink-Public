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

    For DeviceCode authentication, one token is acquired at the start and reused for lookup,
    registration, and verification so one initialization run requires only one device-code sign-in.

    This cmdlet never resets firmware state, removes an association, or reboots the device.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('DeviceCode','Interactive','ClientSecret','AccessToken','Certificate','CertificateThumbprint','CertificateSubjectName','EnvironmentVariable','ManagedIdentity')]
        [string]$Method,
        [ValidateNotNullOrEmpty()][string]$TenantId,
        [ValidateNotNullOrEmpty()][string]$ClientId,
        [securestring]$AccessToken,
        [System.Security.Cryptography.X509Certificates.X509Certificate2]$Certificate,
        [ValidateNotNullOrEmpty()][string]$CertificateThumbprint,
        [ValidateNotNullOrEmpty()][string]$CertificateSubjectName,
        [bool]$SendCertificateChain = $false,
        [securestring]$ClientSecret,
        [ValidateNotNullOrEmpty()][string]$Environment = 'Global',
        [ValidateRange(1, 600)][double]$ClientTimeout = 100,
        [ValidateNotNullOrEmpty()][string]$WindowsManagementServicePath,
        [ValidateRange(5, 600)][int]$TimeoutSeconds = 120
    )

    $effectiveAccessToken = $null
    try {
        $effectiveMethod = $Method
        if ($Method -eq 'DeviceCode') {
            if (-not $TenantId) { throw '-TenantId is required for -Method DeviceCode.' }
            if ($Environment -ne 'Global') { throw 'Native DeviceCode initialization currently supports the Global Microsoft cloud only.' }
            $tokenParameters = @{ TenantId = $TenantId }
            if ($ClientId) { $tokenParameters.ClientId = $ClientId }
            Write-Information -InformationAction Continue -MessageData 'Using native OAuth device-code authentication for DeviceLink initialization.'
            $token = Get-WindowsDeviceLinkDeviceCodeToken @tokenParameters
            $effectiveAccessToken = ConvertTo-SecureString $token.AccessToken -AsPlainText -Force
            $token = $null
            $effectiveMethod = 'AccessToken'
        }

        $commonOnline = @{ Method = $effectiveMethod; Environment = $Environment; ClientTimeout = $ClientTimeout }
        if ($effectiveAccessToken) {
            $commonOnline.TenantId = $TenantId
            $commonOnline.AccessToken = $effectiveAccessToken
        }
        else {
            foreach ($name in @('TenantId','ClientId','AccessToken','Certificate','CertificateThumbprint','CertificateSubjectName','SendCertificateChain','ClientSecret')) {
                if ($PSBoundParameters.ContainsKey($name)) { $commonOnline[$name] = $PSBoundParameters[$name] }
            }
        }

        $statusParameters = @{ Online = $true; Method = $effectiveMethod; Environment = $Environment; ClientTimeout = $ClientTimeout; TimeoutSeconds = $TimeoutSeconds }
        foreach ($key in $commonOnline.Keys) {
            if ($key -notin @('Method','Environment','ClientTimeout')) { $statusParameters[$key] = $commonOnline[$key] }
        }
        if ($PSBoundParameters.ContainsKey('WindowsManagementServicePath')) { $statusParameters.WindowsManagementServicePath = $WindowsManagementServicePath }

        $beforeStatus = Get-WindowsDeviceLinkStatus @statusParameters
        $beforeHealth = $beforeStatus | Test-WindowsDeviceLinkHealth
        $action = Resolve-WindowsDeviceLinkInitializationAction -HealthState $beforeHealth.State
        $changed = $false; $registration = $null
        $afterStatus = $beforeStatus; $afterHealth = $beforeHealth; $message = $beforeHealth.Summary

        switch ($action) {
            'None' {
                if ($beforeHealth.State -eq 'Preassociated') { $message = 'The DeviceLink is already preassociated. No change was made.' }
                else { $message = 'The DeviceLink is already associated. No change was made.' }
            }
            'Register' {
                $deviceLinkParameters = @{ TimeoutSeconds = $TimeoutSeconds }
                if ($PSBoundParameters.ContainsKey('WindowsManagementServicePath')) { $deviceLinkParameters.WindowsManagementServicePath = $WindowsManagementServicePath }
                $deviceLink = Get-WindowsDeviceLink @deviceLinkParameters

                if ($PSCmdlet.ShouldProcess($deviceLink.SerialNumber, 'Create the missing tenant-side DeviceLink preassociation')) {
                    $registerParameters = @{}
                    foreach ($key in $commonOnline.Keys) { $registerParameters[$key] = $commonOnline[$key] }
                    $registerParameters.InputObject = $deviceLink
                    $registerParameters.Confirm = $false
                    $registration = Register-WindowsDeviceLink @registerParameters
                    $changed = $true
                    $afterStatus = Get-WindowsDeviceLinkStatus @statusParameters
                    $afterHealth = $afterStatus | Test-WindowsDeviceLinkHealth
                    if ($afterHealth.State -notin @('Preassociated','Associated')) {
                        throw "DeviceLink registration returned, but verification did not reach Preassociated or Associated. Verified state: $($afterHealth.State)."
                    }
                    $message = "DeviceLink registration completed and was verified as $($afterHealth.State)."
                }
                else { $message = 'The DeviceLink is locally valid and not associated; registration would be performed.' }
            }
            default {
                $message = "Initialization was blocked because the current health state is '$($beforeHealth.State)'. $($beforeHealth.RecommendedAction)"
            }
        }

        [pscustomobject]@{
            PSTypeName='Windows.DeviceLink.InitializationResult'; Action=$action; Changed=$changed
            BeforeState=$beforeHealth.State; AfterState=$afterHealth.State; Severity=$afterHealth.Severity; Message=$message
            SerialNumber=$beforeStatus.SerialNumber; LinkId=$beforeStatus.LinkId
            AssociationId=if ($afterStatus.AssociationId) { $afterStatus.AssociationId } elseif ($registration) { $registration.Id } else { $null }
            AssociationState=$afterStatus.AssociationState; FirmwareVariables=$afterStatus.FirmwareVariablesPresent
            RegistrationResult=$registration; BeforeStatus=$beforeStatus; AfterStatus=$afterStatus
        }
    }
    finally { $effectiveAccessToken = $null }
}
