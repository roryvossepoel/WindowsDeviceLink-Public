<#
WindowsDeviceLink cloud-operation parameter regression tests for 0.4.4-preview1.

These tests exercise the explicit separation between local DeviceLink retrieval and
cloud Device Association operations. They do not require Graph credentials or TPM
access unless the optional live webhook test is enabled.
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
    if (-not (Test-Path -LiteralPath $candidate -PathType Leaf)) { throw "WindowsDeviceLink manifest not found: $candidate" }
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

$fakeDeviceLink = [pscustomobject]@{
    SerialNumber = 'TEST-SERIAL'
    DeviceLink   = 'TEST-PAYLOAD'
}
$fakeDeviceLink.PSObject.TypeNames.Insert(0, 'Windows.DeviceLink.Information')

Assert-Throws -Name 'Get-WindowsDeviceLink no longer accepts Online' -ExpectedMessage "parameter name 'Online'" -ScriptBlock {
    Get-WindowsDeviceLink -Online
}

Assert-Throws -Name 'Register Webhook requires WebhookUri' -ExpectedMessage '-WebhookUri is required for -Method Webhook' -ScriptBlock {
    $fakeDeviceLink | Register-WindowsDeviceLink -Method Webhook
}

$testSecret = ConvertTo-SecureString 'not-a-real-secret' -AsPlainText -Force
Assert-Throws -Name 'Register Webhook rejects ClientSecret' -ExpectedMessage 'not valid with -Method Webhook' -ScriptBlock {
    $fakeDeviceLink | Register-WindowsDeviceLink -Method Webhook -WebhookUri 'https://example.invalid/' -ClientSecret $testSecret
}

Assert-Throws -Name 'Register DeviceCode requires TenantId' -ExpectedMessage '-TenantId is required for -Method DeviceCode' -ScriptBlock {
    $fakeDeviceLink | Register-WindowsDeviceLink -Method DeviceCode
}

Assert-Throws -Name 'Association lookup requires selector' -ExpectedMessage 'Specify exactly one of -AssociationId or -SerialNumber' -ScriptBlock {
    Get-WindowsDeviceLinkAssociation -Method DeviceCode -TenantId '00000000-0000-0000-0000-000000000000'
}

Assert-Throws -Name 'Association lookup rejects two selectors' -ExpectedMessage 'Specify exactly one of -AssociationId or -SerialNumber' -ScriptBlock {
    Get-WindowsDeviceLinkAssociation -AssociationId 'test-id' -SerialNumber 'TEST-SERIAL' -Method DeviceCode -TenantId '00000000-0000-0000-0000-000000000000'
}

Assert-Throws -Name 'Association DeviceCode requires TenantId' -ExpectedMessage '-TenantId is required for -Method DeviceCode' -ScriptBlock {
    Get-WindowsDeviceLinkAssociation -SerialNumber 'TEST-SERIAL' -Method DeviceCode
}

Assert-Throws -Name 'Association ClientSecret requires all inputs' -ExpectedMessage '-TenantId, -ClientId, and -ClientSecret are required' -ScriptBlock {
    Get-WindowsDeviceLinkAssociation -SerialNumber 'TEST-SERIAL' -Method ClientSecret -TenantId '00000000-0000-0000-0000-000000000000'
}

Write-Host ''
Write-Host 'Cloud-operation parameter validation regression set passed.'

if ($PSBoundParameters.ContainsKey('WebhookUri')) {
    Write-Host ''
    Write-Host 'Running optional live webhook registration test...'

    $deviceLink = Get-WindowsDeviceLink
    $parameters = @{ Method = 'Webhook'; WebhookUri = $WebhookUri }
    if ($PSBoundParameters.ContainsKey('WebhookApiKey')) { $parameters.WebhookApiKey = $WebhookApiKey }
    if ($TenantId) { $parameters.TenantId = $TenantId }

    $result = $deviceLink | Register-WindowsDeviceLink @parameters
    if (-not $result.RequestId) { throw 'FAIL: live webhook test returned no RequestId.' }
    if (-not $result.SerialNumber) { throw 'FAIL: live webhook test returned no SerialNumber.' }

    Write-Host "PASS: live webhook transport - RequestId $($result.RequestId)"
}
