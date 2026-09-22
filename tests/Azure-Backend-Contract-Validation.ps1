[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

function Assert-True {
    param(
        [Parameter(Mandatory)][bool]$Condition,
        [Parameter(Mandatory)][string]$Message
    )
    if (-not $Condition) { throw "FAIL: $Message" }
}

$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$functionRoot = Join-Path $root 'function-app'
$runPath = Join-Path $functionRoot 'Register-WindowsDeviceLink\run.ps1'
$functionJsonPath = Join-Path $functionRoot 'Register-WindowsDeviceLink\function.json'
$lookupRunPath = Join-Path $functionRoot 'Lookup-WindowsDeviceLink\run.ps1'
$lookupFunctionJsonPath = Join-Path $functionRoot 'Lookup-WindowsDeviceLink\function.json'
$reconcileRunPath = Join-Path $functionRoot 'Reconcile-WindowsDeviceLink\run.ps1'
$reconcileFunctionJsonPath = Join-Path $functionRoot 'Reconcile-WindowsDeviceLink\function.json'
$associationOperationsPath = Join-Path $functionRoot 'shared\AssociationOperations.ps1'
$sharedBackendPath = Join-Path $functionRoot 'shared\BackendAuth.ps1'
$hostPath = Join-Path $functionRoot 'host.json'
$bicepPath = Join-Path $root 'infrastructure\function-app\main.bicep'
$armPath = Join-Path $root 'infrastructure\function-app\azuredeploy.json'

foreach ($path in @(
    $runPath,$functionJsonPath,
    $lookupRunPath,$lookupFunctionJsonPath,
    $reconcileRunPath,$reconcileFunctionJsonPath,
    $associationOperationsPath,$sharedBackendPath,
    $hostPath,$bicepPath,$armPath
)) {
    Assert-True (Test-Path -LiteralPath $path -PathType Leaf) "Required Azure Function backend file is missing: $path"
}

foreach ($scriptPath in @($runPath,$lookupRunPath,$reconcileRunPath,$associationOperationsPath,$sharedBackendPath)) {
    $tokens = $null
    $errors = $null
    [void][Management.Automation.Language.Parser]::ParseFile($scriptPath,[ref]$tokens,[ref]$errors)
    Assert-True ($errors.Count -eq 0) ("PowerShell parse errors in '$scriptPath': " + (($errors | ForEach-Object Message) -join '; '))
}

$functionJson = Get-Content -LiteralPath $functionJsonPath -Raw | ConvertFrom-Json
$trigger = @($functionJson.bindings | Where-Object type -eq 'httpTrigger')
Assert-True ($trigger.Count -eq 1) 'Preassociate Function must expose exactly one HTTP trigger.'
Assert-True ([string]$trigger[0].route -eq 'devicelink/preassociate') 'Unexpected preassociate Function route.'
Assert-True ([string]$trigger[0].authLevel -eq 'anonymous') 'Function uses custom X-WindowsDeviceLink-Key validation and must keep the declared authLevel consistent.'

$lookupFunctionJson = Get-Content -LiteralPath $lookupFunctionJsonPath -Raw | ConvertFrom-Json
$lookupTrigger = @($lookupFunctionJson.bindings | Where-Object type -eq 'httpTrigger')
Assert-True ($lookupTrigger.Count -eq 1) 'Lookup Function must expose exactly one HTTP trigger.'
Assert-True ([string]$lookupTrigger[0].route -eq 'devicelink/lookup') 'Unexpected lookup Function route.'
Assert-True ('get' -in @($lookupTrigger[0].methods)) 'Lookup Function must allow GET.'

$reconcileFunctionJson = Get-Content -LiteralPath $reconcileFunctionJsonPath -Raw | ConvertFrom-Json
$reconcileTrigger = @($reconcileFunctionJson.bindings | Where-Object type -eq 'httpTrigger')
Assert-True ($reconcileTrigger.Count -eq 1) 'Reconcile Function must expose exactly one HTTP trigger.'
Assert-True ([string]$reconcileTrigger[0].route -eq 'devicelink/reconcile') 'Unexpected reconcile Function route.'
Assert-True ('post' -in @($reconcileTrigger[0].methods)) 'Reconcile Function must allow POST.'
Assert-True ('delete' -notin @($reconcileTrigger[0].methods)) 'Reconcile Function must not expose DELETE.'

$run = Get-Content -LiteralPath $runPath -Raw
foreach ($needle in @(
    'X-WindowsDeviceLink-Key',
    'X-WindowsDeviceLink-Schema',
    'X-WindowsDeviceLink-RequestId',
    'WINDOWSDEVICELINK_ALLOWED_TENANTS',
    'WINDOWSDEVICELINK_CLIENT_ID',
    'https://graph.microsoft.com/.default',
    'importTenantAssociatedDevice',
    'FixedTimeEquals',
    'AssociationConflict'
)) {
    Assert-True ($run.IndexOf($needle,[StringComparison]::OrdinalIgnoreCase) -ge 0) "Function receiver is missing expected contract text '$needle'."
}
Assert-True ($run.IndexOf('Write-Information $body',[StringComparison]::OrdinalIgnoreCase) -lt 0) 'Function must not log the request body.'
Assert-True ($run.IndexOf('Write-Host $body',[StringComparison]::OrdinalIgnoreCase) -lt 0) 'Function must not log the request body.'
Assert-True ($run.IndexOf('Write-Output $body',[StringComparison]::OrdinalIgnoreCase) -lt 0) 'Function must not log the request body.'

foreach ($needle in @(
    'BackendAuth.ps1',
    'AssociationOperations.ps1',
    'Get-WindowsDeviceLinkTenantAssociation',
    'New-WindowsDeviceLinkBackendAssociation',
    'VerificationFailed',
    'CreateUncertain'
)) {
    Assert-True ($run.IndexOf($needle,[StringComparison]::OrdinalIgnoreCase) -ge 0) "Preassociate Function is missing shared/verification contract text '$needle'."
}
Assert-True ($run.IndexOf('function Get-GraphToken',[StringComparison]::OrdinalIgnoreCase) -lt 0) 'Preassociate Function must not carry a private duplicate Graph-token implementation.'
Assert-True ($run.IndexOf('function Get-BackendCertificate',[StringComparison]::OrdinalIgnoreCase) -lt 0) 'Preassociate Function must use shared backend certificate/authentication helpers.'

$lookupRun = Get-Content -LiteralPath $lookupRunPath -Raw
$sharedBackend = Get-Content -LiteralPath $sharedBackendPath -Raw
$lookupContract = $lookupRun + [Environment]::NewLine + $sharedBackend
foreach ($needle in @(
    'serialNumber',
    'X-WindowsDeviceLink-Key',
    'WINDOWSDEVICELINK_ALLOWED_TENANTS',
    'WINDOWSDEVICELINK_TENANT_NAMES_JSON',
    'tenantAssociatedDevices',
    'ServerFilter',
    'ClientFallback',
    'tenantErrors',
    'Get-WindowsDeviceLinkBackendGraphToken'
)) {
    Assert-True ($lookupContract.IndexOf($needle,[StringComparison]::OrdinalIgnoreCase) -ge 0) "Lookup Function/shared backend is missing expected contract text '$needle'."
}
Assert-True ($lookupRun.IndexOf('device.deviceLink',[StringComparison]::OrdinalIgnoreCase) -lt 0) 'Lookup Function must not retrieve or return DeviceLink payload data.'

$reconcileRun = Get-Content -LiteralPath $reconcileRunPath -Raw
$associationOperations = Get-Content -LiteralPath $associationOperationsPath -Raw
$reconcileContract = $reconcileRun + [Environment]::NewLine + $associationOperations
foreach ($needle in @(
    'DeviceLinkReconcile',
    'sourceTenantId',
    'targetTenantId',
    "decision = 'New'",
    "decision = 'Move'",
    "decision = 'Update'",
    'LookupIncomplete',
    'AmbiguousState',
    'SourceStateMismatch',
    'SourceTenantRequired',
    'SourceStateChanged',
    'SourceRemovalUncertain',
    'MoveIncomplete',
    'Remove-WindowsDeviceLinkBackendAssociation',
    'New-WindowsDeviceLinkBackendAssociation'
)) {
    Assert-True ($reconcileContract.IndexOf($needle,[StringComparison]::OrdinalIgnoreCase) -ge 0) "Reconcile Function/shared operations are missing expected contract text '$needle'."
}
Assert-True ($reconcileRun.IndexOf('Write-Information $deviceLink',[StringComparison]::OrdinalIgnoreCase) -lt 0) 'Reconcile Function must not log DeviceLink payload data.'
Assert-True ($reconcileRun.IndexOf('Write-Host $deviceLink',[StringComparison]::OrdinalIgnoreCase) -lt 0) 'Reconcile Function must not log DeviceLink payload data.'

$arm = Get-Content -LiteralPath $armPath -Raw | ConvertFrom-Json
Assert-True ($arm.parameters.webhookApiKey.type -eq 'secureString') 'ARM webhookApiKey must be secureString.'
Assert-True ($arm.parameters.graphCredential.type -eq 'secureString') 'ARM graphCredential must be secureString.'
Assert-True ($arm.parameters.graphCertificatePassword.type -eq 'secureString') 'ARM graphCertificatePassword must be secureString.'

foreach ($name in @('functionAppName','appServicePlanName','storageAccountName','keyVaultResourceName','applicationInsightsName')) {
    Assert-True ($arm.parameters.PSObject.Properties.Name -contains $name) "ARM template is missing optional explicit resource-name parameter '$name'."
    Assert-True ([string]$arm.parameters.$name.defaultValue -eq '') "ARM explicit resource-name parameter '$name' must default to empty so namePrefix fallback remains available."
}

$armText = Get-Content -LiteralPath $armPath -Raw
foreach ($needle in @(
    'Microsoft.KeyVault/vaults',
    'Microsoft.Web/sites/functions',
    'Microsoft.Insights/components',
    'WINDOWSDEVICELINK_API_KEY',
    'WINDOWSDEVICELINK_ALLOWED_TENANTS',
    'WINDOWSDEVICELINK_TENANT_NAMES_JSON',
    'Lookup-WindowsDeviceLink',
    'devicelink/lookup',
    'Reconcile-WindowsDeviceLink',
    'devicelink/reconcile',
    '4633458b-17de-408a-b874-0445c86b69e6'
)) {
    Assert-True ($armText.IndexOf($needle,[StringComparison]::OrdinalIgnoreCase) -ge 0) "ARM template is missing expected resource/configuration '$needle'."
}

Assert-True ($armText.IndexOf('"methods": [\n            "delete"',[StringComparison]::OrdinalIgnoreCase) -lt 0) 'Function ARM template must not expose a standalone DELETE HTTP trigger.'

$bicep = Get-Content -LiteralPath $bicepPath -Raw
Assert-True ($bicep -match 'loadTextContent') 'Bicep deployment must source the committed Function receiver files.'
Assert-True ($bicep -match 'PowerShellVersion.*7\.4|powerShellVersion:\s*''7\.4''') 'Bicep deployment must target PowerShell 7.4.'
Assert-True ($bicep -match 'enableRbacAuthorization:\s*true') 'Key Vault must use Azure RBAC.'

foreach ($name in @('functionAppName','appServicePlanName','storageAccountName','keyVaultResourceName','applicationInsightsName')) {
    Assert-True ($bicep -match ("param\s+" + [regex]::Escape($name) + "\s+string\s*=\s*''")) "Bicep is missing optional explicit resource-name parameter '$name'."
}
Assert-True ($bicep -match 'empty\(functionAppName\).*generatedFunctionAppName') 'Function App naming must fall back to the generated prefix-based name.'
Assert-True ($bicep -match 'empty\(storageAccountName\).*generatedStorageName') 'Storage naming must fall back to the generated prefix-based name.'

Write-Host 'PASS: Azure Function backend, lookup/reconcile contracts, and deployment template satisfy static security/contract checks.'
