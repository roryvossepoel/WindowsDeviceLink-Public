using namespace System.Net

param($Request, $TriggerMetadata)

$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'BackendAuth.ps1')
. (Join-Path $PSScriptRoot 'AssociationOperations.ps1')

function Write-JsonResponse {
    param(
        [Parameter(Mandatory)][int]$StatusCode,
        [Parameter(Mandatory)][hashtable]$Body
    )

    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = $StatusCode
        Headers = @{ 'Content-Type' = 'application/json' }
        Body = ($Body | ConvertTo-Json -Depth 10 -Compress)
    })
}

function Get-HeaderValue {
    param(
        [Parameter(Mandatory)][object]$Headers,
        [Parameter(Mandatory)][string]$Name
    )

    foreach ($key in $Headers.Keys) {
        if ([string]$key -ieq $Name) {
            return [string]$Headers[$key]
        }
    }
    return $null
}

function Write-ReconcileError {
    param(
        [Parameter(Mandatory)][int]$StatusCode,
        [Parameter(Mandatory)][string]$Error,
        [Parameter(Mandatory)][string]$Message,
        [string]$RequestId,
        [string]$SourceTenantId,
        [string]$TargetTenantId,
        [string]$Decision
    )

    $response = @{
        success = $false
        requestId = $RequestId
        error = $Error
        message = $Message
    }
    if ($SourceTenantId) { $response.sourceTenantId = $SourceTenantId }
    if ($TargetTenantId) { $response.targetTenantId = $TargetTenantId }
    if ($Decision) { $response.decision = $Decision }

    Write-JsonResponse -StatusCode $StatusCode -Body $response
}

$requestId = Get-HeaderValue -Headers $Request.Headers -Name 'X-WindowsDeviceLink-RequestId'
$schemaHeader = Get-HeaderValue -Headers $Request.Headers -Name 'X-WindowsDeviceLink-Schema'
$providedApiKey = Get-HeaderValue -Headers $Request.Headers -Name 'X-WindowsDeviceLink-Key'
$expectedApiKey = [Environment]::GetEnvironmentVariable('WINDOWSDEVICELINK_API_KEY')

if ([string]::IsNullOrWhiteSpace($expectedApiKey)) {
    Write-ReconcileError -StatusCode 500 -Error 'BackendConfigurationError' -Message 'The webhook API key is not configured.' -RequestId $requestId
    return
}
if ([string]::IsNullOrWhiteSpace($providedApiKey) -or -not (Test-WindowsDeviceLinkSharedSecret -Expected $expectedApiKey -Provided $providedApiKey)) {
    Write-ReconcileError -StatusCode 401 -Error 'Unauthorized' -Message 'Webhook API key validation failed.' -RequestId $requestId
    return
}
if ($schemaHeader -ne '1') {
    Write-ReconcileError -StatusCode 400 -Error 'UnsupportedSchema' -Message 'X-WindowsDeviceLink-Schema must be 1.' -RequestId $requestId
    return
}

try {
    $body = $Request.Body
    if ($body -is [string]) { $body = $body | ConvertFrom-Json -ErrorAction Stop }

    if (-not $body) { throw 'Request body is empty.' }
    if ([int]$body.schemaVersion -ne 1) { throw "Unsupported schemaVersion '$($body.schemaVersion)'." }
    if ([string]$body.requestType -ne 'DeviceLinkReconcile') { throw "Unsupported requestType '$($body.requestType)'." }
    if ([string]::IsNullOrWhiteSpace([string]$body.requestId)) { throw 'requestId is required.' }
    if ($requestId -and $requestId -ne [string]$body.requestId) { throw 'Request ID header and body do not match.' }
    $requestId = [string]$body.requestId

    if ([string]::IsNullOrWhiteSpace([string]$body.targetTenantId)) { throw 'targetTenantId is required.' }
    if (-not $body.device) { throw 'device is required.' }
    if ([string]::IsNullOrWhiteSpace([string]$body.device.serialNumber)) { throw 'device.serialNumber is required.' }
    if ([string]::IsNullOrWhiteSpace([string]$body.device.deviceLink)) { throw 'device.deviceLink is required.' }
}
catch {
    Write-ReconcileError -StatusCode 400 -Error 'InvalidRequest' -Message $_.Exception.Message -RequestId $requestId
    return
}

$sourceTenantId = [string]$body.sourceTenantId
$targetTenantId = ([string]$body.targetTenantId).Trim().ToLowerInvariant()
$serialNumber = ([string]$body.device.serialNumber).Trim()
$deviceLink = [string]$body.device.deviceLink
if ($sourceTenantId) { $sourceTenantId = $sourceTenantId.Trim().ToLowerInvariant() }

$clientId = [Environment]::GetEnvironmentVariable('WINDOWSDEVICELINK_CLIENT_ID')
if ([string]::IsNullOrWhiteSpace($clientId)) {
    Write-ReconcileError -StatusCode 500 -Error 'BackendConfigurationError' -Message 'WINDOWSDEVICELINK_CLIENT_ID is not configured.' -RequestId $requestId -SourceTenantId $sourceTenantId -TargetTenantId $targetTenantId
    return
}

$allowedTenants = @(Get-WindowsDeviceLinkAllowedTenants)
if ($allowedTenants.Count -eq 0) {
    Write-ReconcileError -StatusCode 500 -Error 'BackendConfigurationError' -Message 'No allowed tenants are configured. The backend fails closed.' -RequestId $requestId -SourceTenantId $sourceTenantId -TargetTenantId $targetTenantId
    return
}
if ($targetTenantId -notin $allowedTenants) {
    Write-ReconcileError -StatusCode 403 -Error 'TenantNotAllowed' -Message 'The target tenant is not in the backend allow list.' -RequestId $requestId -SourceTenantId $sourceTenantId -TargetTenantId $targetTenantId
    return
}
if ($sourceTenantId -and $sourceTenantId -notin $allowedTenants) {
    Write-ReconcileError -StatusCode 403 -Error 'TenantNotAllowed' -Message 'The supplied source tenant is not in the backend allow list.' -RequestId $requestId -SourceTenantId $sourceTenantId -TargetTenantId $targetTenantId
    return
}

$detected = New-Object System.Collections.Generic.List[object]
$lookupErrors = New-Object System.Collections.Generic.List[object]

foreach ($tenantId in $allowedTenants) {
    try {
        $lookup = Get-WindowsDeviceLinkTenantAssociation -TenantId $tenantId -SerialNumber $serialNumber -ClientId $clientId
        foreach ($match in @($lookup.Matches)) {
            $detected.Add([pscustomobject]@{
                TenantId = $tenantId
                AssociationId = [string]$match.id
                AssociationState = [string]$match.associationState
                SerialNumber = [string]$match.serialNumber
            })
        }
    }
    catch {
        $lookupErrors.Add([pscustomobject]@{
            TenantId = $tenantId
            Error = 'TenantLookupFailed'
        })
        Write-Warning "DeviceLink reconcile lookup failed. RequestId=$requestId TenantId=$tenantId"
    }
}

if ($lookupErrors.Count -gt 0) {
    Write-ReconcileError -StatusCode 503 -Error 'LookupIncomplete' -Message 'One or more configured tenants could not be searched. No state-changing action was performed.' -RequestId $requestId -SourceTenantId $sourceTenantId -TargetTenantId $targetTenantId
    return
}
if ($detected.Count -gt 1) {
    Write-ReconcileError -StatusCode 409 -Error 'AmbiguousState' -Message 'The serial number was found in more than one configured tenant. No state-changing action was performed.' -RequestId $requestId -SourceTenantId $sourceTenantId -TargetTenantId $targetTenantId
    return
}

$decision = $null
$current = if ($detected.Count -eq 1) { $detected[0] } else { $null }

if (-not $current) {
    if ($sourceTenantId) {
        Write-ReconcileError -StatusCode 409 -Error 'SourceStateMismatch' -Message 'A source tenant was supplied, but the device is not currently present in any configured tenant.' -RequestId $requestId -SourceTenantId $sourceTenantId -TargetTenantId $targetTenantId
        return
    }
    $decision = 'New'
}
elseif ($current.TenantId -eq $targetTenantId) {
    if ($sourceTenantId -and $sourceTenantId -ne $targetTenantId) {
        Write-ReconcileError -StatusCode 409 -Error 'SourceStateMismatch' -Message 'The supplied source tenant does not match the freshly detected tenant state.' -RequestId $requestId -SourceTenantId $sourceTenantId -TargetTenantId $targetTenantId
        return
    }
    $decision = 'Update'
}
else {
    if ([string]::IsNullOrWhiteSpace($sourceTenantId)) {
        Write-ReconcileError -StatusCode 409 -Error 'SourceTenantRequired' -Message 'The device exists in another tenant. sourceTenantId is required before a Move can be performed.' -RequestId $requestId -TargetTenantId $targetTenantId
        return
    }
    if ($sourceTenantId -ne $current.TenantId) {
        Write-ReconcileError -StatusCode 409 -Error 'SourceStateMismatch' -Message 'The supplied source tenant does not match the freshly detected tenant state.' -RequestId $requestId -SourceTenantId $sourceTenantId -TargetTenantId $targetTenantId
        return
    }
    $decision = 'Move'
}

if ($decision -eq 'Update') {
    Write-JsonResponse -StatusCode 200 -Body @{
        success = $true
        requestId = $requestId
        decision = 'Update'
        changed = $false
        sourceTenantId = $current.TenantId
        targetTenantId = $targetTenantId
        associationId = $current.AssociationId
        associationState = $current.AssociationState
        serialNumber = $serialNumber
    }
    return
}

if ($decision -eq 'New') {
    $targetLookup = Get-WindowsDeviceLinkTenantAssociation -TenantId $targetTenantId -SerialNumber $serialNumber -ClientId $clientId
    $targetToken = [string]$targetLookup.AccessToken
    $createError = $null
    try {
        $null = New-WindowsDeviceLinkBackendAssociation -DeviceLink $deviceLink -AccessToken $targetToken
    }
    catch {
        $createError = $_
    }
    finally {
        $targetToken = $null
    }

    $verify = Get-WindowsDeviceLinkTenantAssociation -TenantId $targetTenantId -SerialNumber $serialNumber -ClientId $clientId
    if ($createError -and @($verify.Matches).Count -eq 0) {
        Write-ReconcileError -StatusCode 502 -Error 'TargetCreateUncertain' -Message 'The target pre-association request failed and the target state could not be proven. Re-run lookup before retrying.' -RequestId $requestId -TargetTenantId $targetTenantId -Decision 'New'
        return
    }
    $matches = @($verify.Matches)
    if ($matches.Count -ne 1) {
        Write-ReconcileError -StatusCode 502 -Error 'TargetVerificationFailed' -Message 'The target association could not be verified after creation.' -RequestId $requestId -TargetTenantId $targetTenantId -Decision 'New'
        return
    }

    Write-JsonResponse -StatusCode 200 -Body @{
        success = $true
        requestId = $requestId
        decision = 'New'
        changed = $true
        targetTenantId = $targetTenantId
        associationId = [string]$matches[0].id
        associationState = [string]$matches[0].associationState
        serialNumber = $serialNumber
    }
    return
}

# Move
$sourceLookup = Get-WindowsDeviceLinkTenantAssociation -TenantId $sourceTenantId -SerialNumber $serialNumber -ClientId $clientId
$sourceMatches = @($sourceLookup.Matches)
if ($sourceMatches.Count -ne 1 -or [string]$sourceMatches[0].id -ne $current.AssociationId) {
    Write-ReconcileError -StatusCode 409 -Error 'SourceStateChanged' -Message 'The source association changed between decision and mutation. No deletion was performed.' -RequestId $requestId -SourceTenantId $sourceTenantId -TargetTenantId $targetTenantId -Decision 'Move'
    return
}

$sourceToken = [string]$sourceLookup.AccessToken
try {
    Remove-WindowsDeviceLinkBackendAssociation -AssociationId $current.AssociationId -AccessToken $sourceToken
}
catch {
    # A DELETE transport failure can be ambiguous. Verify state, but never issue a second DELETE automatically.
    $verifySourceAfterError = Get-WindowsDeviceLinkTenantAssociation -TenantId $sourceTenantId -SerialNumber $serialNumber -ClientId $clientId
    if (@($verifySourceAfterError.Matches).Count -ne 0) {
        Write-ReconcileError -StatusCode 502 -Error 'SourceRemovalUncertain' -Message 'Source removal failed or remains uncertain. No target registration was attempted.' -RequestId $requestId -SourceTenantId $sourceTenantId -TargetTenantId $targetTenantId -Decision 'Move'
        return
    }
}
finally {
    $sourceToken = $null
}

$verifySource = Get-WindowsDeviceLinkTenantAssociation -TenantId $sourceTenantId -SerialNumber $serialNumber -ClientId $clientId
if (@($verifySource.Matches).Count -ne 0) {
    Write-ReconcileError -StatusCode 502 -Error 'SourceVerificationFailed' -Message 'The source association is still present after removal. No target registration was attempted.' -RequestId $requestId -SourceTenantId $sourceTenantId -TargetTenantId $targetTenantId -Decision 'Move'
    return
}

$targetLookup = Get-WindowsDeviceLinkTenantAssociation -TenantId $targetTenantId -SerialNumber $serialNumber -ClientId $clientId
if (@($targetLookup.Matches).Count -gt 0) {
    Write-ReconcileError -StatusCode 409 -Error 'TargetStateChanged' -Message 'The target tenant now contains an association. The source was removed; verify final state before another mutation.' -RequestId $requestId -SourceTenantId $sourceTenantId -TargetTenantId $targetTenantId -Decision 'Move'
    return
}

$targetToken = [string]$targetLookup.AccessToken
$targetCreateError = $null
try {
    $null = New-WindowsDeviceLinkBackendAssociation -DeviceLink $deviceLink -AccessToken $targetToken
}
catch {
    $targetCreateError = $_
}
finally {
    $targetToken = $null
}

$verifyTarget = Get-WindowsDeviceLinkTenantAssociation -TenantId $targetTenantId -SerialNumber $serialNumber -ClientId $clientId
if ($targetCreateError -and @($verifyTarget.Matches).Count -eq 0) {
    Write-ReconcileError -StatusCode 502 -Error 'MoveIncomplete' -Message 'The source association was removed, but target creation failed and the target state could not be proven. Re-run lookup before retrying.' -RequestId $requestId -SourceTenantId $sourceTenantId -TargetTenantId $targetTenantId -Decision 'Move'
    return
}
$targetMatches = @($verifyTarget.Matches)
if ($targetMatches.Count -ne 1) {
    Write-ReconcileError -StatusCode 502 -Error 'MoveIncomplete' -Message 'The source association was removed, but the target association could not be verified. Re-run lookup before retrying.' -RequestId $requestId -SourceTenantId $sourceTenantId -TargetTenantId $targetTenantId -Decision 'Move'
    return
}

Write-JsonResponse -StatusCode 200 -Body @{
    success = $true
    requestId = $requestId
    decision = 'Move'
    changed = $true
    sourceTenantId = $sourceTenantId
    targetTenantId = $targetTenantId
    sourceAssociationId = $current.AssociationId
    targetAssociationId = [string]$targetMatches[0].id
    associationState = [string]$targetMatches[0].associationState
    serialNumber = $serialNumber
}
