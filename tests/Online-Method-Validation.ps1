<#
WindowsDeviceLink online-method regression tests.

These tests intentionally exercise parameter validation before DeviceLink generation.
They do not require Graph credentials, TPM access, or a live webhook.

Optional live webhook validation can be enabled with -WebhookUri. That test does
require DeviceLink support on the machine running the script.
#>

[CmdletBinding()]
param(
    [string]$ModulePath,
    [uri]$WebhookUri,
    [string]$WebhookApiKey,
    [string]$TenantId
)

$ErrorActionPreference = 'Stop'

function Resolve-ModulePath {
    if ($ModulePath) { return (Resolve-Path -LiteralPath $ModulePath).Path }

    $candidate = Join-Path $PSScriptRoot '..\src\WindowsDeviceLink\WindowsDeviceLink.psd1'
    if (-not (Test-Path -LiteralPath $candidate -PathType Leaf)) {
        throw "WindowsDeviceLink manifest not found: $candidate"
    }
    (Resolve-Path -LiteralPath $candidate).Path
}

function Assert-Throws {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][scriptblock]$ScriptBlock,
        [Parameter(Mandatory)][string]$ExpectedMessage
    )

    try {
        & $ScriptBlock
        throw "FAIL: $Name - expected an exception but none was thrown."
    }
    catch {
        if ($_.Exception.Message -notlike "*$ExpectedMessage*") {
            throw "FAIL: $Name - expected message containing '$ExpectedMessage', received '$($_.Exception.Message)'."
        }
        Write-Host "PASS: $Name"
    }
}

$resolvedModulePath = Resolve-ModulePath
Import-Module $resolvedModulePath -Force

Assert-Throws -Name 'Online requires Method' -ExpectedMessage '-Method is required with -Online' -ScriptBlock {
    Get-WindowsDeviceLink -Online
}

Assert-Throws -Name 'Webhook requires WebhookUri' -ExpectedMessage '-WebhookUri is required for -Method Webhook' -ScriptBlock {
    Get-WindowsDeviceLink -Online -Method Webhook
}

$testSecret = ConvertTo-SecureString 'not-a-real-secret' -AsPlainText -Force
Assert-Throws -Name 'Webhook rejects ClientSecret' -ExpectedMessage 'not valid with -Method Webhook' -ScriptBlock {
    Get-WindowsDeviceLink `
        -Online `
        -Method Webhook `
        -WebhookUri 'https://example.invalid/' `
        -ClientSecret $testSecret
}

Assert-Throws -Name 'DeviceCode requires TenantId' -ExpectedMessage '-TenantId is required for -Method DeviceCode' -ScriptBlock {
    Get-WindowsDeviceLink -Online -Method DeviceCode
}

Assert-Throws -Name 'ClientSecret requires all inputs' -ExpectedMessage '-TenantId, -ClientId, and -ClientSecret are required' -ScriptBlock {
    Get-WindowsDeviceLink -Online -Method ClientSecret -TenantId '00000000-0000-0000-0000-000000000000'
}

Assert-Throws -Name 'AccessToken requires token' -ExpectedMessage '-TenantId and -AccessToken are required' -ScriptBlock {
    Get-WindowsDeviceLink -Online -Method AccessToken -TenantId '00000000-0000-0000-0000-000000000000'
}

Write-Host ''
Write-Host 'Parameter validation regression set passed.'

if ($PSBoundParameters.ContainsKey('WebhookUri')) {
    Write-Host ''
    Write-Host 'Running optional live webhook test...'

    $parameters = @{
        Online = $true
        Method = 'Webhook'
        WebhookUri = $WebhookUri
    }
    if ($PSBoundParameters.ContainsKey('WebhookApiKey')) { $parameters.WebhookApiKey = $WebhookApiKey }
    if ($TenantId) { $parameters.TenantId = $TenantId }

    $result = Get-WindowsDeviceLink @parameters
    if (-not $result.RequestId) { throw 'FAIL: live webhook test returned no RequestId.' }
    if (-not $result.SerialNumber) { throw 'FAIL: live webhook test returned no SerialNumber.' }

    Write-Host "PASS: live webhook transport - RequestId $($result.RequestId)"
}
