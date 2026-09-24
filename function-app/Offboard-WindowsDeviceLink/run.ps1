using namespace System.Net

param($Request, $TriggerMetadata)

$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot '..\shared\BackendAuth.ps1')
. (Join-Path $PSScriptRoot '..\shared\AssociationOperations.ps1')

function Write-JsonResponse {
    param([Parameter(Mandatory)][int]$StatusCode,[Parameter(Mandatory)][hashtable]$Body)
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = $StatusCode
        Headers = @{ 'Content-Type' = 'application/json'; 'Cache-Control' = 'no-store' }
        Body = ($Body | ConvertTo-Json -Depth 8 -Compress)
    })
}

function Get-HeaderValue {
    param([Parameter(Mandatory)][object]$Headers,[Parameter(Mandatory)][string]$Name)
    foreach ($key in $Headers.Keys) {
        if ([string]$key -ieq $Name) { return [string]$Headers[$key] }
    }
    $null
}

function Write-OffboardError {
    param(
        [Parameter(Mandatory)][int]$StatusCode,
        [Parameter(Mandatory)][string]$Error,
        [Parameter(Mandatory)][string]$Message,
        [string]$RequestId,
        [string]$SourceTenantId,
        [string]$Stage,
        [System.Management.Automation.ErrorRecord]$UpstreamError
    )
    $response = @{ success=$false; requestId=$RequestId; error=$Error; message=$Message }
    if ($SourceTenantId) { $response.sourceTenantId = $SourceTenantId }
    if ($Stage) { $response.stage = $Stage }
    if ($UpstreamError) {
        $diagnostic = Get-WindowsDeviceLinkUpstreamFailure -ErrorRecord $UpstreamError
        $response.upstreamStatusCode = $diagnostic.statusCode
        $response.upstreamErrorCode = $diagnostic.upstreamErrorCode
        $response.aadstsCodes = $diagnostic.aadstsCodes
        $response.upstreamCorrelationId = $diagnostic.upstreamCorrelationId
        Write-Warning ("DeviceLink offboarding failed. RequestId={0} Stage={1} UpstreamStatusCode={2} UpstreamCode={3}" -f $RequestId,$Stage,$diagnostic.statusCode,$diagnostic.upstreamErrorCode)
    }
    Write-JsonResponse -StatusCode $StatusCode -Body $response
}

$requestId = Get-HeaderValue -Headers $Request.Headers -Name 'X-WindowsDeviceLink-RequestId'
$schemaHeader = Get-HeaderValue -Headers $Request.Headers -Name 'X-WindowsDeviceLink-Schema'
$providedApiKey = Get-HeaderValue -Headers $Request.Headers -Name 'X-WindowsDeviceLink-Key'
$expectedApiKey = [Environment]::GetEnvironmentVariable('WINDOWSDEVICELINK_API_KEY')

if ([string]::IsNullOrWhiteSpace($expectedApiKey)) {
    Write-OffboardError -StatusCode 500 -Error 'BackendConfigurationError' -Message 'The webhook API key is not configured.' -RequestId $requestId
    return
}
if ([string]::IsNullOrWhiteSpace($providedApiKey) -or -not (Test-WindowsDeviceLinkSharedSecret -Expected $expectedApiKey -Provided $providedApiKey)) {
    Write-OffboardError -StatusCode 401 -Error 'Unauthorized' -Message 'Webhook API key validation failed.' -RequestId $requestId
    return
}
if ($schemaHeader -ne '1') {
    Write-OffboardError -StatusCode 400 -Error 'UnsupportedSchema' -Message 'X-WindowsDeviceLink-Schema must be 1.' -RequestId $requestId
    return
}

try {
    $body = $Request.Body
    if ($body -is [string]) { $body = $body | ConvertFrom-Json -ErrorAction Stop }
    if (-not $body) { throw 'Request body is empty.' }
    if ([int]$body.schemaVersion -ne 1) { throw "Unsupported schemaVersion '$($body.schemaVersion)'." }
    if ([string]$body.requestType -ne 'DeviceLinkOffboard') { throw "Unsupported requestType '$($body.requestType)'." }
    if ([string]::IsNullOrWhiteSpace([string]$body.requestId)) { throw 'requestId is required.' }
    if ($requestId -and $requestId -ne [string]$body.requestId) { throw 'Request ID header and body do not match.' }
    $requestId = [string]$body.requestId
    if ([string]::IsNullOrWhiteSpace([string]$body.serialNumber)) { throw 'serialNumber is required.' }
}
catch {
    Write-OffboardError -StatusCode 400 -Error 'InvalidRequest' -Message $_.Exception.Message -RequestId $requestId
    return
}

$serialNumber = ([string]$body.serialNumber).Trim()
$sourceTenantId = ([string]$body.sourceTenantId).Trim().ToLowerInvariant()
$clientId = [Environment]::GetEnvironmentVariable('WINDOWSDEVICELINK_CLIENT_ID')
if ([string]::IsNullOrWhiteSpace($clientId)) {
    Write-OffboardError -StatusCode 500 -Error 'BackendConfigurationError' -Message 'WINDOWSDEVICELINK_CLIENT_ID is not configured.' -RequestId $requestId -SourceTenantId $sourceTenantId
    return
}

$allowedTenants = @(Get-WindowsDeviceLinkAllowedTenants)
if ($allowedTenants.Count -eq 0) {
    Write-OffboardError -StatusCode 500 -Error 'BackendConfigurationError' -Message 'No allowed tenants are configured. The backend fails closed.' -RequestId $requestId -SourceTenantId $sourceTenantId
    return
}
if ($sourceTenantId -and $sourceTenantId -notin $allowedTenants) {
    Write-OffboardError -StatusCode 403 -Error 'TenantNotAllowed' -Message 'The supplied source tenant is not in the backend allow list.' -RequestId $requestId -SourceTenantId $sourceTenantId
    return
}

$detected = New-Object System.Collections.Generic.List[object]
foreach ($tenantId in $allowedTenants) {
    try {
        $lookup = Get-WindowsDeviceLinkTenantAssociation -TenantId $tenantId -SerialNumber $serialNumber -ClientId $clientId
        foreach ($match in @($lookup.Matches)) {
            $detected.Add([pscustomobject]@{ TenantId=$tenantId; AssociationId=[string]$match.id; AssociationState=[string]$match.associationState })
        }
    }
    catch {
        Write-OffboardError -StatusCode 503 -Error 'LookupIncomplete' -Message 'One or more configured tenants could not be searched. No state-changing action was performed.' -RequestId $requestId -SourceTenantId $sourceTenantId -Stage 'GraphLookup' -UpstreamError $_
        return
    }
}

if ($detected.Count -gt 1) {
    Write-OffboardError -StatusCode 409 -Error 'AmbiguousState' -Message 'The serial number was found in more than one configured tenant. No state-changing action was performed.' -RequestId $requestId -SourceTenantId $sourceTenantId
    return
}
if ($detected.Count -eq 0) {
    Write-JsonResponse -StatusCode 200 -Body @{ success=$true; requestId=$requestId; decision='None'; changed=$false; serialNumber=$serialNumber }
    return
}

$current = $detected[0]
if ($sourceTenantId -and $sourceTenantId -ne $current.TenantId) {
    Write-OffboardError -StatusCode 409 -Error 'SourceStateMismatch' -Message 'The supplied source tenant does not match the freshly detected tenant state.' -RequestId $requestId -SourceTenantId $sourceTenantId
    return
}

$verified = Get-WindowsDeviceLinkTenantAssociation -TenantId $current.TenantId -SerialNumber $serialNumber -ClientId $clientId
$matches = @($verified.Matches)
if ($matches.Count -ne 1 -or [string]$matches[0].id -ne $current.AssociationId) {
    Write-OffboardError -StatusCode 409 -Error 'SourceStateChanged' -Message 'The cloud association changed between lookup and removal. No deletion was performed.' -RequestId $requestId -SourceTenantId $current.TenantId
    return
}

$token = [string]$verified.AccessToken
try {
    Remove-WindowsDeviceLinkBackendAssociation -AssociationId $current.AssociationId -AccessToken $token
}
catch {
    $verifyAfterError = Get-WindowsDeviceLinkTenantAssociation -TenantId $current.TenantId -SerialNumber $serialNumber -ClientId $clientId
    if (@($verifyAfterError.Matches).Count -ne 0) {
        Write-OffboardError -StatusCode 502 -Error 'RemovalUncertain' -Message 'Cloud removal failed or remains uncertain. Verify cloud state before retrying.' -RequestId $requestId -SourceTenantId $current.TenantId -Stage 'GraphDelete' -UpstreamError $_
        return
    }
}
finally { $token = $null }

try {
    $verifyAbsent = Get-WindowsDeviceLinkTenantAssociation -TenantId $current.TenantId -SerialNumber $serialNumber -ClientId $clientId
}
catch {
    Write-OffboardError -StatusCode 502 -Error 'RemovalVerificationFailed' -Message 'Cloud removal was attempted, but the resulting state could not be verified.' -RequestId $requestId -SourceTenantId $current.TenantId -Stage 'GraphVerify' -UpstreamError $_
    return
}
if (@($verifyAbsent.Matches).Count -ne 0) {
    Write-OffboardError -StatusCode 502 -Error 'RemovalVerificationFailed' -Message 'The cloud association is still present after removal.' -RequestId $requestId -SourceTenantId $current.TenantId
    return
}

Write-JsonResponse -StatusCode 200 -Body @{
    success=$true
    requestId=$requestId
    decision='Remove'
    changed=$true
    sourceTenantId=$current.TenantId
    associationId=$current.AssociationId
    associationState=$current.AssociationState
    serialNumber=$serialNumber
}
