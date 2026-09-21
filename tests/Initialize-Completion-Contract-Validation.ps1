<#
Validates the Initialize-WindowsDeviceLink full-association opt-in contract.

This test is hardware-independent. It does not invoke DeviceLink, Graph, firmware, or native
association operations. It parses the public cmdlet source and verifies that full association
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
Assert-True ($parameterNames -contains 'FullAssociation') 'Initialize-WindowsDeviceLink is missing the explicit -FullAssociation switch.'

$source=[IO.File]::ReadAllText($path)
Assert-True ($source -match '\[switch\]\$FullAssociation') '-FullAssociation must remain an explicit switch parameter.'
Assert-True ($source -match 'if\s*\(\s*\$FullAssociation\s+-and\s+\$afterHealth\.State\s+-eq\s+''Preassociated''\s*\)') 'Full association must be gated by -FullAssociation and verified Preassociated state.'
Assert-True ($source -match 'Complete-WindowsDeviceLinkAssociation\s+@completeParameters') 'Initializer must delegate the device-side operation to Complete-WindowsDeviceLinkAssociation.'
Assert-True ($source -match 'FullAssociationRequested=\[bool\]\$FullAssociation') 'Initialization result must expose whether full association was requested.'
Assert-True ($source -match 'FullAssociationResult=\$fullAssociationResult') 'Initialization result must expose the full-association result.'
Assert-True ($source -match 'FullAssociationDetails=\$completion') 'Initialization result must expose the low-level full-association details.'

$fullAssociationCalls=@($functionAst.FindAll({param($n)
    $n -is [System.Management.Automation.Language.CommandAst] -and $n.GetCommandName() -eq 'Complete-WindowsDeviceLinkAssociation'
},$true))
Assert-True ($fullAssociationCalls.Count -eq 1) 'Initialize-WindowsDeviceLink must contain exactly one full-association command invocation.'

Write-Host 'PASS: Initialize-WindowsDeviceLink full association remains explicit opt-in behavior.'
Write-Host 'PASS: Full association delegates to the guarded Complete-WindowsDeviceLinkAssociation cmdlet exactly once.'
Write-Host 'PASS: Initialization result exposes full-association request/result/details state.'
