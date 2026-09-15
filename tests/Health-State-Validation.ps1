<#
WindowsDeviceLink health-classification regression tests.

These tests use synthetic Windows.DeviceLink.Status objects. They do not require
DeviceLink-capable hardware, firmware access, Microsoft Graph, or credentials.
#>

[CmdletBinding()]
param([string]$ModulePath)

$ErrorActionPreference = 'Stop'

if (-not $ModulePath) {
    $ModulePath = Join-Path $PSScriptRoot '..\src\WindowsDeviceLink\WindowsDeviceLink.psd1'
}
Import-Module (Resolve-Path -LiteralPath $ModulePath).Path -Force

function New-TestStatus {
    param(
        [bool]$Supported = $true,
        [bool]$DeviceLinkPresent = $true,
        [bool]$FirmwareChecked = $true,
        [string]$FirmwareVariablesPresent = '2/4',
        [bool]$FirmwareStateComplete = $false,
        [bool]$CloudChecked = $false,
        [Nullable[bool]]$AssociationPresent = $null,
        [string]$AssociationState,
        [string]$SupportReason,
        [string]$IdentityError,
        [string]$FirmwareError,
        [string]$AssociationError
    )

    [pscustomobject]@{
        PSTypeName               = 'Windows.DeviceLink.Status'
        Environment              = 'Test'
        Supported                = $Supported
        DeviceLinkPresent        = $DeviceLinkPresent
        LinkId                   = '00000000-0000-0000-0000-000000000001'
        FirmwareChecked          = $FirmwareChecked
        FirmwareVariablesPresent = $FirmwareVariablesPresent
        FirmwareStateComplete    = $FirmwareStateComplete
        FirmwareCreationTimeUtc  = [datetime]'2026-01-01T00:00:00Z'
        CloudChecked             = $CloudChecked
        AssociationPresent       = $AssociationPresent
        AssociationState         = $AssociationState
        AssociationId            = if ($AssociationPresent) { '00000000-0000-0000-0000-000000000002' } else { $null }
        SupportReason            = $SupportReason
        IdentityError            = $IdentityError
        FirmwareError            = $FirmwareError
        AssociationError         = $AssociationError
    }
}

$cases = @(
    @{ Name='Unsupported'; Expected='Unsupported'; Severity='Error'; Status=(New-TestStatus -Supported $false -SupportReason 'unsupported') },
    @{ Name='IdentityUnavailable'; Expected='IdentityUnavailable'; Severity='Error'; Status=(New-TestStatus -DeviceLinkPresent $false -IdentityError 'identity failed') },
    @{ Name='FirmwareUnavailable'; Expected='FirmwareUnavailable'; Severity='Error'; Status=(New-TestStatus -FirmwareChecked $false -FirmwareError 'firmware failed') },
    @{ Name='CloudUnknown'; Expected='CloudUnknown'; Severity='Warning'; Status=(New-TestStatus -CloudChecked $true -AssociationPresent $null -AssociationState 'Unknown' -AssociationError 'lookup failed') },
    @{ Name='FirmwareStateUnknown'; Expected='FirmwareStateUnknown'; Severity='Warning'; Status=(New-TestStatus -FirmwareVariablesPresent 'unknown') },
    @{ Name='NoFirmwareState'; Expected='NoFirmwareState'; Severity='Warning'; Status=(New-TestStatus -FirmwareVariablesPresent '0/4') },
    @{ Name='IncompleteFirmware1'; Expected='IncompleteFirmwareState'; Severity='Warning'; Status=(New-TestStatus -FirmwareVariablesPresent '1/4') },
    @{ Name='IncompleteFirmware3'; Expected='IncompleteFirmwareState'; Severity='Warning'; Status=(New-TestStatus -FirmwareVariablesPresent '3/4') },
    @{ Name='LocalBaseIdentity'; Expected='LocalBaseIdentity'; Severity='Information'; Status=(New-TestStatus -FirmwareVariablesPresent '2/4') },
    @{ Name='LocalCompleteFirmwareState'; Expected='LocalCompleteFirmwareState'; Severity='Information'; Status=(New-TestStatus -FirmwareVariablesPresent '4/4' -FirmwareStateComplete $true) },
    @{ Name='LocalOnly'; Expected='LocalOnly'; Severity='Information'; Status=(New-TestStatus -FirmwareVariablesPresent '2/4' -CloudChecked $true -AssociationPresent $false -AssociationState 'NotAssociated') },
    @{ Name='CloudAssociationMissingWithCompleteFirmware'; Expected='CloudAssociationMissingWithCompleteFirmware'; Severity='Warning'; Status=(New-TestStatus -FirmwareVariablesPresent '4/4' -FirmwareStateComplete $true -CloudChecked $true -AssociationPresent $false -AssociationState 'NotAssociated') },
    @{ Name='Preassociated'; Expected='Preassociated'; Severity='Information'; Status=(New-TestStatus -FirmwareVariablesPresent '2/4' -CloudChecked $true -AssociationPresent $true -AssociationState 'preassociated') },
    @{ Name='PreassociatedUnexpectedFirmwareState'; Expected='PreassociatedUnexpectedFirmwareState'; Severity='Warning'; Status=(New-TestStatus -FirmwareVariablesPresent '4/4' -FirmwareStateComplete $true -CloudChecked $true -AssociationPresent $true -AssociationState 'preassociated') },
    @{ Name='Associated'; Expected='Associated'; Severity='Information'; Status=(New-TestStatus -FirmwareVariablesPresent '4/4' -FirmwareStateComplete $true -CloudChecked $true -AssociationPresent $true -AssociationState 'associated') },
    @{ Name='AssociatedIncompleteFirmwareState'; Expected='AssociatedIncompleteFirmwareState'; Severity='Warning'; Status=(New-TestStatus -FirmwareVariablesPresent '2/4' -CloudChecked $true -AssociationPresent $true -AssociationState 'associated') },
    @{ Name='UnclassifiedAssociationState'; Expected='UnclassifiedAssociationState'; Severity='Warning'; Status=(New-TestStatus -FirmwareVariablesPresent '2/4' -CloudChecked $true -AssociationPresent $true -AssociationState 'futureState') }
)

foreach ($case in $cases) {
    $result = $case.Status | Test-WindowsDeviceLinkHealth
    if ($result.State -ne $case.Expected) {
        throw "FAIL: $($case.Name) expected state '$($case.Expected)', got '$($result.State)'."
    }
    if ($result.Severity -ne $case.Severity) {
        throw "FAIL: $($case.Name) expected severity '$($case.Severity)', got '$($result.Severity)'."
    }
    if ([string]::IsNullOrWhiteSpace($result.Summary) -or [string]::IsNullOrWhiteSpace($result.RecommendedAction)) {
        throw "FAIL: $($case.Name) returned an empty Summary or RecommendedAction."
    }
    Write-Host "PASS: $($case.Name) -> $($result.State) [$($result.Severity)]"
}

# Invariant: an associated device with incomplete known firmware must never be classified as healthy Associated.
$incompleteAssociated = New-TestStatus -FirmwareVariablesPresent '2/4' -CloudChecked $true -AssociationPresent $true -AssociationState 'associated'
$incompleteResult = $incompleteAssociated | Test-WindowsDeviceLinkHealth
if ($incompleteResult.State -eq 'Associated') {
    throw 'FAIL: associated + incomplete firmware was incorrectly classified as Associated.'
}

# Invariant: a cloud lookup error must not be interpreted as NotAssociated/LocalOnly.
$cloudFailure = New-TestStatus -FirmwareVariablesPresent '2/4' -CloudChecked $true -AssociationPresent $null -AssociationState 'Unknown' -AssociationError 'synthetic failure'
$cloudFailureResult = $cloudFailure | Test-WindowsDeviceLinkHealth
if ($cloudFailureResult.State -in @('LocalOnly','Preassociated','Associated')) {
    throw "FAIL: cloud lookup failure was incorrectly classified as '$($cloudFailureResult.State)'."
}

Write-Host ''
Write-Host "Health regression set passed: $($cases.Count) states plus invariants."
