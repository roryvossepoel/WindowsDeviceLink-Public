function Set-WindowsDeviceLinkTenant {
    <#
    .SYNOPSIS
    Ensures that the local device is pre-associated using Direct or Backend mode.
    .DESCRIPTION
    Direct mode uses one Microsoft Graph authentication context and can perform New or
    no-op in that tenant. TenantId is optional for interactive and device-code sign-in;
    when omitted, the authenticated tenant context is authoritative.

    Backend mode uses the Function tenant catalog and authoritative multitenant lookup
    to choose New, None, or Move. The backend never chooses the target tenant.

    A Move is a deliberate physical-device transfer: after confirmation, this cmdlet
    clears the local DeviceLink UEFI identity, creates a new TPM-backed identity, and
    asks the backend to delete the proven source record and pre-associate the new
    identity with the target. Cloud state is then read back across all configured
    tenants. No mutation is blindly retried.

    Run this operation from Windows PE or from the intended OOBE servicing context.
    Clearing DeviceLink firmware doesn't unenroll Windows or remove Entra/Intune
    device records belonging to the previous deployment.
    #>
    [CmdletBinding(DefaultParameterSetName='Direct',SupportsShouldProcess,ConfirmImpact='High')]
    param(
        [Parameter(Mandatory,ParameterSetName='Direct')]
        [ValidateSet('DeviceCode','Interactive','ClientSecret','AccessToken','Certificate','CertificateThumbprint','CertificateSubjectName','EnvironmentVariable','ManagedIdentity')]
        [string]$Method,
        [Parameter(ParameterSetName='Direct')][ValidateNotNullOrEmpty()][string]$TenantId,
        [Parameter(ParameterSetName='Direct')][ValidateNotNullOrEmpty()][string]$ClientId,
        [Parameter(ParameterSetName='Direct')][securestring]$AccessToken,
        [Parameter(ParameterSetName='Direct')][System.Security.Cryptography.X509Certificates.X509Certificate2]$Certificate,
        [Parameter(ParameterSetName='Direct')][ValidateNotNullOrEmpty()][string]$CertificateThumbprint,
        [Parameter(ParameterSetName='Direct')][ValidateNotNullOrEmpty()][string]$CertificateSubjectName,
        [Parameter(ParameterSetName='Direct')][bool]$SendCertificateChain = $false,
        [Parameter(ParameterSetName='Direct')][securestring]$ClientSecret,
        [Parameter(ParameterSetName='Direct')][ValidateNotNullOrEmpty()][string]$Environment = 'Global',
        [Parameter(ParameterSetName='Direct')][ValidateRange(1,600)][double]$ClientTimeout = 100,

        [Parameter(Mandatory,ParameterSetName='BackendById')]
        [Parameter(Mandatory,ParameterSetName='BackendByName')]
        [ValidateNotNull()][uri]$BackendUri,
        [Parameter(Mandatory,ParameterSetName='BackendById')]
        [Parameter(Mandatory,ParameterSetName='BackendByName')]
        [ValidateNotNull()][securestring]$BackendApiKey,
        [Parameter(Mandatory,ParameterSetName='BackendById')][guid]$TargetTenantId,
        [Parameter(Mandatory,ParameterSetName='BackendByName')][ValidateNotNullOrEmpty()][string]$TargetTenantName,
        [ValidateNotNullOrEmpty()][string]$WindowsManagementServicePath,
        [ValidateRange(5,600)][int]$TimeoutSeconds = 120
    )

    if ($PSCmdlet.ParameterSetName -eq 'Direct') {
        $parameters = @{
            Method=$Method
            TimeoutSeconds=$TimeoutSeconds
            Environment=$Environment
            ClientTimeout=$ClientTimeout
        }
        foreach ($name in @('TenantId','ClientId','AccessToken','Certificate','CertificateThumbprint','CertificateSubjectName','SendCertificateChain','ClientSecret','WindowsManagementServicePath')) {
            if ($PSBoundParameters.ContainsKey($name)) { $parameters[$name]=$PSBoundParameters[$name] }
        }

        $initialization = Initialize-WindowsDeviceLink @parameters
        $decision = switch ([string]$initialization.Action) {
            'Register' { 'New' }
            'None' { 'None' }
            default { 'Blocked' }
        }
        $effectiveTenant = if ($initialization.AfterStatus.TenantId) { [string]$initialization.AfterStatus.TenantId } elseif ($TenantId) { [string]$TenantId } else { $null }
        $success = $decision -ne 'Blocked'
        return [pscustomobject]@{
            PSTypeName='Windows.DeviceLink.TenantAssignmentResult'
            Success=$success
            Changed=[bool]$initialization.Changed
            OperationMode='Direct'
            Decision=$decision
            ReasonCode=if ($decision -eq 'New') { 'WDL-DIRECT-NEW' } elseif ($decision -eq 'None') { 'WDL-DIRECT-NO-CHANGE' } else { 'WDL-DIRECT-BLOCKED' }
            RetrySafe=if ($success) { $true } else { $false }
            RecommendedAction=if ($success) { 'None' } else { [string]$initialization.Message }
            SerialNumber=[string]$initialization.SerialNumber
            SourceTenantId=$effectiveTenant
            TargetTenantId=$effectiveTenant
            TargetTenantName=$null
            PreviousLinkId=[string]$initialization.LinkId
            NewLinkId=[string]$initialization.LinkId
            AssociationId=[string]$initialization.AssociationId
            AssociationState=[string]$initialization.AssociationState
            RequestId=$null
            Message=[string]$initialization.Message
            Details=$initialization
        }
    }

    $credential = New-Object System.Management.Automation.PSCredential('api-key',$BackendApiKey)
    $plainKey = $null
    try {
        $plainKey = $credential.GetNetworkCredential().Password
        $catalog = Invoke-WindowsDeviceLinkBackendTenantCatalog -BackendUri $BackendUri -BackendApiKey $plainKey
        $catalogTenants = @($catalog.tenants)

        if ($PSCmdlet.ParameterSetName -eq 'BackendByName') {
            $targetMatches = @($catalogTenants | Where-Object { [string]$_.name -ieq $TargetTenantName.Trim() })
            if ($targetMatches.Count -ne 1) {
                throw "Target tenant name '$TargetTenantName' resolved to $($targetMatches.Count) catalog entries; exactly one is required."
            }
            $targetId = ([guid][string]$targetMatches[0].tenantId).ToString().ToLowerInvariant()
            $targetName = [string]$targetMatches[0].name
        }
        else {
            $targetId = $TargetTenantId.ToString().ToLowerInvariant()
            $targetMatches = @($catalogTenants | Where-Object { [string]$_.tenantId -ieq $targetId })
            if ($targetMatches.Count -ne 1) { throw "Target tenant '$targetId' is not uniquely present in the Function backend catalog." }
            $targetName = [string]$targetMatches[0].name
        }

        $runtime = @{ TimeoutSeconds=$TimeoutSeconds }
        if ($PSBoundParameters.ContainsKey('WindowsManagementServicePath')) { $runtime.WindowsManagementServicePath=$WindowsManagementServicePath }
        $currentDeviceLink = Get-WindowsDeviceLink @runtime
        $localBefore = Get-WindowsDeviceLinkLocalAssociation
        if ($localBefore.ConflictDetected) { throw 'Local tenant evidence conflicts. No local or cloud state was changed.' }
        if ([string]$localBefore.FirmwareState -notin @('2/4','4/4')) {
            throw "Local firmware state '$($localBefore.FirmwareState)' isn't safe for tenant assignment. No state was changed."
        }

        $lookup = Invoke-WindowsDeviceLinkBackendLookup -BackendUri $BackendUri -BackendApiKey $plainKey -SerialNumber $currentDeviceLink.SerialNumber
        $tenantRows = @($lookup.tenants)
        $matches = @($lookup.matches)
        if ($lookup.success -ne $true -or [int]$lookup.failedTenantCount -ne 0 -or
            [int]$lookup.successfulTenantCount -ne $catalogTenants.Count -or
            [int]$lookup.searchedTenantCount -ne $catalogTenants.Count -or
            $tenantRows.Count -ne $catalogTenants.Count -or
            @($lookup.tenantErrors).Count -ne 0 -or
            @($tenantRows | Where-Object { $_.success -ne $true }).Count -ne 0) {
            throw '[WDL-BACKEND-LOOKUP-INCOMPLETE] The Function lookup did not prove a complete read across the configured tenant catalog. No state was changed.'
        }
        $catalogIds = @($catalogTenants | ForEach-Object { ([guid][string]$_.tenantId).ToString().ToLowerInvariant() } | Sort-Object)
        $lookupIds = @($tenantRows | ForEach-Object { ([guid][string]$_.tenantId).ToString().ToLowerInvariant() } | Sort-Object)
        if (@(Compare-Object $catalogIds $lookupIds).Count -ne 0) {
            throw '[WDL-BACKEND-CATALOG-MISMATCH] The Function lookup tenant set differs from the authenticated tenant catalog. No state was changed.'
        }
        if ($matches.Count -gt 1 -or [int]$lookup.matchCount -ne $matches.Count) {
            throw '[WDL-BACKEND-ASSOCIATION-AMBIGUOUS] The Function lookup returned ambiguous or inconsistent association state. No state was changed.'
        }

        $source = if ($matches.Count -eq 1) { $matches[0] } else { $null }
        $sourceId = if ($source) { ([guid][string]$source.tenantId).ToString().ToLowerInvariant() } else { $null }
        if ($source -and ([string]$source.serialNumber -ine [string]$currentDeviceLink.SerialNumber -or
            [string]$source.associationState -notin @('preassociated','associated'))) {
            throw 'The Function lookup returned a source record with an unexpected serial number or association state. No state was changed.'
        }
        if ($sourceId -and $localBefore.TenantId -and [string]$localBefore.TenantId -ine $sourceId) {
            throw '[WDL-LOCAL-CLOUD-CONFLICT] Local tenant evidence differs from the authoritative cloud source. No state was changed.'
        }
        $assignmentDecision = Resolve-WindowsDeviceLinkTenantAssignmentDecision -OperationMode Backend `
            -SourceTenantId $sourceId -TargetTenantId $targetId -FirmwareState ([string]$localBefore.FirmwareState)
        $decision = [string]$assignmentDecision.Decision

        if ($decision -eq 'None') {
            return [pscustomobject]@{
                PSTypeName='Windows.DeviceLink.TenantAssignmentResult'; Success=$true; Decision='None'; Changed=$false; OperationMode='Backend'
                ReasonCode='WDL-BACKEND-NO-CHANGE'; RetrySafe=$true; RecommendedAction='None'
                SerialNumber=[string]$currentDeviceLink.SerialNumber; SourceTenantId=$sourceId; TargetTenantId=$targetId
                TargetTenantName=$targetName; PreviousLinkId=[string]$currentDeviceLink.LinkId; NewLinkId=[string]$currentDeviceLink.LinkId
                AssociationId=[string]$source.associationId; AssociationState=[string]$source.associationState
                Message="The device is already present in target tenant '$targetName'. No change was made."
            }
        }

        $renewIdentity = [bool]$assignmentDecision.IdentityRenewalRequired
        $action = if ($decision -eq 'Move') {
            "Renew the local DeviceLink identity, remove the association from tenant $sourceId, and pre-associate it with $targetName ($targetId)"
        } elseif ($renewIdentity) {
            "Create a fresh local DeviceLink identity and pre-associate it with $targetName ($targetId)"
        } else {
            "Pre-associate the current DeviceLink identity with $targetName ($targetId)"
        }
        if (-not $PSCmdlet.ShouldProcess([string]$currentDeviceLink.SerialNumber,$action)) {
            return [pscustomobject]@{
                PSTypeName='Windows.DeviceLink.TenantAssignmentResult'; Success=$true; Decision=$decision; Changed=$false; OperationMode='Backend'
                ReasonCode=if($decision -eq 'Move'){'WDL-BACKEND-MOVE'}else{'WDL-BACKEND-NEW'}; RetrySafe=$true; RecommendedAction='Review WhatIf output and run without -WhatIf to apply.'
                SerialNumber=[string]$currentDeviceLink.SerialNumber; SourceTenantId=$sourceId; TargetTenantId=$targetId
                TargetTenantName=$targetName; PreviousLinkId=[string]$currentDeviceLink.LinkId; NewLinkId=$null
                AssociationId=$null; AssociationState=$null; Message="Would perform $decision for target tenant '$targetName'."
            }
        }

        $previousLinkId = [string]$currentDeviceLink.LinkId
        $deviceLinkForTarget = $currentDeviceLink
        if ($renewIdentity) {
            Reset-WindowsDeviceLinkFirmwareState -Confirm:$false | Out-Null
            $deviceLinkForTarget = Get-WindowsDeviceLink @runtime
            if ([string]::IsNullOrWhiteSpace([string]$deviceLinkForTarget.LinkId) -or [string]$deviceLinkForTarget.LinkId -ieq $previousLinkId) {
                throw 'Local firmware was reset, but Windows did not produce a new DeviceLink LinkId. No backend mutation was requested.'
            }
        }

        try {
            $reconcileParameters = @{
                BackendUri = $BackendUri
                BackendApiKey = $plainKey
                InputObject = $deviceLinkForTarget
                TargetTenantId = $targetId
            }
            if (-not [string]::IsNullOrWhiteSpace($sourceId)) {
                $reconcileParameters.SourceTenantId = $sourceId
            }
            $reconcile = Invoke-WindowsDeviceLinkBackendReconcile @reconcileParameters
        }
        catch {
            if ($renewIdentity) {
                throw ("[WDL-BACKEND-RECONCILE-UNCERTAIN] The local DeviceLink identity was renewed, but backend reconciliation failed. Do not reset again or blindly retry; perform a fresh lookup. " + $_.Exception.Message)
            }
            throw
        }

        $verified = Invoke-WindowsDeviceLinkBackendLookup -BackendUri $BackendUri -BackendApiKey $plainKey -SerialNumber $deviceLinkForTarget.SerialNumber
        $verifiedMatches = @($verified.matches)
        $verifiedTenantRows = @($verified.tenants)
        $verifiedTenantIds = @($verifiedTenantRows | ForEach-Object { ([guid][string]$_.tenantId).ToString().ToLowerInvariant() } | Sort-Object)
        if ($verified.success -ne $true -or [int]$verified.failedTenantCount -ne 0 -or
            [int]$verified.successfulTenantCount -ne $catalogTenants.Count -or
            [int]$verified.searchedTenantCount -ne $catalogTenants.Count -or
            $verifiedTenantRows.Count -ne $catalogTenants.Count -or
            @($verifiedTenantRows | Where-Object { $_.success -ne $true }).Count -ne 0 -or
            @(Compare-Object $catalogIds $verifiedTenantIds).Count -ne 0 -or
            @($verified.tenantErrors).Count -ne 0 -or $verifiedMatches.Count -ne 1 -or
            [int]$verified.matchCount -ne 1 -or [string]$verifiedMatches[0].tenantId -ine $targetId -or
            [string]$verifiedMatches[0].serialNumber -ine [string]$deviceLinkForTarget.SerialNumber) {
            throw '[WDL-BACKEND-VERIFY-UNCERTAIN] Reconcile returned, but the final multitenant lookup did not prove exactly one target association. Perform a fresh lookup before another mutation.'
        }

        [pscustomobject]@{
            PSTypeName='Windows.DeviceLink.TenantAssignmentResult'; Success=$true; Decision=$decision; Changed=$true; OperationMode='Backend'
            ReasonCode=if($decision -eq 'Move'){'WDL-BACKEND-MOVE'}else{'WDL-BACKEND-NEW'}; RetrySafe=$true; RecommendedAction='None'
            SerialNumber=[string]$deviceLinkForTarget.SerialNumber; SourceTenantId=$sourceId; TargetTenantId=$targetId
            TargetTenantName=$targetName; PreviousLinkId=$previousLinkId; NewLinkId=[string]$deviceLinkForTarget.LinkId
            AssociationId=[string]$verifiedMatches[0].associationId; AssociationState=[string]$verifiedMatches[0].associationState
            RequestId=[string]$reconcile.requestId
            Message="DeviceLink tenant assignment completed and was verified in '$targetName'."
        }
    }
    finally { $plainKey=$null; $credential=$null }
}
