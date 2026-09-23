using namespace System.Net
using namespace System.Text

param($Request, $TriggerMetadata)

$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'BackendAuth.ps1')

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

function Get-ExactSerialMatches {
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Records,
        [Parameter(Mandatory)][string]$SerialNumber
    )

    @(
        $Records | Where-Object {
            -not [string]::IsNullOrWhiteSpace([string]$_.serialNumber) -and
            ([string]$_.serialNumber).Trim() -ieq $SerialNumber.Trim()
        }
    )
}

function ConvertTo-LookupMatch {
    param(
        [Parameter(Mandatory)][object]$Record,
        [Parameter(Mandatory)][string]$TenantId,
        [string]$TenantName
    )

    [ordered]@{
        tenantId = $TenantId
        tenantName = $TenantName
        associationId = [string]$Record.id
        associationState = [string]$Record.associationState
        serialNumber = [string]$Record.serialNumber
        manufacturer = [string]$Record.manufacturerName
        model = [string]$Record.modelName
        managedDeviceId = [string]$Record.managedDeviceId
        preassociationDateTime = $Record.preassociationDateTime
        deploymentProfileId = [string]$Record.deploymentProfileId
    }
}

$requestId = [guid]::NewGuid().ToString()
$providedApiKey = Get-HeaderValue -Headers $Request.Headers -Name 'X-WindowsDeviceLink-Key'
$expectedApiKey = [Environment]::GetEnvironmentVariable('WINDOWSDEVICELINK_API_KEY')

if ([string]::IsNullOrWhiteSpace($expectedApiKey)) {
    Write-JsonResponse -StatusCode 500 -Body @{
        success = $false
        requestId = $requestId
        error = 'BackendConfigurationError'
        message = 'The lookup API key is not configured on the Function App.'
    }
    return
}

if ([string]::IsNullOrWhiteSpace($providedApiKey) -or -not (Test-WindowsDeviceLinkSharedSecret -Expected $expectedApiKey -Provided $providedApiKey)) {
    Write-JsonResponse -StatusCode 401 -Body @{
        success = $false
        requestId = $requestId
        error = 'Unauthorized'
        message = 'API key validation failed.'
    }
    return
}

$serialNumber = [string]$Request.Query.serialNumber
if ([string]::IsNullOrWhiteSpace($serialNumber)) {
    Write-JsonResponse -StatusCode 400 -Body @{
        success = $false
        requestId = $requestId
        error = 'SerialNumberRequired'
        message = 'Query parameter serialNumber is required.'
    }
    return
}
$serialNumber = $serialNumber.Trim()

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

try {
    $allowedTenants = @(Get-WindowsDeviceLinkAllowedTenants)
    $tenantNames = Get-WindowsDeviceLinkTenantNames
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
        message = 'No allowed tenants are configured. The backend fails closed.'
    }
    return
}

$requestedTenant = [string]$Request.Query.tenantId
if (-not [string]::IsNullOrWhiteSpace($requestedTenant)) {
    $requestedTenant = $requestedTenant.Trim().ToLowerInvariant()
    if ($requestedTenant -notin $allowedTenants) {
        Write-JsonResponse -StatusCode 403 -Body @{
            success = $false
            requestId = $requestId
            error = 'TenantNotAllowed'
            message = 'The requested tenant is not in the backend allow list.'
        }
        return
    }
    $tenantsToSearch = @($requestedTenant)
}
else {
    $tenantsToSearch = @($allowedTenants)
}

$matches = New-Object System.Collections.Generic.List[object]
$tenantErrors = New-Object System.Collections.Generic.List[object]
$searchedTenants = New-Object System.Collections.Generic.List[object]

foreach ($tenantId in $tenantsToSearch) {
    $tenantName = if ($tenantNames.ContainsKey($tenantId)) { [string]$tenantNames[$tenantId] } else { $null }
    $token = $null
    $stage = 'GraphToken'

    try {
        $token = Get-WindowsDeviceLinkBackendGraphToken -TenantId $tenantId -ClientId $clientId
        if ([string]::IsNullOrWhiteSpace($token)) {
            throw 'Microsoft identity platform returned no access token.'
        }

        $stage = 'GraphLookup'
        $escapedSerial = $serialNumber.Replace("'","''")
        $filter = [uri]::EscapeDataString("serialNumber eq '$escapedSerial'")
        $filteredUri = "https://graph.microsoft.com/beta/deviceManagement/tenantAssociatedDevices?%24filter=$filter"

        $filtered = @(
            Invoke-WindowsDeviceLinkGraphCollection -Uri $filteredUri -AccessToken $token
        )
        $records = @(Get-ExactSerialMatches -Records $filtered -SerialNumber $serialNumber)
        $lookupMode = 'ServerFilter'

        if ($records.Count -eq 0) {
            $stage = 'GraphLookupFallback'
            $allUri = 'https://graph.microsoft.com/beta/deviceManagement/tenantAssociatedDevices'
            $all = @(
                Invoke-WindowsDeviceLinkGraphCollection -Uri $allUri -AccessToken $token
            )
            $records = @(Get-ExactSerialMatches -Records $all -SerialNumber $serialNumber)
            $lookupMode = 'ClientFallback'
        }

        foreach ($record in $records) {
            $matches.Add((ConvertTo-LookupMatch -Record $record -TenantId $tenantId -TenantName $tenantName))
        }

        $searchedTenants.Add([ordered]@{
            tenantId = $tenantId
            tenantName = $tenantName
            success = $true
            lookupMode = $lookupMode
            matchCount = $records.Count
        })
    }
    catch {
        $diagnostic = Get-WindowsDeviceLinkUpstreamFailure -ErrorRecord $_

        $tenantErrors.Add([ordered]@{
            tenantId = $tenantId
            tenantName = $tenantName
            statusCode = $diagnostic.statusCode
            error = 'TenantLookupFailed'
            stage = $stage
            upstreamErrorCode = $diagnostic.upstreamErrorCode
            aadstsCodes = $diagnostic.aadstsCodes
            upstreamCorrelationId = $diagnostic.upstreamCorrelationId
        })

        $searchedTenants.Add([ordered]@{
            tenantId = $tenantId
            tenantName = $tenantName
            success = $false
            lookupMode = $null
            matchCount = 0
        })

        Write-Warning ("DeviceLink lookup failed for TenantId={0} RequestId={1} Stage={2} StatusCode={3} UpstreamCode={4} AadstsCodes={5} UpstreamCorrelationId={6}" -f $tenantId,$requestId,$stage,$diagnostic.statusCode,$diagnostic.upstreamErrorCode,($diagnostic.aadstsCodes -join ','),$diagnostic.upstreamCorrelationId)
    }
    finally {
        $token = $null
    }
}

Write-Information "DeviceLink multitenant lookup completed. RequestId=$requestId SerialNumber=$serialNumber Tenants=$($tenantsToSearch.Count) Matches=$($matches.Count) Errors=$($tenantErrors.Count)"

Write-JsonResponse -StatusCode 200 -Body @{
    success = $true
    requestId = $requestId
    serialNumber = $serialNumber
    searchedTenantCount = $tenantsToSearch.Count
    successfulTenantCount = $searchedTenants.Count - $tenantErrors.Count
    failedTenantCount = $tenantErrors.Count
    matchCount = $matches.Count
    matches = $matches.ToArray()
    tenants = $searchedTenants.ToArray()
    tenantErrors = $tenantErrors.ToArray()
}
