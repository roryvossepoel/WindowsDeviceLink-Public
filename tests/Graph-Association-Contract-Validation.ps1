<#
WindowsDeviceLink Graph Device Association contract regression tests.
Hardware- and tenant-independent. Exercises private response normalization, serial
resolution and native registration error handling without real network activity.
#>
[CmdletBinding()] param([string]$ModulePath)
$ErrorActionPreference='Stop'

function Assert-True { param([bool]$Condition,[string]$Message) if(-not $Condition){throw "FAIL: $Message"} }
function Assert-Throws {
    param([string]$Name,[scriptblock]$ScriptBlock,[string]$ExpectedMessage)
    try { & $ScriptBlock; throw "FAIL: $Name - expected an exception but none was thrown." }
    catch {
        if($_.Exception.Message -notlike "*$ExpectedMessage*"){throw "FAIL: $Name - expected '$ExpectedMessage', got '$($_.Exception.Message)'."}
        Write-Host "PASS: $Name"
    }
}

if(-not $ModulePath){$ModulePath=Join-Path $PSScriptRoot '..\src\WindowsDeviceLink\WindowsDeviceLink.psd1'}
$resolvedModulePath=(Resolve-Path -LiteralPath $ModulePath).Path
Remove-Module WindowsDeviceLink -Force -ErrorAction SilentlyContinue
Import-Module $resolvedModulePath -Force -ErrorAction Stop
$module=Get-Module WindowsDeviceLink|Select-Object -First 1
if(-not $module){throw 'FAIL: WindowsDeviceLink did not load.'}

function Convert-AssociationRecord {
    param([AllowNull()][psobject]$Record,[string]$ExpectedId,[string]$ExpectedSerial,[string]$ResultType='Association')
    & $module {
        param($Raw,$Id,$Serial,$Type)
        $params=@{Record=$Raw;TenantId='tenant-test';ResultType=$Type}
        if($Id){$params.ExpectedAssociationId=$Id}
        if($Serial){$params.ExpectedSerialNumber=$Serial}
        ConvertTo-WindowsDeviceLinkAssociationResult @params
    } $Record $ExpectedId $ExpectedSerial $ResultType
}

function Resolve-SerialRecords {
    param([object[]]$Records,[string]$Serial,[switch]$RequireComplete)
    & $module {
        param($Raw,$SerialValue,$Require)
        $params=@{Records=$Raw;SerialNumber=$SerialValue}
        if($Require){$params.RequireCompleteSerialCoverage=$true}
        @(Resolve-WindowsDeviceLinkSerialAssociationRecords @params)
    } $Records $Serial ([bool]$RequireComplete)
}

function Invoke-SyntheticRegistration {
    param([scriptblock]$Request)
    & $module {
        param($RequestScript)
        $inputObject=[pscustomobject]@{SerialNumber='TEST-SERIAL';DeviceLink='synthetic-device-link'}
        $inputObject.PSObject.TypeNames.Insert(0,'Windows.DeviceLink.Information')
        Invoke-WindowsDeviceLinkGraphRegistration `
            -InputObject $inputObject `
            -AccessToken 'synthetic-token' `
            -TenantId 'tenant-test' `
            -RequestScript $RequestScript
    } $Request
}

$validId='11111111-1111-1111-1111-111111111111'
$zeroGuid=[guid]::Empty.ToString()

# Missing optional properties are valid and remain null.
$minimal=[pscustomobject]@{id=$validId;serialNumber='TEST-SERIAL';associationState='preassociated'}
$result=Convert-AssociationRecord -Record $minimal -ExpectedSerial 'TEST-SERIAL'
Assert-True ($result.Id -eq $validId) 'minimal record ID was not preserved.'
Assert-True ($result.AssociationState -eq 'preassociated') 'minimal record associationState was not preserved.'
Assert-True ($null -eq $result.ManagedDeviceId) 'missing managedDeviceId must remain null.'
Assert-True ($null -eq $result.DevicePreparationPolicyId) 'missing devicePreparationPolicyId must remain null.'
Write-Host 'PASS: missing optional association properties remain safe nulls'

# Empty/zero optional GUID-like values use Graph sentinel semantics and normalize to null.
$sentinel=[pscustomobject]@{id=$validId;serialNumber='TEST-SERIAL';associationState='preassociated';managedDeviceId=$zeroGuid;devicePreparationPolicyId=''}
$result=Convert-AssociationRecord -Record $sentinel
Assert-True ($null -eq $result.ManagedDeviceId) 'zero managedDeviceId must normalize to null.'
Assert-True ($null -eq $result.DevicePreparationPolicyId) 'empty devicePreparationPolicyId must normalize to null.'
Write-Host 'PASS: empty/zero optional GUID-like values normalize to null'

# Graph/.NET minimum date sentinels mean the optional lifecycle date is not populated yet.
$dateSentinel=[pscustomobject]@{
    id=$validId;serialNumber='TEST-SERIAL';associationState='preassociated'
    preassociationDateTime='2026-09-15T15:27:07.9458446Z'
    associationDateTime='0001-01-01T00:00:00Z'
    enrolledDateTime='0001-01-01T00:00:00Z'
    lastContactedDateTime='0001-01-01T00:00:00Z'
    devicePreparationPolicyAssignedDateTime='0001-01-01T00:00:00Z'
}
$result=Convert-AssociationRecord -Record $dateSentinel
Assert-True ($result.PreassociationDateTime -eq '2026-09-15T15:27:07.9458446Z') 'real preassociation date must remain unchanged.'
Assert-True ($null -eq $result.AssociationDateTime) 'minimum associationDateTime sentinel must normalize to null.'
Assert-True ($null -eq $result.EnrolledDateTime) 'minimum enrolledDateTime sentinel must normalize to null.'
Assert-True ($null -eq $result.LastContactedDateTime) 'minimum lastContactedDateTime sentinel must normalize to null.'
Assert-True ($null -eq $result.DevicePreparationPolicyAssignedDateTime) 'minimum policy-assigned date sentinel must normalize to null.'
Write-Host 'PASS: minimum lifecycle date sentinels normalize to null'

# Required association identity/state must never silently degrade.
Assert-Throws -Name 'Zero association ID is rejected' -ExpectedMessage 'association ID is missing or empty' -ScriptBlock {
    Convert-AssociationRecord -Record ([pscustomobject]@{id=$zeroGuid;serialNumber='TEST-SERIAL';associationState='preassociated'})
}
Assert-Throws -Name 'Missing association state is rejected' -ExpectedMessage 'associationState is missing or empty' -ScriptBlock {
    Convert-AssociationRecord -Record ([pscustomobject]@{id=$validId;serialNumber='TEST-SERIAL'})
}
Assert-Throws -Name 'Exact ID mismatch is rejected' -ExpectedMessage 'mismatched Device Association record' -ScriptBlock {
    Convert-AssociationRecord -Record $minimal -ExpectedId '22222222-2222-2222-2222-222222222222'
}
Assert-Throws -Name 'Expected serial mismatch is rejected' -ExpectedMessage 'mismatched Device Association record' -ScriptBlock {
    Convert-AssociationRecord -Record $minimal -ExpectedSerial 'OTHER-SERIAL'
}

# New/future association states are preserved explicitly for the health layer to classify conservatively.
$future=Convert-AssociationRecord -Record ([pscustomobject]@{id=$validId;serialNumber='TEST-SERIAL';associationState='futureState'})
Assert-True ($future.AssociationState -eq 'futureState') 'future association state should be preserved, not coerced.'
Write-Host 'PASS: future association state remains explicit'

# Serial matching is exact and duplicates are an error rather than an arbitrary selection.
$records=@(
    [pscustomobject]@{id='a';serialNumber='OTHER'},
    [pscustomobject]@{id='b';serialNumber='TEST-SERIAL'}
)
$matches=@(Resolve-SerialRecords -Records $records -Serial 'TEST-SERIAL')
Assert-True ($matches.Count -eq 1 -and $matches[0].id -eq 'b') 'serial resolver did not return the unique exact match.'
Write-Host 'PASS: serial resolver returns one exact match'

$duplicates=@(
    [pscustomobject]@{id='a';serialNumber='TEST-SERIAL'},
    [pscustomobject]@{id='b';serialNumber='TEST-SERIAL'}
)
Assert-Throws -Name 'Duplicate serial matches are rejected' -ExpectedMessage 'Multiple Device Association records' -ScriptBlock {
    Resolve-SerialRecords -Records $duplicates -Serial 'TEST-SERIAL'
}

# Full enumeration cannot prove absence if Graph omitted serialNumber on any record.
$incomplete=@(
    [pscustomobject]@{id='a';serialNumber='OTHER'},
    [pscustomobject]@{id='b';serialNumber=$null}
)
Assert-Throws -Name 'Incomplete serial coverage cannot confirm absence' -ExpectedMessage 'cannot be confirmed safely' -ScriptBlock {
    Resolve-SerialRecords -Records $incomplete -Serial 'TEST-SERIAL' -RequireComplete
}

$completeNoMatch=@([pscustomobject]@{id='a';serialNumber='OTHER'})
$matches=@(Resolve-SerialRecords -Records $completeNoMatch -Serial 'TEST-SERIAL' -RequireComplete)
Assert-True ($matches.Count -eq 0) 'complete non-matching enumeration should confirm zero exact matches.'
Write-Host 'PASS: complete serial coverage can confirm absence'

# Native registration transport has deterministic 409 handling and validates its response.
$conflictRequest={param($Uri,$Body,$AccessToken)throw 'HTTP 409 Conflict'}
Assert-Throws -Name 'Registration 409 returns actionable conflict error' -ExpectedMessage 'pre-association already exists or conflicts' -ScriptBlock {
    Invoke-SyntheticRegistration -Request $conflictRequest
}

$emptyRequest={param($Uri,$Body,$AccessToken)$null}
Assert-Throws -Name 'Empty registration response is indeterminate' -ExpectedMessage 'empty Device Association response' -ScriptBlock {
    Invoke-SyntheticRegistration -Request $emptyRequest
}

$successRequest={param($Uri,$Body,$AccessToken)[pscustomobject]@{id='33333333-3333-3333-3333-333333333333';serialNumber='TEST-SERIAL';associationState='preassociated';managedDeviceId='00000000-0000-0000-0000-000000000000'}}
$registration=Invoke-SyntheticRegistration -Request $successRequest
Assert-True ($registration.PSObject.TypeNames -contains 'Windows.DeviceLink.Registration') 'registration result type is incorrect.'
Assert-True ($registration.AssociationState -eq 'preassociated') 'registration state was not preserved.'
Assert-True ($null -eq $registration.ManagedDeviceId) 'registration zero managedDeviceId should normalize to null.'
Write-Host 'PASS: native registration response is normalized and validated'

Write-Host ''
Write-Host 'Graph Device Association contract regression set passed.'
