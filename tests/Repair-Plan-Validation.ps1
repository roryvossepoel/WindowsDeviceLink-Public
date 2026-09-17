<#
WindowsDeviceLink lifecycle repair planning regression tests.
Hardware- and tenant-independent. The planner must remain non-destructive.
#>
[CmdletBinding()] param([string]$ModulePath)
$ErrorActionPreference='Stop'

function Assert-True { param([bool]$Condition,[string]$Message) if(-not $Condition){throw "FAIL: $Message"} }
if(-not $ModulePath){$ModulePath=Join-Path $PSScriptRoot '..\src\WindowsDeviceLink\WindowsDeviceLink.psd1'}
Remove-Module WindowsDeviceLink -Force -ErrorAction SilentlyContinue
Import-Module (Resolve-Path -LiteralPath $ModulePath).Path -Force -ErrorAction Stop

function New-Health {
    param([string]$State,[string]$Severity='Warning',[bool]$CloudChecked=$true,[string]$AssociationState='Unknown',[string]$Firmware='2/4')
    $h=[pscustomobject]@{
        State=$State;Severity=$Severity;RecommendedAction='synthetic recommendation';AssociationId='assoc-test';AssociationState=$AssociationState
        LinkId='link-test';FirmwareVariablesPresent=$Firmware;CloudChecked=$CloudChecked
    }
    $h.PSObject.TypeNames.Insert(0,'Windows.DeviceLink.Health')
    $h
}

$cases=@(
    @{State='LocalOnly';Action='UseInitialize';Safe=$true;Investigate=$false;Register=$true},
    @{State='Preassociated';Action='NoAction';Safe=$true;Investigate=$false;Register=$false},
    @{State='Associated';Action='NoAction';Safe=$true;Investigate=$false;Register=$false},
    @{State='LocalBaseIdentity';Action='NoLocalRepair';Safe=$true;Investigate=$false;Register=$false},
    @{State='LocalCompleteFirmwareState';Action='CheckCloudState';Safe=$true;Investigate=$false;Register=$false},
    @{State='CloudAssociationMissingWithCompleteFirmware';Action='ReviewLifecycleIntent';Safe=$false;Investigate=$true;Register=$false},
    @{State='NoFirmwareState';Action='ReviewLifecycleIntent';Safe=$false;Investigate=$true;Register=$false},
    @{State='IncompleteFirmwareState';Action='InvestigateFirmware';Safe=$false;Investigate=$true;Register=$false},
    @{State='PreassociatedUnexpectedFirmwareState';Action='InvestigateLifecycleMismatch';Safe=$false;Investigate=$true;Register=$false},
    @{State='AssociatedIncompleteFirmwareState';Action='RecheckThenInvestigate';Safe=$false;Investigate=$true;Register=$false},
    @{State='Unsupported';Action='ResolveSupportIssue';Safe=$false;Investigate=$true;Register=$false},
    @{State='IdentityUnavailable';Action='ResolveIdentityIssue';Safe=$false;Investigate=$true;Register=$false},
    @{State='FirmwareUnavailable';Action='ResolveFirmwareAccessIssue';Safe=$false;Investigate=$true;Register=$false},
    @{State='CloudUnknown';Action='RetryCloudLookup';Safe=$false;Investigate=$true;Register=$false},
    @{State='FirmwareStateUnknown';Action='InvestigateFirmware';Safe=$false;Investigate=$true;Register=$false},
    @{State='UnclassifiedAssociationState';Action='InvestigateAssociationState';Safe=$false;Investigate=$true;Register=$false},
    @{State='FutureState';Action='InvestigateUnknownState';Safe=$false;Investigate=$true;Register=$false}
)

foreach($case in $cases){
    $plan=New-Health -State $case.State | Get-WindowsDeviceLinkRepairPlan
    Assert-True ($plan.CurrentState -eq $case.State) "$($case.State): CurrentState mismatch."
    Assert-True ($plan.Action -eq $case.Action) "$($case.State): expected action $($case.Action), got $($plan.Action)."
    Assert-True ($plan.SafeToAutomate -eq $case.Safe) "$($case.State): SafeToAutomate mismatch."
    Assert-True ($plan.RequiresInvestigation -eq $case.Investigate) "$($case.State): RequiresInvestigation mismatch."
    Assert-True ($plan.RequiresRegistration -eq $case.Register) "$($case.State): RequiresRegistration mismatch."

    # Hard safety boundary: health classification alone can never authorize destructive repair.
    Assert-True (-not $plan.DestructiveActionsAllowed) "$($case.State): planner authorized destructive actions."
    Assert-True (-not $plan.RequiresCloudDelete) "$($case.State): planner requested cloud deletion."
    Assert-True (-not $plan.RequiresFirmwareReset) "$($case.State): planner requested firmware reset."
    Assert-True (-not $plan.RequiresReboot) "$($case.State): planner requested reboot."
    Write-Host "PASS: $($case.State) -> $($plan.Action)"
}

$cloudUnknown=New-Health -State 'CloudUnknown' | Get-WindowsDeviceLinkRepairPlan
Assert-True ($cloudUnknown.Reason -like '*never authorize*') 'CloudUnknown plan does not explicitly block destructive authorization from cloud failure.'
Write-Host 'PASS: cloud lookup failure can never authorize destructive repair'

$command=Get-Command Get-WindowsDeviceLinkRepairPlan
Assert-True (-not $command.Parameters.ContainsKey('WhatIf')) 'Read-only repair planner unexpectedly exposes WhatIf.'
Write-Host 'PASS: repair planner is read-only and exposes no mutation controls'

Write-Host ''
Write-Host 'Repair planning regression set passed.'
