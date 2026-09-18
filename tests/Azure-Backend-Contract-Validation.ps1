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
$hostPath = Join-Path $functionRoot 'host.json'
$bicepPath = Join-Path $root 'infrastructure\function-app\main.bicep'
$armPath = Join-Path $root 'infrastructure\function-app\azuredeploy.json'

foreach ($path in @($runPath,$functionJsonPath,$hostPath,$bicepPath,$armPath)) {
    Assert-True (Test-Path -LiteralPath $path -PathType Leaf) "Required Azure backend file is missing: $path"
}

$tokens = $null
$errors = $null
[void][Management.Automation.Language.Parser]::ParseFile($runPath,[ref]$tokens,[ref]$errors)
Assert-True ($errors.Count -eq 0) ("Function run.ps1 has PowerShell parse errors: " + (($errors | ForEach-Object Message) -join '; '))

$functionJson = Get-Content -LiteralPath $functionJsonPath -Raw | ConvertFrom-Json
$trigger = @($functionJson.bindings | Where-Object type -eq 'httpTrigger')
Assert-True ($trigger.Count -eq 1) 'Function must expose exactly one HTTP trigger.'
Assert-True ([string]$trigger[0].route -eq 'devicelink/preassociate') 'Unexpected Function route.'
Assert-True ([string]$trigger[0].authLevel -eq 'anonymous') 'Function uses custom X-WindowsDeviceLink-Key validation and must keep the declared authLevel consistent.'

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

$arm = Get-Content -LiteralPath $armPath -Raw | ConvertFrom-Json -Depth 100
Assert-True ($arm.parameters.webhookApiKey.type -eq 'secureString') 'ARM webhookApiKey must be secureString.'
Assert-True ($arm.parameters.graphCredential.type -eq 'secureString') 'ARM graphCredential must be secureString.'
Assert-True ($arm.parameters.graphCertificatePassword.type -eq 'secureString') 'ARM graphCertificatePassword must be secureString.'

$armText = Get-Content -LiteralPath $armPath -Raw
foreach ($needle in @(
    'Microsoft.KeyVault/vaults',
    'Microsoft.Web/sites/functions',
    'Microsoft.Insights/components',
    'WINDOWSDEVICELINK_API_KEY',
    'WINDOWSDEVICELINK_ALLOWED_TENANTS',
    '4633458b-17de-408a-b874-0445c86b69e6'
)) {
    Assert-True ($armText.IndexOf($needle,[StringComparison]::OrdinalIgnoreCase) -ge 0) "ARM template is missing expected resource/configuration '$needle'."
}

$bicep = Get-Content -LiteralPath $bicepPath -Raw
Assert-True ($bicep -match 'loadTextContent') 'Bicep deployment must source the committed Function receiver files.'
Assert-True ($bicep -match 'PowerShellVersion.*7\.4|powerShellVersion:\s*''7\.4''') 'Bicep deployment must target PowerShell 7.4.'
Assert-True ($bicep -match 'enableRbacAuthorization:\s*true') 'Key Vault must use Azure RBAC.'

Write-Host 'PASS: Azure Function receiver, webhook contract, and deployment templates satisfy static security/contract checks.'
