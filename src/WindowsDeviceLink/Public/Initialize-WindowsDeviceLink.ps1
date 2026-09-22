function Initialize-WindowsDeviceLink {
    <#
    .SYNOPSIS
    Safely ensures that the local DeviceLink has a tenant-side preassociation and can optionally complete device-side association.

    .DESCRIPTION
    Orchestrates existing WindowsDeviceLink operations without performing destructive repair.
    The cmdlet obtains the local DeviceLink, checks the tenant-side Device Association, classifies
    health, and creates a preassociation only when the validated state is LocalOnly.

    By default, existing preassociated or associated records are left unchanged. Specify
    -FullAssociation to opt in to full association after the state has been verified as
    Preassociated. Completion uses the guarded Complete-WindowsDeviceLinkAssociation cmdlet and
    therefore performs at most one ConfigureDeviceLinkAsync call, with no retry, reset, cleanup,
    cloud deletion, or reboot.

    Unexpected, incomplete, unsupported, or unknown states are blocked rather than repaired
    automatically.

    For DeviceCode authentication, one token is acquired at the start and reused for lookup,
    registration, and verification so one initialization run requires only one device-code sign-in.

    This cmdlet never resets firmware state, removes an association, or reboots the device.
    #>
    [CmdletBinding(DefaultParameterSetName = 'Direct', SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'Direct')]
        [ValidateSet('DeviceCode','Interactive','ClientSecret','AccessToken','Certificate','CertificateThumbprint','CertificateSubjectName','EnvironmentVariable','ManagedIdentity')]
        [string]$Method,
        [Parameter(ParameterSetName = 'Direct')][ValidateNotNullOrEmpty()][string]$TenantId,
        [Parameter(ParameterSetName = 'Direct')][ValidateNotNullOrEmpty()][string]$ClientId,
        [Parameter(ParameterSetName = 'Direct')][securestring]$AccessToken,
        [Parameter(ParameterSetName = 'Direct')][System.Security.Cryptography.X509Certificates.X509Certificate2]$Certificate,
        [Parameter(ParameterSetName = 'Direct')][ValidateNotNullOrEmpty()][string]$CertificateThumbprint,
        [Parameter(ParameterSetName = 'Direct')][ValidateNotNullOrEmpty()][string]$CertificateSubjectName,
        [Parameter(ParameterSetName = 'Direct')][bool]$SendCertificateChain = $false,
        [Parameter(ParameterSetName = 'Direct')][securestring]$ClientSecret,

        [Parameter(Mandatory, ParameterSetName = 'Backend')]
        [ValidateNotNull()]
        [uri]$BackendUri,

        [Parameter(Mandatory, ParameterSetName = 'Backend')]
        [ValidateNotNullOrEmpty()]
        [string]$BackendApiKey,

        [Parameter(Mandatory, ParameterSetName = 'Backend')]
        [guid]$TargetTenantId,
        [ValidateNotNullOrEmpty()][string]$Environment = 'Global',
        [ValidateRange(1, 600)][double]$ClientTimeout = 100,
        [ValidateNotNullOrEmpty()][string]$WindowsManagementServicePath,
        [ValidateRange(5, 600)][int]$TimeoutSeconds = 120,
        [switch]$FullAssociation
    )

    if ($PSCmdlet.ParameterSetName -eq 'Backend') {
        $targetTenant = $TargetTenantId.ToString().ToLowerInvariant()
        $statusParameters = @{
            BackendUri = $BackendUri
            BackendApiKey = $BackendApiKey
            TimeoutSeconds = $TimeoutSeconds
        }
        if ($PSBoundParameters.ContainsKey('WindowsManagementServicePath')) {
            $statusParameters.WindowsManagementServicePath = $WindowsManagementServicePath
        }

        $beforeStatus = Get-WindowsDeviceLinkBackendStatus @statusParameters
        $beforeHealth = $beforeStatus | Test-WindowsDeviceLinkHealth

        if ($beforeStatus.AssociationPresent -and
            -not [string]::IsNullOrWhiteSpace([string]$beforeStatus.TenantId) -and
            ([string]$beforeStatus.TenantId).Trim().ToLowerInvariant() -ne $targetTenant) {

            return [pscustomobject]@{
                PSTypeName='Windows.DeviceLink.InitializationResult'
                Action='Blocked'
                Changed=$false
                FullAssociationRequested=[bool]$FullAssociation
                FullAssociationResult=$null
                FullAssociationDetails=$null
                BeforeState='AssociationInDifferentTenant'
                AfterState='AssociationInDifferentTenant'
                Severity='Warning'
                Message="Initialization was blocked because the Device Association exists in another tenant. Use an explicit tenant-move workflow before targeting tenant '$targetTenant'."
                SerialNumber=$beforeStatus.SerialNumber
                LinkId=$beforeStatus.LinkId
                AssociationId=$beforeStatus.AssociationId
                AssociationState=$beforeStatus.AssociationState
                FirmwareVariables=$beforeStatus.FirmwareVariablesPresent
                RegistrationResult=$null
                BeforeStatus=$beforeStatus
                AfterStatus=$beforeStatus
            }
        }

        $action = Resolve-WindowsDeviceLinkInitializationAction -HealthState $beforeHealth.State
        $changed = $false
        $registration = $null
        $completion = $null
        $fullAssociationResult = $null
        $afterStatus = $beforeStatus
        $afterHealth = $beforeHealth
        $message = $beforeHealth.Summary

        switch ($action) {
            'None' {
                if ($beforeHealth.State -eq 'Preassociated') {
                    $message = 'The DeviceLink is already preassociated in the requested target tenant. No cloud change was made.'
                }
                else {
                    $message = 'The DeviceLink is already associated in the requested target tenant. No cloud change was made.'
                }
            }
            'Register' {
                $deviceLinkParameters = @{ TimeoutSeconds = $TimeoutSeconds }
                if ($PSBoundParameters.ContainsKey('WindowsManagementServicePath')) {
                    $deviceLinkParameters.WindowsManagementServicePath = $WindowsManagementServicePath
                }
                $deviceLink = Get-WindowsDeviceLink @deviceLinkParameters

                if ($PSCmdlet.ShouldProcess($deviceLink.SerialNumber, "Create the missing DeviceLink pre-association in target tenant $targetTenant through the Azure Function backend")) {
                    $preassociateUri = Resolve-WindowsDeviceLinkBackendEndpoint -BackendUri $BackendUri -Route preassociate
                    $registration = Invoke-WindowsDeviceLinkWebhook -InputObject $deviceLink -WebhookUri $preassociateUri -WebhookApiKey $BackendApiKey -TenantId $targetTenant
                    $changed = $true

                    $afterStatus = Get-WindowsDeviceLinkBackendStatus @statusParameters
                    $afterHealth = $afterStatus | Test-WindowsDeviceLinkHealth
                    if ($afterHealth.State -notin @('Preassociated','Associated')) {
                        throw "Function pre-association returned, but verification did not reach Preassociated or Associated. Verified state: $($afterHealth.State)."
                    }
                    if (([string]$afterStatus.TenantId).Trim().ToLowerInvariant() -ne $targetTenant) {
                        throw 'Function pre-association verification returned an unexpected target tenant.'
                    }
                    $message = "DeviceLink pre-association completed through the Azure Function backend and was verified as $($afterHealth.State)."
                }
                else {
                    $message = 'The DeviceLink is locally valid and not associated; Function-backed pre-association would be performed.'
                    if ($FullAssociation) { $fullAssociationResult = 'WouldPreassociateAndComplete' }
                }
            }
            default {
                $message = "Initialization was blocked because the current health state is '$($beforeHealth.State)'. $($beforeHealth.RecommendedAction)"
            }
        }

        if ($FullAssociation -and $afterHealth.State -eq 'Preassociated') {
            $target = if ($afterStatus.SerialNumber) { $afterStatus.SerialNumber } else { 'DeviceLink' }
            if ($PSCmdlet.ShouldProcess($target, 'Perform full DeviceLink association on this device')) {
                $completeParameters = @{ TimeoutSeconds = $TimeoutSeconds; Confirm = $false }
                if ($PSBoundParameters.ContainsKey('WindowsManagementServicePath')) {
                    $completeParameters.WindowsManagementServicePath = $WindowsManagementServicePath
                }

                $completion = Complete-WindowsDeviceLinkAssociation @completeParameters
                $fullAssociationResult = [string]$completion.Result
                if ($completion.Changed) { $changed = $true }

                $afterStatus = Get-WindowsDeviceLinkBackendStatus @statusParameters
                $afterHealth = $afterStatus | Test-WindowsDeviceLinkHealth
                if ($afterHealth.State -ne 'Associated') {
                    throw "DeviceLink full association returned, but Function-backed verification did not reach Associated. Verified state: $($afterHealth.State)."
                }
                if (([string]$afterStatus.TenantId).Trim().ToLowerInvariant() -ne $targetTenant) {
                    throw 'Full-association verification returned an unexpected target tenant.'
                }
                $message = 'DeviceLink full association succeeded and the final Function-backed cloud state was verified as Associated.'
            }
            elseif (-not $fullAssociationResult) {
                $fullAssociationResult = 'WouldComplete'
                $message = 'The DeviceLink is preassociated; full association would be performed.'
            }
        }
        elseif ($FullAssociation -and $afterHealth.State -eq 'Associated') {
            $fullAssociationResult = 'AlreadyAssociated'
            $message = 'The DeviceLink is already fully associated in the requested target tenant. No full-association change was required.'
        }

        return [pscustomobject]@{
            PSTypeName='Windows.DeviceLink.InitializationResult'
            Action=$action
            Changed=$changed
            FullAssociationRequested=[bool]$FullAssociation
            FullAssociationResult=$fullAssociationResult
            FullAssociationDetails=$completion
            BeforeState=$beforeHealth.State
            AfterState=$afterHealth.State
            Severity=$afterHealth.Severity
            Message=$message
            SerialNumber=$beforeStatus.SerialNumber
            LinkId=$beforeStatus.LinkId
            AssociationId=$afterStatus.AssociationId
            AssociationState=$afterStatus.AssociationState
            FirmwareVariables=$afterStatus.FirmwareVariablesPresent
            RegistrationResult=$registration
            BeforeStatus=$beforeStatus
            AfterStatus=$afterStatus
        }
    }

    $effectiveAccessToken = $null
    try {
        $effectiveMethod = $Method
        if ($Method -eq 'DeviceCode') {
            if ($Environment -ne 'Global') { throw 'Native DeviceCode initialization currently supports the Global Microsoft cloud only.' }
            $tokenParameters = @{}
            if ($TenantId) { $tokenParameters.TenantId = $TenantId }
            if ($ClientId) { $tokenParameters.ClientId = $ClientId }
            Write-Information -InformationAction Continue -MessageData 'Using native OAuth device-code authentication for DeviceLink initialization.'
            $token = Get-WindowsDeviceLinkDeviceCodeToken @tokenParameters
            $effectiveAccessToken = ConvertTo-SecureString $token.AccessToken -AsPlainText -Force
            $TenantId = $token.TenantId
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
        $changed = $false
        $registration = $null
        $completion = $null
        $fullAssociationResult = $null
        $afterStatus = $beforeStatus
        $afterHealth = $beforeHealth
        $message = $beforeHealth.Summary

        switch ($action) {
            'None' {
                if ($beforeHealth.State -eq 'Preassociated') {
                    $message = 'The DeviceLink is already preassociated. No change was made.'
                }
                else {
                    $message = 'The DeviceLink is already associated. No change was made.'
                }
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
                else {
                    $message = 'The DeviceLink is locally valid and not associated; registration would be performed.'
                }
            }
            default {
                $message = "Initialization was blocked because the current health state is '$($beforeHealth.State)'. $($beforeHealth.RecommendedAction)"
            }
        }

        if ($FullAssociation -and $afterHealth.State -eq 'Preassociated') {
            $target = if ($afterStatus.SerialNumber) { $afterStatus.SerialNumber } else { 'DeviceLink' }
            if ($PSCmdlet.ShouldProcess($target, 'Complete the tenant DeviceLink association on this device')) {
                $completeParameters = @{ TimeoutSeconds = $TimeoutSeconds; Confirm = $false }
                if ($PSBoundParameters.ContainsKey('WindowsManagementServicePath')) {
                    $completeParameters.WindowsManagementServicePath = $WindowsManagementServicePath
                }
                $completion = Complete-WindowsDeviceLinkAssociation @completeParameters
                $fullAssociationResult = [string]$completion.Result
                if ($completion.Changed) { $changed = $true }

                $afterStatus = Get-WindowsDeviceLinkStatus @statusParameters
                $afterHealth = $afterStatus | Test-WindowsDeviceLinkHealth
                if ($afterHealth.State -ne 'Associated') {
                    throw "DeviceLink completion returned, but verification did not reach Associated. Verified state: $($afterHealth.State)."
                }
                $message = 'DeviceLink full association succeeded and the final state was verified as Associated.'
            }
            else {
                $fullAssociationResult = 'WouldComplete'
                $message = 'The DeviceLink is preassociated; device-side full association would be performed.'
            }
        }
        elseif ($FullAssociation -and $afterHealth.State -eq 'Associated') {
            if ($completion) {
                $fullAssociationResult = [string]$completion.Result
                $message = 'DeviceLink full association succeeded and the final state was verified as Associated.'
            }
            else {
                $fullAssociationResult = 'AlreadyAssociated'
                $message = 'The DeviceLink is already associated. No completion change was required.'
            }
        }

        [pscustomobject]@{
            PSTypeName='Windows.DeviceLink.InitializationResult'
            Action=$action
            Changed=$changed
            FullAssociationRequested=[bool]$FullAssociation
            FullAssociationResult=$fullAssociationResult
            FullAssociationDetails=$completion
            BeforeState=$beforeHealth.State
            AfterState=$afterHealth.State
            Severity=$afterHealth.Severity
            Message=$message
            SerialNumber=$beforeStatus.SerialNumber
            LinkId=$beforeStatus.LinkId
            AssociationId=if ($afterStatus.AssociationId) { $afterStatus.AssociationId } elseif ($registration) { $registration.Id } else { $null }
            AssociationState=$afterStatus.AssociationState
            FirmwareVariables=$afterStatus.FirmwareVariablesPresent
            RegistrationResult=$registration
            BeforeStatus=$beforeStatus
            AfterStatus=$afterStatus
        }
    }
    finally {
        $effectiveAccessToken = $null
    }
}
