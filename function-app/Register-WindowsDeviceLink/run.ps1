using namespace System.Net

param($Request, $TriggerMetadata)

$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot '..\shared\BackendAuth.ps1')
. (Join-Path $PSScriptRoot '..\shared\AssociationOperations.ps1')

function Write-JsonResponse {
    param(
        [Parameter(Mandatory)][int]$StatusCode,
        [Parameter(Mandatory)][hashtable]$Body
    )

    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = $StatusCode
        Headers = @{ 'Content-Type' = 'application/json' }
        Body = ($Body | ConvertTo-Json -Depth 8 -Compress)
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

$requestId = Get-HeaderValue -Headers $Request.Headers -Name 'X-WindowsDeviceLink-RequestId'
$schemaHeader = Get-HeaderValue -Headers $Request.Headers -Name 'X-WindowsDeviceLink-Schema'
$providedApiKey = Get-HeaderValue -Headers $Request.Headers -Name 'X-WindowsDeviceLink-Key'
$expectedApiKey = [Environment]::GetEnvironmentVariable('WINDOWSDEVICELINK_API_KEY')

if ([string]::IsNullOrWhiteSpace($expectedApiKey)) {
    Write-JsonResponse -StatusCode 500 -Body @{
        success = $false
        requestId = $requestId
        error = 'BackendConfigurationError'
        message = 'The webhook API key is not configured on the Function App.'
    }
    return
}

if ([string]::IsNullOrWhiteSpace($providedApiKey) -or -not (Test-WindowsDeviceLinkSharedSecret -Expected $expectedApiKey -Provided $providedApiKey)) {
    Write-JsonResponse -StatusCode 401 -Body @{
        success = $false
        requestId = $requestId
        error = 'Unauthorized'
        message = 'Webhook API key validation failed.'
    }
    return
}

if ($schemaHeader -ne '1') {
    Write-JsonResponse -StatusCode 400 -Body @{
        success = $false
        requestId = $requestId
        error = 'UnsupportedSchema'
        message = 'X-WindowsDeviceLink-Schema must be 1.'
    }
    return
}

try {
    $body = $Request.Body
    if ($body -is [string]) { $body = $body | ConvertFrom-Json -ErrorAction Stop }

    if (-not $body) { throw 'Request body is empty.' }
    if ([int]$body.schemaVersion -ne 1) { throw "Unsupported schemaVersion '$($body.schemaVersion)'." }
    if ([string]$body.requestType -ne 'DeviceLinkPreassociation') { throw "Unsupported requestType '$($body.requestType)'." }
    if ([string]::IsNullOrWhiteSpace([string]$body.requestId)) { throw 'requestId is required.' }
    if ($requestId -and $requestId -ne [string]$body.requestId) { throw 'Request ID header and body do not match.' }
    $requestId = [string]$body.requestId

    if (-not $body.device) { throw 'device is required.' }
    if ([string]::IsNullOrWhiteSpace([string]$body.device.serialNumber)) { throw 'device.serialNumber is required.' }
    if ([string]::IsNullOrWhiteSpace([string]$body.device.deviceLink)) { throw 'device.deviceLink is required.' }
}
catch {
    Write-JsonResponse -StatusCode 400 -Body @{
        success = $false
        requestId = $requestId
        error = 'InvalidRequest'
        message = $_.Exception.Message
    }
    return
}

$tenantId = ([string]$body.tenantId).Trim().ToLowerInvariant()
if ([string]::IsNullOrWhiteSpace($tenantId)) {
    $tenantId = ([string][Environment]::GetEnvironmentVariable('WINDOWSDEVICELINK_DEFAULT_TENANT_ID')).Trim().ToLowerInvariant()
}
if ([string]::IsNullOrWhiteSpace($tenantId)) {
    Write-JsonResponse -StatusCode 400 -Body @{
        success = $false
        requestId = $requestId
        error = 'TenantRequired'
        message = 'No tenantId was supplied and no default tenant is configured.'
    }
    return
}

try {
    $allowedTenants = @(Get-WindowsDeviceLinkAllowedTenants)
}
catch {
    Write-JsonResponse -StatusCode 500 -Body @{
        success = $false
        requestId = $requestId
        error = 'BackendConfigurationError'
        message = $_.Exception.Message
    }
    return
}

if ($allowedTenants.Count -eq 0) {
    Write-JsonResponse -StatusCode 500 -Body @{
        success = $false
        requestId = $requestId
        error = 'BackendConfigurationError'
        message = 'No allowed tenant list is configured. The backend fails closed.'
    }
    return
}

if ($tenantId -notin $allowedTenants) {
    Write-JsonResponse -StatusCode 403 -Body @{
        success = $false
        requestId = $requestId
        tenantId = $tenantId
        error = 'TenantNotAllowed'
        message = 'The requested tenant is not in the backend allow list.'
    }
    return
}

$clientId = [Environment]::GetEnvironmentVariable('WINDOWSDEVICELINK_CLIENT_ID')
if ([string]::IsNullOrWhiteSpace($clientId)) {
    Write-JsonResponse -StatusCode 500 -Body @{
        success = $false
        requestId = $requestId
        error = 'BackendConfigurationError'
        message = 'WINDOWSDEVICELINK_CLIENT_ID is not configured.'
    }
    return
}

$serialNumber = ([string]$body.device.serialNumber).Trim()
$deviceLink = [string]$body.device.deviceLink

try {
    $before = Get-WindowsDeviceLinkTenantAssociation -TenantId $tenantId -SerialNumber $serialNumber -ClientId $clientId
}
catch {
    Write-Warning "DeviceLink pre-association lookup failed. RequestId=$requestId TenantId=$tenantId ErrorType=$($_.Exception.GetType().Name)"
    Write-JsonResponse -StatusCode 502 -Body @{
        success = $false
        requestId = $requestId
        tenantId = $tenantId
        error = 'LookupFailed'
        message = 'The backend could not verify current Device Association state before pre-association.'
    }
    return
}

$beforeMatches = @($before.Matches)
if ($beforeMatches.Count -gt 0) {
    Write-JsonResponse -StatusCode 409 -Body @{
        success = $false
        requestId = $requestId
        tenantId = $tenantId
        serialNumber = $serialNumber
        error = 'AssociationConflict'
        message = 'A DeviceLink association already exists for this serial number in the requested tenant.'
    }
    return
}

$createError = $null
$token = [string]$before.AccessToken
try {
    $null = New-WindowsDeviceLinkBackendAssociation -DeviceLink $deviceLink -AccessToken $token
}
catch {
    $createError = $_
}
finally {
    $token = $null
}

try {
    $verify = Get-WindowsDeviceLinkTenantAssociation -TenantId $tenantId -SerialNumber $serialNumber -ClientId $clientId
}
catch {
    Write-Warning "DeviceLink post-create verification failed. RequestId=$requestId TenantId=$tenantId ErrorType=$($_.Exception.GetType().Name)"
    Write-JsonResponse -StatusCode 502 -Body @{
        success = $false
        requestId = $requestId
        tenantId = $tenantId
        error = 'VerificationFailed'
        message = 'The pre-association request was sent, but the resulting tenant state could not be verified. Re-run lookup before retrying.'
    }
    return
}

$matches = @($verify.Matches)
if ($createError -and $matches.Count -eq 0) {
    $diagnostic = Get-WindowsDeviceLinkUpstreamFailure -ErrorRecord $createError
    Write-Warning ("DeviceLink pre-association failed. RequestId={0} TenantId={1} Stage=GraphImportTarget UpstreamStatusCode={2} UpstreamCode={3} AadstsCodes={4} UpstreamCorrelationId={5}" -f $requestId,$tenantId,$diagnostic.statusCode,$diagnostic.upstreamErrorCode,($diagnostic.aadstsCodes -join ','),$diagnostic.upstreamCorrelationId)
    Write-JsonResponse -StatusCode 502 -Body @{
        success = $false
        requestId = $requestId
        tenantId = $tenantId
        error = 'CreateUncertain'
        stage = 'GraphImportTarget'
        upstreamStatusCode = $diagnostic.statusCode
        upstreamErrorCode = $diagnostic.upstreamErrorCode
        aadstsCodes = $diagnostic.aadstsCodes
        upstreamCorrelationId = $diagnostic.upstreamCorrelationId
        message = 'The pre-association request failed and no resulting association could be verified. Re-run lookup before retrying.'
    }
    return
}

if ($matches.Count -ne 1) {
    Write-JsonResponse -StatusCode 502 -Body @{
        success = $false
        requestId = $requestId
        tenantId = $tenantId
        error = 'VerificationFailed'
        message = 'The target association could not be verified as exactly one record after pre-association.'
    }
    return
}

$association = $matches[0]
Write-Information "DeviceLink pre-association succeeded and was verified. RequestId=$requestId TenantId=$tenantId AssociationId=$($association.id) State=$($association.associationState)"

Write-JsonResponse -StatusCode 200 -Body @{
    success = $true
    requestId = $requestId
    tenantId = $tenantId
    associationId = [string]$association.id
    associationState = [string]$association.associationState
    serialNumber = [string]$association.serialNumber
    manufacturer = [string]$association.manufacturerName
    model = [string]$association.modelName
    preassociationDateTime = $association.preassociationDateTime
}
