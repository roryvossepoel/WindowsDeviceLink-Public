<#
Validates the Function-backed Initialize-WindowsDeviceLink contract without hardware or network access.
#>
[CmdletBinding()]
param([string]$ModulePath)

$ErrorActionPreference = 'Stop'
function Assert-True { param([bool]$Condition,[string]$Message) if(-not $Condition){ throw "FAIL: $Message" } }

if (-not $ModulePath) {
    $ModulePath = Join-Path $PSScriptRoot '..\src\WindowsDeviceLink\WindowsDeviceLink.psd1'
}

Remove-Module WindowsDeviceLink -Force -ErrorAction SilentlyContinue
Import-Module (Resolve-Path -LiteralPath $ModulePath).Path -Force -ErrorAction Stop
$command = Get-Command Initialize-WindowsDeviceLink -Module WindowsDeviceLink -ErrorAction Stop
$source = $command.ScriptBlock.ToString()

foreach ($name in @('BackendUri','BackendApiKey','TargetTenantId','Associate')) {
    Assert-True ($command.Parameters.ContainsKey($name)) "Initialize-WindowsDeviceLink is missing -$name."
}

Assert-True ($command.Parameters['BackendUri'].ParameterType -eq [uri]) '-BackendUri must remain a URI.'
Assert-True ($command.Parameters['TargetTenantId'].ParameterType -eq [guid]) '-TargetTenantId must remain a GUID.'

$methodSets = @($command.Parameters['Method'].ParameterSets.Keys)
$backendUriSets = @($command.Parameters['BackendUri'].ParameterSets.Keys)
Assert-True ('Direct' -in $methodSets) '-Method must belong to the Direct parameter set.'
Assert-True ('Backend' -notin $methodSets) '-Method must not be accepted in the Backend parameter set.'
Assert-True ('Backend' -in $backendUriSets) '-BackendUri must belong to the Backend parameter set.'

foreach ($required in @(
    'Get-WindowsDeviceLinkBackendStatus',
    'Resolve-WindowsDeviceLinkBackendEndpoint',
    'Invoke-WindowsDeviceLinkWebhook',
    'AssociationInDifferentTenant',
    'explicit tenant-move workflow',
    'Complete-WindowsDeviceLinkAssociation',
    'Function-backed cloud state was verified as Associated'
)) {
    Assert-True ($source -match [regex]::Escape($required)) "Function-backed initializer contract is missing '$required'."
}

Assert-True ($source -notmatch "(?s)AssociationInDifferentTenant.*Remove-WindowsDeviceLinkAssociation") 'Initializer must not remove an existing association when the target tenant differs.'

$module = Get-Module WindowsDeviceLink -ErrorAction Stop
$resolved = & $module { Resolve-WindowsDeviceLinkBackendEndpoint -BackendUri 'https://wdl.example.com/api/devicelink' -Route lookup }
Assert-True ([string]$resolved -eq 'https://wdl.example.com/api/devicelink/lookup') 'Backend endpoint resolver returned an unexpected lookup URI.'

$invalidHttpBlocked = $false
try {
    & $module { Resolve-WindowsDeviceLinkBackendEndpoint -BackendUri 'http://wdl.example.com/api/devicelink' -Route lookup } | Out-Null
} catch { $invalidHttpBlocked = $true }
Assert-True $invalidHttpBlocked 'Backend endpoint resolver must reject non-HTTPS URIs.'

$invalidBaseBlocked = $false
try {
    & $module { Resolve-WindowsDeviceLinkBackendEndpoint -BackendUri 'https://wdl.example.com/api' -Route lookup } | Out-Null
} catch { $invalidBaseBlocked = $true }
Assert-True $invalidBaseBlocked "Backend endpoint resolver must require the '/api/devicelink' base path."

Write-Host 'PASS: Function-backed initializer parameter sets, safety boundary and endpoint resolution are valid.'