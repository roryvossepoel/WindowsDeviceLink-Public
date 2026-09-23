[CmdletBinding()]
param([string]$ModulePath = (Join-Path $PSScriptRoot '..\src\WindowsDeviceLink\WindowsDeviceLink.psd1'))

$ErrorActionPreference = 'Stop'
function Assert-True([bool]$Condition,[string]$Message) { if (-not $Condition) { throw "FAIL: $Message" } }

Remove-Module WindowsDeviceLink -Force -ErrorAction SilentlyContinue
Import-Module (Resolve-Path $ModulePath) -Force

$tenantA = '11111111-1111-1111-1111-111111111111'
$tenantB = '22222222-2222-2222-2222-222222222222'
$map = @{ 'Tenant B'=$tenantB; 'Tenant A'=$tenantA }

$all = @(Get-WindowsDeviceLinkTenantCatalog -TenantMap $map)
Assert-True ($all.Count -eq 2 -and $all[0].Name -eq 'Tenant A' -and $all[1].TenantId -eq $tenantB) 'Hashtable catalog was not normalized and sorted.'

$selected = Get-WindowsDeviceLinkTenantCatalog -TenantMap $map -Name 'tenant b'
Assert-True ($selected.TenantId -eq $tenantB) 'Case-insensitive name selection failed.'

$selectedById = Get-WindowsDeviceLinkTenantCatalog -TenantMap $map -TenantId $tenantA
Assert-True ($selectedById.Name -eq 'Tenant A') 'Tenant ID selection failed.'

$tempPath = Join-Path ([IO.Path]::GetTempPath()) ('wdl-tenants-' + [guid]::NewGuid().ToString() + '.json')
try {
    '{"Tenant A":"11111111-1111-1111-1111-111111111111","Tenant B":"22222222-2222-2222-2222-222222222222"}' | Set-Content -LiteralPath $tempPath -Encoding UTF8
    $fromFile = @(Get-WindowsDeviceLinkTenantCatalog -Path $tempPath)
    Assert-True ($fromFile.Count -eq 2) 'Local JSON catalog did not load.'
}
finally { Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue }

$blocked = $false
try { $null = Get-WindowsDeviceLinkTenantCatalog -TenantMap @{ A=$tenantA; Alias=$tenantA } } catch { $blocked=$true }
Assert-True $blocked 'Duplicate tenant IDs must fail closed.'

$blocked = $false
try { $null = Get-WindowsDeviceLinkTenantCatalog -TenantMap $map -Name 'Missing' } catch { $blocked=$true }
Assert-True $blocked 'A missing selected name must fail closed.'

$command = Get-Command Get-WindowsDeviceLinkTenantCatalog -Module WindowsDeviceLink
Assert-True (-not $command.Parameters.ContainsKey('WhatIf')) 'Tenant catalog reading must remain read-only.'
Write-Host 'PASS: backend-independent tenant catalog supports hashtable, local JSON, name/ID selection, and fail-closed validation.'

$backendResponse = [pscustomobject]@{
    success=$true; apiVersion='1.0'; minimumModuleVersion='0.10.0'
    capabilities=@('TenantCatalog','MultitenantLookup','Reconcile'); tenantCount=2
    tenants=@(
        [pscustomobject]@{name='Tenant A';tenantId=$tenantA},
        [pscustomobject]@{name='Tenant B';tenantId=$tenantB}
    )
}
$catalog = & (Get-Module WindowsDeviceLink) {
    param($response)
    Invoke-WindowsDeviceLinkBackendTenantCatalog -BackendUri 'https://example.test/api/devicelink' -BackendApiKey 'safe-test-key' -RequestScript { param($endpoint,$headers) $response }
} $backendResponse
Assert-True ($catalog.apiVersion -eq '1.0') 'Compatible backend handshake was rejected.'

$blocked=$false
$backendResponse.capabilities=@('TenantCatalog','MultitenantLookup')
try {
    $null = & (Get-Module WindowsDeviceLink) {
        param($response)
        Invoke-WindowsDeviceLinkBackendTenantCatalog -BackendUri 'https://example.test/api/devicelink' -BackendApiKey 'safe-test-key' -RequestScript { param($endpoint,$headers) $response }
    } $backendResponse
} catch { $blocked=$true }
Assert-True $blocked 'A backend missing Reconcile capability must fail closed.'

$blocked=$false
$backendResponse.capabilities=@('TenantCatalog','MultitenantLookup','Reconcile')
$backendResponse.apiVersion='2.0'
try {
    $null = & (Get-Module WindowsDeviceLink) {
        param($response)
        Invoke-WindowsDeviceLinkBackendTenantCatalog -BackendUri 'https://example.test/api/devicelink' -BackendApiKey 'safe-test-key' -RequestScript { param($endpoint,$headers) $response }
    } $backendResponse
} catch { $blocked=$true }
Assert-True $blocked 'An incompatible backend API version must fail closed.'
Write-Host 'PASS: backend compatibility handshake accepts v1 and rejects missing capabilities or incompatible versions.'
