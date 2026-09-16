<#
WindowsDeviceLink firmware safety regression tests.

These tests are hardware-independent. They validate the isolated timestamp decoder and
verify that the public firmware cmdlet only invokes decoding for the explicitly safe
DeviceLinkCreationTimeUtc variable.
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

function Invoke-TimestampDecoder {
    param([AllowNull()][byte[]]$Bytes)
    & $module {
        param([byte[]]$InputBytes)
        ConvertFrom-WindowsDeviceLinkFirmwareTimestamp -Bytes $InputBytes
    } $Bytes
}

function ConvertTo-Utf8Bytes([string]$Value) {
    [Text.Encoding]::UTF8.GetBytes($Value)
}

$validCases = @(
    '2026-09-06T12:22:51Z',
    '2026-09-15T07:48:22.972Z',
    '2026-09-15T07:48:22.1Z',
    '2026-09-15T07:48:22.1234567Z'
)

foreach ($value in $validCases) {
    $result = Invoke-TimestampDecoder (ConvertTo-Utf8Bytes $value)
    Assert-True ($result.DecodedValue -eq $value) "valid timestamp '$value' was not returned unchanged."
    Assert-True ($null -ne $result.ParsedUtc) "valid timestamp '$value' was not parsed."
    Assert-True ($result.ParsedUtc.Kind -eq [DateTimeKind]::Utc) "valid timestamp '$value' did not parse as UTC."
    Write-Host "PASS: accepted safe timestamp $value"
}

$unsafeOrMalformed = @(
    '',
    '2026-09-15T07:48:22.12345678Z',
    '2026-09-15T07:48:22+00:00',
    '2026-09-15 07:48:22Z',
    '2026-13-99T99:99:99Z',
    'eyJhbGciOiJub25lIn0.eyJzZW5zaXRpdmUiOnRydWV9.signature',
    '0B1C094B-6443-4925-87B4-1F4809716E55',
    "2026-09-15T07:48:22Z`0SECRET"
)

foreach ($value in $unsafeOrMalformed) {
    $bytes = if ($value.Length -eq 0) { [byte[]]@() } else { ConvertTo-Utf8Bytes $value }
    $result = Invoke-TimestampDecoder $bytes
    Assert-True ($null -eq $result.DecodedValue) "unsafe/malformed value '$value' was decoded."
    Assert-True ($null -eq $result.ParsedUtc) "unsafe/malformed value '$value' produced ParsedUtc."
    Write-Host 'PASS: rejected unsafe/malformed firmware value'
}

$nullResult = Invoke-TimestampDecoder $null
Assert-True ($null -eq $nullResult.DecodedValue -and $null -eq $nullResult.ParsedUtc) 'null input must remain undisclosed.'
Write-Host 'PASS: null firmware value remains undisclosed'

# Static safety invariant: the public firmware reader may invoke the decoder only inside
# the DeviceLinkCreationTimeUtc branch. This protects DeviceLinkId/JWT variables from
# accidentally being routed through a decoder in a future refactor.
$moduleRoot = Split-Path -Parent $resolvedModulePath
$firmwareReaderPath = Join-Path $moduleRoot 'Public\Get-WindowsDeviceLinkFirmwareState.ps1'
$readerText = Get-Content -LiteralPath $firmwareReaderPath -Raw
$decoderCalls = [regex]::Matches($readerText, 'ConvertFrom-WindowsDeviceLinkFirmwareTimestamp').Count
Assert-True ($decoderCalls -eq 1) "firmware reader must contain exactly one timestamp-decoder call; found $decoderCalls."
Assert-True ($readerText -match '\$name\s+-eq\s+''DeviceLinkCreationTimeUtc''') 'timestamp decoder is not guarded by the DeviceLinkCreationTimeUtc variable name.'
Write-Host 'PASS: public firmware reader decodes only DeviceLinkCreationTimeUtc'

Write-Host ''
Write-Host 'Firmware safety regression set passed.'
