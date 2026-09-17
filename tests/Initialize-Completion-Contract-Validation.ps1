<#
Validates the Initialize-WindowsDeviceLink completion opt-in contract.

This test is hardware-independent. It does not invoke DeviceLink, Graph, firmware, or native
association operations. It parses the public cmdlet source and verifies that association
completion remains explicit opt-in behavior.
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
Assert-True ($parameterNames -contains 'CompleteAssociation') 'Initialize-WindowsDeviceLink is missing the explicit -CompleteAssociation switch.'

$source=[IO.File]::ReadAllText($path)
Assert-True ($source -match '\[switch\]\$CompleteAssociation') '-CompleteAssociation must remain an explicit switch parameter.'
Assert-True ($source -match 'if\s*\(\s*\$CompleteAssociation\s+-and\s+\$afterHealth\.State\s+-eq\s+''Preassociated''\s*\)') 'Completion must be gated by -CompleteAssociation and verified Preassociated state.'
Assert-True ($source -match 'Complete-WindowsDeviceLinkAssociation\s+@completeParameters') 'Initializer must delegate device-side completion to Complete-WindowsDeviceLinkAssociation.'
Assert-True ($source -match 'CompletionRequested=\[bool\]\$CompleteAssociation') 'Initialization result must expose whether completion was requested.'
Assert-True ($source -match 'CompletionResult=\$completion') 'Initialization result must expose the completion result.'

$completionCalls=@($functionAst.FindAll({param($n)
    $n -is [System.Management.Automation.Language.CommandAst] -and $n.GetCommandName() -eq 'Complete-WindowsDeviceLinkAssociation'
},$true))
Assert-True ($completionCalls.Count -eq 1) 'Initialize-WindowsDeviceLink must contain exactly one completion command invocation.'

Write-Host 'PASS: Initialize-WindowsDeviceLink completion remains explicit opt-in behavior.'
Write-Host 'PASS: completion delegates to the guarded public completion cmdlet exactly once.'
Write-Host 'PASS: initialization result exposes completion request/result state.'
