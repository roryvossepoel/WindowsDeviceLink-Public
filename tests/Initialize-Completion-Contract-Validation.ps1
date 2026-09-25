<#
Validates the Initialize-WindowsDeviceLink association opt-in contract.

This test is hardware-independent. It does not invoke DeviceLink, Graph, firmware, or native
association operations. It parses the public cmdlet source and verifies that association
remains explicit opt-in behavior.
#>
[CmdletBinding()]
param()

$ErrorActionPreference='Stop'

function Assert-True {
    param([Parameter(Mandatory)][bool]$Condition,[Parameter(Mandatory)][string]$Message)
    if(-not $Condition){ throw "FAIL: $Message" }
}

$path=(Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\src\WindowsDeviceLink\Public\Initialize-WindowsDeviceLink.ps1')).Path
$tokens=$null
$errors=$null
$ast=[System.Management.Automation.Language.Parser]::ParseFile($path,[ref]$tokens,[ref]$errors)
if($errors.Count -gt 0){
    $detail=($errors|ForEach-Object{"$($_.Extent.Text): $($_.Message)"}) -join '; '
    throw "FAIL: Initialize-WindowsDeviceLink parser errors: $detail"
}

$functionAst=$ast.Find({param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Initialize-WindowsDeviceLink'},$true)
Assert-True ($null -ne $functionAst) 'Initialize-WindowsDeviceLink function was not found.'

$parameterNames=@($functionAst.Body.ParamBlock.Parameters | ForEach-Object { $_.Name.VariablePath.UserPath })
Assert-True ($parameterNames -contains 'Associate') 'Initialize-WindowsDeviceLink is missing the explicit -Associate switch.'
Assert-True ($parameterNames -contains 'BackendUri') 'Initialize-WindowsDeviceLink is missing -BackendUri.'
Assert-True ($parameterNames -contains 'BackendApiKey') 'Initialize-WindowsDeviceLink is missing -BackendApiKey.'
Assert-True ($parameterNames -contains 'TargetTenantId') 'Initialize-WindowsDeviceLink is missing -TargetTenantId.'

$source=[IO.File]::ReadAllText($path)
Assert-True ($source -match '\[switch\]\$Associate') '-Associate must remain an explicit switch parameter.'
$retiredTerm = 'Full' + 'Association'
Assert-True ($source -notmatch $retiredTerm) 'The retired preview terminology must not remain as a parameter or alias.'
Assert-True ($source -match 'if\s*\(\s*\$Associate\s+-and\s+\$afterHealth\.State\s+-eq\s+''Preassociated''\s*\)') 'Association must be gated by -Associate and verified Preassociated state.'
Assert-True ($source -match 'Complete-WindowsDeviceLinkAssociation\s+@completeParameters') 'Initializer must delegate the device-side operation to Complete-WindowsDeviceLinkAssociation.'
Assert-True ($source -match 'AssociationRequested=\[bool\]\$Associate') 'Initialization result must expose whether association was requested.'
Assert-True ($source -match 'AssociationResult=\$associationResult') 'Initialization result must expose the association result.'
Assert-True ($source -match 'AssociationDetails=\$completion') 'Initialization result must expose the low-level association details.'

$associationCalls=@($functionAst.FindAll({param($n)
    $n -is [System.Management.Automation.Language.CommandAst] -and $n.GetCommandName() -eq 'Complete-WindowsDeviceLinkAssociation'
},$true))
Assert-True ($associationCalls.Count -eq 2) 'Initialize-WindowsDeviceLink must contain one guarded association invocation for each Direct/Backend orchestration path.'

Write-Host 'PASS: Initialize-WindowsDeviceLink association remains explicit opt-in behavior.'
Write-Host 'PASS: Direct and Function-backed association both delegate to the guarded Complete-WindowsDeviceLinkAssociation cmdlet.'
Write-Host 'PASS: Initialization result exposes association request/result/details state.'
