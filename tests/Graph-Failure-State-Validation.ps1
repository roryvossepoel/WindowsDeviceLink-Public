<#
WindowsDeviceLink Graph failure-state regression tests.

These tests are hardware- and tenant-independent. They replace selected module-scoped
functions with deterministic synthetic implementations and verify the critical safety
invariant that a failed/indeterminate cloud lookup can never become confirmed
NotAssociated/LocalOnly or trigger Initialize-WindowsDeviceLink registration.
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

# Replace hardware-dependent operations with deterministic local state: supported,
# valid DeviceLink identity, and the observed/valid 2-of-4 base firmware state.
& $module {
    function Test-WindowsDeviceLinkSupport {
        [CmdletBinding()]
        param([string]$WindowsManagementServicePath)
        [pscustomobject]@{
            Environment='Test'; Architecture='AMD64'; Supported=$true; Reason=$null
            DllSource='Synthetic'; ActivationMode='Synthetic'; DllPath=$null; DllVersion=$null
        }
    }

    function Get-WindowsDeviceLink {
        [CmdletBinding()]
        param([int]$TimeoutSeconds=120,[string]$WindowsManagementServicePath)
        $result = [pscustomobject]@{
            SerialNumber='TEST-SERIAL'; Manufacturer='Test'; Model='Test'; SmbiosUuid='00000000-0000-0000-0000-000000000003'
            LinkId='00000000-0000-0000-0000-000000000001'; PayloadCreationTimeUtc=[datetime]'2026-01-01T00:00:00Z'; DeviceLink='SYNTHETIC'
        }
        $result.PSObject.TypeNames.Insert(0,'Windows.DeviceLink.Information')
        $result
    }

    function Get-WindowsDeviceLinkFirmwareState {
        [CmdletBinding()]
        param()
        foreach ($item in @(
            @{Name='DeviceLinkId';Present=$true},
            @{Name='DeviceLinkJwtCompressed';Present=$false},
            @{Name='DeviceLinkJwtLastWrite';Present=$false},
            @{Name='DeviceLinkCreationTimeUtc';Present=$true}
        )) {
            [pscustomobject]@{
                PSTypeName='Windows.DeviceLink.FirmwareState'; Environment='Test'; Namespace='Synthetic'; Name=$item.Name
                Present=$item.Present; Size=if($item.Present){20}else{0}; DecodedValue=$null
                ParsedUtc=if($item.Name -eq 'DeviceLinkCreationTimeUtc' -and $item.Present){[datetime]'2026-01-01T00:00:00Z'}else{$null}
                LastError=$null
            }
        }
    }

    $script:GraphFailureMessage = $null
    $script:GraphFailureRegistrationCalls = 0

    function Get-WindowsDeviceLinkAssociation {
        [CmdletBinding()]
        param(
            [string]$AssociationId,[string]$SerialNumber,[string]$Method,[string]$TenantId,[string]$ClientId,
            [securestring]$AccessToken,[object]$Certificate,[string]$CertificateThumbprint,[string]$CertificateSubjectName,
            [bool]$SendCertificateChain=$false,[securestring]$ClientSecret,[string]$Environment='Global',[double]$ClientTimeout=100
        )
        throw $script:GraphFailureMessage
    }

    function Register-WindowsDeviceLink {
        [CmdletBinding(SupportsShouldProcess)]
        param(
            [Parameter(ValueFromPipeline)][psobject]$InputObject,[string]$Method,[string]$TenantId,[string]$ClientId,
            [securestring]$AccessToken,[object]$Certificate,[string]$CertificateThumbprint,[string]$CertificateSubjectName,
            [bool]$SendCertificateChain=$false,[securestring]$ClientSecret,[string]$Environment='Global',[double]$ClientTimeout=100
        )
        $script:GraphFailureRegistrationCalls++
        throw 'FAIL: registration must never be called while cloud state is indeterminate.'
    }
}

$tenantId = '00000000-0000-0000-0000-000000000010'
$accessToken = ConvertTo-SecureString 'synthetic-token-never-sent' -AsPlainText -Force

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
    & $module { param($Message) $script:GraphFailureMessage = $Message; $script:GraphFailureRegistrationCalls = 0 } $failure

    $status = Get-WindowsDeviceLinkStatus -Online -Method AccessToken -TenantId $tenantId -AccessToken $accessToken
    Assert-True ($status.CloudChecked -eq $true) "'$failure': CloudChecked must be true."
    Assert-True ($null -eq $status.AssociationPresent) "'$failure': AssociationPresent must remain null/unknown, not false."
    Assert-True ($status.AssociationState -eq 'Unknown') "'$failure': AssociationState must be Unknown."
    Assert-True (-not [string]::IsNullOrWhiteSpace($status.AssociationError)) "'$failure': AssociationError must be populated."

    $health = $status | Test-WindowsDeviceLinkHealth
    Assert-True ($health.State -eq 'CloudUnknown') "'$failure': health must be CloudUnknown, got '$($health.State)'."
    Assert-True ($health.State -notin @('LocalOnly','Preassociated','Associated')) "'$failure': cloud failure became a confirmed lifecycle state."

    $initialize = Initialize-WindowsDeviceLink -Method AccessToken -TenantId $tenantId -AccessToken $accessToken -Confirm:$false
    Assert-True ($initialize.Action -eq 'Blocked') "'$failure': initializer must be Blocked, got '$($initialize.Action)'."
    Assert-True ($initialize.Changed -eq $false) "'$failure': initializer reported a change."
    Assert-True ($initialize.BeforeState -eq 'CloudUnknown') "'$failure': initializer BeforeState must be CloudUnknown."

    $registrationCalls = & $module { $script:GraphFailureRegistrationCalls }
    Assert-True ($registrationCalls -eq 0) "'$failure': registration was invoked $registrationCalls time(s)."

    Write-Host "PASS: fail-safe cloud state - $failure"
}

# Positive control: a successful lookup that returns no records is the only case here
# that may become confirmed NotAssociated/LocalOnly.
& $module {
    function Get-WindowsDeviceLinkAssociation {
        [CmdletBinding()]
        param(
            [string]$AssociationId,[string]$SerialNumber,[string]$Method,[string]$TenantId,[string]$ClientId,
            [securestring]$AccessToken,[object]$Certificate,[string]$CertificateThumbprint,[string]$CertificateSubjectName,
            [bool]$SendCertificateChain=$false,[securestring]$ClientSecret,[string]$Environment='Global',[double]$ClientTimeout=100
        )
        return
    }
}

$notAssociated = Get-WindowsDeviceLinkStatus -Online -Method AccessToken -TenantId $tenantId -AccessToken $accessToken
Assert-True ($notAssociated.AssociationPresent -eq $false) 'successful empty lookup must report AssociationPresent=False.'
Assert-True ($notAssociated.AssociationState -eq 'NotAssociated') 'successful empty lookup must report NotAssociated.'
Assert-True ([string]::IsNullOrWhiteSpace($notAssociated.AssociationError)) 'successful empty lookup must not report AssociationError.'
$notAssociatedHealth = $notAssociated | Test-WindowsDeviceLinkHealth
Assert-True ($notAssociatedHealth.State -eq 'LocalOnly') "successful empty lookup expected LocalOnly, got '$($notAssociatedHealth.State)'."
Write-Host 'PASS: successful empty lookup remains distinct from Graph failure'

Write-Host ''
Write-Host 'Graph failure-state regression set passed.'
