<#
WindowsDeviceLink Microsoft Graph transport regression tests.

Hardware- and tenant-independent. The private transport helpers expose test-only
scriptblock seams so CI never performs real network requests.
#>

[CmdletBinding()]
param([string]$ModulePath)

$ErrorActionPreference = 'Stop'

function Assert-True {
    param([bool]$Condition,[string]$Message)
    if (-not $Condition) { throw "FAIL: $Message" }
}

function Assert-Throws {
    param([string]$Name,[scriptblock]$ScriptBlock,[string]$ExpectedMessage)
    try {
        & $ScriptBlock
        throw "FAIL: $Name - expected an exception but none was thrown."
    }
    catch {
        if ($_.Exception.Message -notlike "*$ExpectedMessage*") {
            throw "FAIL: $Name - expected '$ExpectedMessage', got '$($_.Exception.Message)'."
        }
        Write-Host "PASS: $Name"
    }
}

if (-not $ModulePath) { $ModulePath = Join-Path $PSScriptRoot '..\src\WindowsDeviceLink\WindowsDeviceLink.psd1' }
$resolvedModulePath = (Resolve-Path -LiteralPath $ModulePath).Path
Remove-Module WindowsDeviceLink -Force -ErrorAction SilentlyContinue
Import-Module $resolvedModulePath -Force -ErrorAction Stop
$module = Get-Module WindowsDeviceLink | Select-Object -First 1
if (-not $module) { throw 'FAIL: WindowsDeviceLink did not load.' }

# 503 -> 503 -> success: GET is idempotent and may retry.
$state = [pscustomobject]@{ Attempts=0; Sleeps=0 }
$request = {
    param($Uri,$SdkMode,$AccessToken)
    $state.Attempts++
    if ($state.Attempts -lt 3) { throw 'HTTP 503 Service Unavailable' }
    [pscustomobject]@{ value=@('ok') }
}.GetNewClosure()
$sleep = { param($Seconds) $state.Sleeps++ }.GetNewClosure()
$result = & $module { param($Request,$Sleep) Invoke-WindowsDeviceLinkGraphGet -Uri 'https://graph.microsoft.com/beta/test' -AccessToken 'synthetic' -MaxAttempts 3 -RequestScript $Request -SleepScript $Sleep } $request $sleep
Assert-True ($state.Attempts -eq 3) "503 retry expected 3 attempts, got $($state.Attempts)."
Assert-True ($state.Sleeps -eq 2) "503 retry expected 2 waits, got $($state.Sleeps)."
Assert-True ($result.value[0] -eq 'ok') '503 retry did not return the eventual successful response.'
Write-Host 'PASS: transient 503 GET retries and returns eventual success'

# 429 is retryable for GET.
$state = [pscustomobject]@{ Attempts=0; Sleeps=0 }
$request = {
    param($Uri,$SdkMode,$AccessToken)
    $state.Attempts++
    if ($state.Attempts -eq 1) { throw 'HTTP 429 Too Many Requests' }
    [pscustomobject]@{ value=@('ok') }
}.GetNewClosure()
$sleep = { param($Seconds) $state.Sleeps++ }.GetNewClosure()
$result = & $module { param($Request,$Sleep) Invoke-WindowsDeviceLinkGraphGet -Uri 'https://graph.microsoft.com/beta/test' -AccessToken 'synthetic' -MaxAttempts 3 -RequestScript $Request -SleepScript $Sleep } $request $sleep
Assert-True ($state.Attempts -eq 2) "429 retry expected 2 attempts, got $($state.Attempts)."
Assert-True ($state.Sleeps -eq 1) "429 retry expected 1 wait, got $($state.Sleeps)."
Write-Host 'PASS: throttled GET is retried'

# Authentication/authorization failures must not retry.
foreach ($code in @(401,403)) {
    $state = [pscustomobject]@{ Attempts=0 }
    $request = {
        param($Uri,$SdkMode,$AccessToken)
        $state.Attempts++
        throw "HTTP $code failure"
    }.GetNewClosure()
    Assert-Throws -Name "HTTP $code is not retried" -ExpectedMessage "HTTP $code" -ScriptBlock {
        & $module { param($Request) Invoke-WindowsDeviceLinkGraphGet -Uri 'https://graph.microsoft.com/beta/test' -AccessToken 'synthetic' -MaxAttempts 3 -RequestScript $Request } $request
    }
    Assert-True ($state.Attempts -eq 1) "HTTP $code should have exactly one attempt; got $($state.Attempts)."
}

# Paging: three pages, including an empty middle page, must preserve records.
$request = {
    param($Uri,$SdkMode,$AccessToken)
    switch ($Uri) {
        'https://graph.microsoft.com/beta/page1' { [pscustomobject]@{ value=@([pscustomobject]@{id='one'}); '@odata.nextLink'='https://graph.microsoft.com/beta/page2' } }
        'https://graph.microsoft.com/beta/page2' { [pscustomobject]@{ value=@(); '@odata.nextLink'='https://graph.microsoft.com/beta/page3' } }
        'https://graph.microsoft.com/beta/page3' { [pscustomobject]@{ value=@([pscustomobject]@{id='three'}) } }
        default { throw "Unexpected page URI: $Uri" }
    }
}
$records = @(& $module { param($Request) Get-WindowsDeviceLinkGraphCollection -Uri 'https://graph.microsoft.com/beta/page1' -AccessToken 'synthetic' -RequestScript $Request } $request)
Assert-True ($records.Count -eq 2) "three-page collection expected 2 records, got $($records.Count)."
Assert-True ($records[0].id -eq 'one' -and $records[1].id -eq 'three') 'paged records were not returned in order.'
Write-Host 'PASS: bounded paging follows multiple pages and tolerates an empty page'

# A repeated nextLink must stop instead of looping forever.
$request = { param($Uri,$SdkMode,$AccessToken) [pscustomobject]@{ value=@(); '@odata.nextLink'='https://graph.microsoft.com/beta/loop' } }
Assert-Throws -Name 'Repeated nextLink is rejected' -ExpectedMessage 'repeated @odata.nextLink' -ScriptBlock {
    & $module { param($Request) Get-WindowsDeviceLinkGraphCollection -Uri 'https://graph.microsoft.com/beta/loop' -AccessToken 'synthetic' -RequestScript $Request } $request
}

# nextLink is server-provided input: never follow a different host or non-HTTPS URL.
$request = { param($Uri,$SdkMode,$AccessToken) [pscustomobject]@{ value=@(); '@odata.nextLink'='https://example.invalid/steal-token' } }
Assert-Throws -Name 'Foreign nextLink host is rejected' -ExpectedMessage 'invalid or unexpected @odata.nextLink' -ScriptBlock {
    & $module { param($Request) Get-WindowsDeviceLinkGraphCollection -Uri 'https://graph.microsoft.com/beta/page1' -AccessToken 'synthetic' -RequestScript $Request } $request
}

Write-Host ''
Write-Host 'Graph transport regression set passed.'
