using namespace System.Net

param($Request, $TriggerMetadata)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'BackendAuth.ps1')

function Get-HeaderValue {
    param([Parameter(Mandatory)][object]$Headers,[Parameter(Mandatory)][string]$Name)
    foreach ($key in $Headers.Keys) {
        if ([string]$key -ieq $Name) { return [string]$Headers[$key] }
    }
    $null
}

function Write-JsonResponse {
    param([Parameter(Mandatory)][int]$StatusCode,[Parameter(Mandatory)][hashtable]$Body)
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = $StatusCode
        Headers = @{ 'Content-Type' = 'application/json'; 'Cache-Control' = 'no-store' }
        Body = ($Body | ConvertTo-Json -Depth 6 -Compress)
    })
}

$requestId = [guid]::NewGuid().ToString()
$provided = Get-HeaderValue -Headers $Request.Headers -Name 'X-WindowsDeviceLink-Key'
$expected = [Environment]::GetEnvironmentVariable('WINDOWSDEVICELINK_API_KEY')

if ([string]::IsNullOrWhiteSpace($expected)) {
    Write-JsonResponse -StatusCode 500 -Body @{ success=$false; requestId=$requestId; error='BackendConfigurationError'; message='The API key is not configured.' }
    return
}
if ([string]::IsNullOrWhiteSpace($provided) -or -not (Test-WindowsDeviceLinkSharedSecret -Expected $expected -Provided $provided)) {
    Write-JsonResponse -StatusCode 401 -Body @{ success=$false; requestId=$requestId; error='Unauthorized'; message='API key validation failed.' }
    return
}

try {
    $allowed = @(Get-WindowsDeviceLinkAllowedTenants)
    if ($allowed.Count -eq 0) { throw 'No allowed tenants are configured.' }
    $names = Get-WindowsDeviceLinkTenantNames
    $tenants = @(
        foreach ($tenantId in $allowed) {
            $name = if ($names.ContainsKey($tenantId)) { [string]$names[$tenantId] } else { $tenantId }
            [ordered]@{ tenantId=$tenantId; name=$name }
        }
    )
    $metadata = Get-WindowsDeviceLinkBackendMetadata
    Write-JsonResponse -StatusCode 200 -Body @{
        success=$true
        requestId=$requestId
        apiVersion=$metadata.apiVersion
        minimumModuleVersion=$metadata.minimumModuleVersion
        capabilities=$metadata.capabilities
        tenantCount=$tenants.Count
        tenants=$tenants
    }
}
catch {
    Write-JsonResponse -StatusCode 500 -Body @{ success=$false; requestId=$requestId; error='BackendConfigurationError'; message='The tenant catalog could not be loaded.' }
}
