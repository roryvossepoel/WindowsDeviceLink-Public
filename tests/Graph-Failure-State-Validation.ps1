<#
WindowsDeviceLink Graph failure-state regression tests.

These tests are hardware- and tenant-independent. They exercise the same private
cloud-state and initialization-action resolvers used by the public status/initializer
cmdlets. The critical invariant is that a failed/indeterminate cloud lookup can never
become confirmed NotAssociated/LocalOnly or authorize registration.
#>

[CmdletBinding()]
param([string]$ModulePath)

$ErrorActionPreference = 'Stop'

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "FAIL: $Message" }
}

if (-not $ModulePath) {
    $ModulePath = Join-Path $PSScriptRoot '..\src\WindowsDeviceLink\WindowsDeviceLink.psd1'
}
$resolvedModulePath = (Resolve-Path -LiteralPath $ModulePath).Path

Remove-Module WindowsDeviceLink -Force -ErrorAction SilentlyContinue
Import-Module $resolvedModulePath -Force -ErrorAction Stop
$module = Get-Module WindowsDeviceLink | Select-Object -First 1
if (-not $module) { throw 'FAIL: WindowsDeviceLink did not load.' }

function Resolve-CloudState {
    param([bool]$CloudChecked,[AllowNull()][psobject]$Association,[AllowNull()][string]$AssociationError)
    & $module {
        param($Checked,$Record,$ErrorText)
        Resolve-WindowsDeviceLinkCloudState -CloudChecked $Checked -Association $Record -AssociationError $ErrorText
    } $CloudChecked $Association $AssociationError
}

function Resolve-InitializationAction {
    param([string]$HealthState)
    & $module { param($State) Resolve-WindowsDeviceLinkInitializationAction -HealthState $State } $HealthState
}

function New-SyntheticStatus {
    param(
        [Nullable[bool]]$AssociationPresent,
        [string]$AssociationState,
        [string]$AssociationError
    )
    [pscustomobject]@{
        PSTypeName='Windows.DeviceLink.Status'; Environment='Test'; Supported=$true; DeviceLinkPresent=$true
        LinkId='00000000-0000-0000-0000-000000000001'; FirmwareChecked=$true
        FirmwareVariablesPresent='2/4'; FirmwareStateComplete=$false; FirmwareCreationTimeUtc=[datetime]'2026-01-01T00:00:00Z'
        CloudChecked=$true; AssociationPresent=$AssociationPresent; AssociationState=$AssociationState
        AssociationId=$null; SupportReason=$null; IdentityError=$null; FirmwareError=$null; AssociationError=$AssociationError
    }
}

$failureCases = @(
    'HTTP 401 Unauthorized',
    'HTTP 403 Forbidden',
    'HTTP 404 Not Found from collection lookup',
    'HTTP 409 Conflict during lookup',
    'HTTP 429 Too Many Requests; Retry-After: 30',
    'HTTP 500 Internal Server Error',
    'HTTP 503 Service Unavailable',
    'The operation timed out.',
    'The remote name could not be resolved.',
    'Graph response was empty or malformed.',
    'Multiple Device Association records were returned for serial number TEST-SERIAL.'
)

foreach ($failure in $failureCases) {
    $cloud = Resolve-CloudState -CloudChecked $true -Association $null -AssociationError $failure
    Assert-True ($null -eq $cloud.AssociationPresent) "'$failure': AssociationPresent must remain null/unknown, not false."
    Assert-True ($cloud.AssociationState -eq 'Unknown') "'$failure': AssociationState must be Unknown."

    $status = New-SyntheticStatus -AssociationPresent $cloud.AssociationPresent -AssociationState $cloud.AssociationState -AssociationError $failure
    $health = $status | Test-WindowsDeviceLinkHealth
    Assert-True ($health.State -eq 'CloudUnknown') "'$failure': health must be CloudUnknown, got '$($health.State)'."
    Assert-True ($health.State -notin @('LocalOnly','Preassociated','Associated')) "'$failure': cloud failure became a confirmed lifecycle state."

    $action = Resolve-InitializationAction $health.State
    Assert-True ($action -eq 'Blocked') "'$failure': initializer decision must be Blocked, got '$action'."
    Write-Host "PASS: fail-safe cloud state - $failure"
}

# No cloud lookup means no tenant-side claim at all.
$notChecked = Resolve-CloudState -CloudChecked $false -Association $null -AssociationError $null
Assert-True ($null -eq $notChecked.AssociationPresent -and $null -eq $notChecked.AssociationState) 'unchecked cloud state must remain null.'
Write-Host 'PASS: unchecked cloud state remains unspecified'

# Positive control: only a successful empty lookup becomes confirmed NotAssociated,
# which then maps to LocalOnly and permits the safe registration action.
$empty = Resolve-CloudState -CloudChecked $true -Association $null -AssociationError $null
Assert-True ($empty.AssociationPresent -eq $false) 'successful empty lookup must report AssociationPresent=False.'
Assert-True ($empty.AssociationState -eq 'NotAssociated') 'successful empty lookup must report NotAssociated.'
$emptyHealth = New-SyntheticStatus -AssociationPresent $empty.AssociationPresent -AssociationState $empty.AssociationState -AssociationError $null | Test-WindowsDeviceLinkHealth
Assert-True ($emptyHealth.State -eq 'LocalOnly') "successful empty lookup expected LocalOnly, got '$($emptyHealth.State)'."
Assert-True ((Resolve-InitializationAction $emptyHealth.State) -eq 'Register') 'LocalOnly must be the registration-authorized initializer state.'
Write-Host 'PASS: successful empty lookup remains distinct from Graph failure'

# Known association states are preserved; already-associated lifecycle states never
# authorize another registration.
foreach ($state in @('preassociated','associated')) {
    $record = [pscustomobject]@{ AssociationState=$state }
    $resolved = Resolve-CloudState -CloudChecked $true -Association $record -AssociationError $null
    Assert-True ($resolved.AssociationPresent -eq $true) "$state must report AssociationPresent=True."
    Assert-True ($resolved.AssociationState -eq $state) "$state must be preserved."

    $firmwareCount = if ($state -eq 'associated') { '4/4' } else { '2/4' }
    $firmwareComplete = $state -eq 'associated'
    $status = New-SyntheticStatus -AssociationPresent $true -AssociationState $state -AssociationError $null
    $status.FirmwareVariablesPresent = $firmwareCount
    $status.FirmwareStateComplete = $firmwareComplete
    $health = $status | Test-WindowsDeviceLinkHealth
    Assert-True ((Resolve-InitializationAction $health.State) -eq 'None') "$state must not authorize registration."
    Write-Host "PASS: existing $state state is idempotent"
}

# Future/unknown association states are preserved for diagnostics but blocked by the
# initializer until explicitly understood and classified.
$future = Resolve-CloudState -CloudChecked $true -Association ([pscustomobject]@{AssociationState='futureState'}) -AssociationError $null
$futureHealth = New-SyntheticStatus -AssociationPresent $true -AssociationState $future.AssociationState -AssociationError $null | Test-WindowsDeviceLinkHealth
Assert-True ($futureHealth.State -eq 'UnclassifiedAssociationState') "future state expected UnclassifiedAssociationState, got '$($futureHealth.State)'."
Assert-True ((Resolve-InitializationAction $futureHealth.State) -eq 'Blocked') 'unknown future association state must be blocked.'
Write-Host 'PASS: unknown future association state fails conservatively'

# Static integration invariants ensure the tested pure resolvers remain wired into the
# public cmdlets rather than becoming unused helper code.
$moduleRoot = Split-Path -Parent $resolvedModulePath
$statusSource = Get-Content -LiteralPath (Join-Path $moduleRoot 'Public\Get-WindowsDeviceLinkStatus.ps1') -Raw
$initializerSource = Get-Content -LiteralPath (Join-Path $moduleRoot 'Public\Initialize-WindowsDeviceLink.ps1') -Raw
Assert-True ($statusSource -match 'Resolve-WindowsDeviceLinkCloudState') 'Get-WindowsDeviceLinkStatus is not using the tested cloud-state resolver.'
Assert-True ($initializerSource -match 'Resolve-WindowsDeviceLinkInitializationAction') 'Initialize-WindowsDeviceLink is not using the tested action resolver.'
Write-Host 'PASS: fail-safe resolvers are wired into public status and initialization cmdlets'

Write-Host ''
Write-Host 'Graph failure-state regression set passed.'
