<#
Deterministic Association JWT parser/validation tests.
Uses synthetic JWT fixtures only. No firmware or network access is required.
#>
[CmdletBinding()] param([string]$ModulePath)
$ErrorActionPreference='Stop'
function Assert-True { param([bool]$Condition,[string]$Message) if(-not $Condition){throw "FAIL: $Message"} }
if(-not $ModulePath){$ModulePath=Join-Path $PSScriptRoot '..\src\WindowsDeviceLink\WindowsDeviceLink.psd1'}
Remove-Module WindowsDeviceLink -Force -ErrorAction SilentlyContinue
Import-Module (Resolve-Path -LiteralPath $ModulePath).Path -Force -ErrorAction Stop
$module=Get-Module WindowsDeviceLink|Select-Object -First 1

function ConvertTo-Base64Url([byte[]]$Bytes){([Convert]::ToBase64String($Bytes).TrimEnd('=').Replace('+','-').Replace('/','_'))}
function New-JwtBytes {
    param([hashtable]$Payload,[string]$Algorithm='none')
    $header=@{alg=$Algorithm;typ='JWT'}|ConvertTo-Json -Compress
    $payloadJson=$Payload|ConvertTo-Json -Compress
    $h=ConvertTo-Base64Url ([Text.Encoding]::UTF8.GetBytes($header))
    $p=ConvertTo-Base64Url ([Text.Encoding]::UTF8.GetBytes($payloadJson))
    [Text.Encoding]::UTF8.GetBytes("$h.$p.sig")
}
function To-Epoch([datetimeoffset]$Utc){$Utc.ToUnixTimeSeconds()}

$linkId='0B1C094B-6443-4925-87B4-1F4809716E55'
$now=[datetimeoffset]::UtcNow

$validBytes=New-JwtBytes @{iat=(To-Epoch $now.AddMinutes(-2));nbf=(To-Epoch $now.AddMinutes(-1));exp=(To-Epoch $now.AddMinutes(30));linkId=$linkId}
$valid=& $module {param($Bytes,$LinkId) ConvertFrom-WindowsDeviceLinkAssociationJwtBytes -Bytes $Bytes -ExpectedLinkId $LinkId} $validBytes $linkId
Assert-True ($valid.State -eq 'Valid') "Expected Valid, got $($valid.State)."
Assert-True ($valid.IdentityClaimPresent -and $valid.IdentityMatch -eq $true) 'Valid fixture did not match LinkId.'
Assert-True ($valid.SignatureValidation -eq 'NotPerformed') 'Parser incorrectly claimed signature validation.'
Write-Host 'PASS: structurally/temporally valid JWT is classified without signature overclaim'

$expiredBytes=New-JwtBytes @{exp=(To-Epoch $now.AddMinutes(-1));linkId=$linkId}
$expired=& $module {param($Bytes,$LinkId) ConvertFrom-WindowsDeviceLinkAssociationJwtBytes -Bytes $Bytes -ExpectedLinkId $LinkId} $expiredBytes $linkId
Assert-True ($expired.State -eq 'Expired') "Expected Expired, got $($expired.State)."
Write-Host 'PASS: expired JWT is classified'

$futureBytes=New-JwtBytes @{nbf=(To-Epoch $now.AddMinutes(10));exp=(To-Epoch $now.AddMinutes(30));linkId=$linkId}
$future=& $module {param($Bytes,$LinkId) ConvertFrom-WindowsDeviceLinkAssociationJwtBytes -Bytes $Bytes -ExpectedLinkId $LinkId} $futureBytes $linkId
Assert-True ($future.State -eq 'NotYetValid') "Expected NotYetValid, got $($future.State)."
Write-Host 'PASS: not-yet-valid JWT is classified'

$mismatchBytes=New-JwtBytes @{exp=(To-Epoch $now.AddMinutes(30));linkId='11111111-1111-1111-1111-111111111111'}
$mismatch=& $module {param($Bytes,$LinkId) ConvertFrom-WindowsDeviceLinkAssociationJwtBytes -Bytes $Bytes -ExpectedLinkId $LinkId} $mismatchBytes $linkId
Assert-True ($mismatch.State -eq 'IdentityMismatch') "Expected IdentityMismatch, got $($mismatch.State)."
Write-Host 'PASS: LinkId mismatch is classified'

$secretMarker='RAW-JWT-SECRET-MARKER'
$malformedBytes=[Text.Encoding]::UTF8.GetBytes($secretMarker)
$malformed=& $module {param($Bytes) ConvertFrom-WindowsDeviceLinkAssociationJwtBytes -Bytes $Bytes} $malformedBytes
$serialized=$malformed|ConvertTo-Json -Compress
Assert-True ($malformed.State -eq 'Malformed') "Expected Malformed, got $($malformed.State)."
Assert-True (-not $serialized.Contains($secretMarker)) 'Malformed result leaked raw JWT input.'
Write-Host 'PASS: malformed JWT fails closed without raw input disclosure'

Write-Host ''
Write-Host 'Association JWT regression set passed.'
