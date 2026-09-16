<#
WindowsDeviceLink Microsoft Graph transport regression tests.

Hardware- and tenant-independent. These tests exercise the private read-only Graph
transport and collection paging helpers with deterministic module-scoped fakes.
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
& $module {
    $script:TransportAttempt = 0
    $script:SleepCalls = 0
    function Start-Sleep { param([double]$Seconds) $script:SleepCalls++ }
    function Invoke-RestMethod {
        param($Method,$Uri,$Headers,$ErrorAction)
        $script:TransportAttempt++
        if ($script:TransportAttempt -lt 3) { throw 'HTTP 503 Service Unavailable' }
        [pscustomobject]@{ value=@('ok') }
    }
}
$result = & $module { Invoke-WindowsDeviceLinkGraphGet -Uri 'https://graph.microsoft.com/beta/test' -AccessToken 'synthetic' -MaxAttempts 3 }
$attempts = & $module { $script:TransportAttempt }
$sleeps = & $module { $script:SleepCalls }
Assert-True ($attempts -eq 3) "503 retry expected 3 attempts, got $attempts."
Assert-True ($sleeps -eq 2) "503 retry expected 2 waits, got $sleeps."
Assert-True ($result.value[0] -eq 'ok') '503 retry did not return the eventual successful response.'
Write-Host 'PASS: transient 503 GET retries and returns eventual success'

# 429 is retryable for GET.
& $module {
    $script:TransportAttempt = 0
    $script:SleepCalls = 0
    function Invoke-RestMethod {
        param($Method,$Uri,$Headers,$ErrorAction)
        $script:TransportAttempt++
        if ($script:TransportAttempt -eq 1) { throw 'HTTP 429 Too Many Requests' }
        [pscustomobject]@{ value=@('ok') }
    }
}
$result = & $module { Invoke-WindowsDeviceLinkGraphGet -Uri 'https://graph.microsoft.com/beta/test' -AccessToken 'synthetic' -MaxAttempts 3 }
$attempts = & $module { $script:TransportAttempt }
Assert-True ($attempts -eq 2) "429 retry expected 2 attempts, got $attempts."
Write-Host 'PASS: throttled GET is retried'

# Authentication/authorization failures must not retry.
foreach ($code in @(401,403)) {
    & $module {
        param($StatusCode)
        $script:TransportAttempt = 0
        $script:TransportStatusCode = $StatusCode
        function Invoke-RestMethod {
            param($Method,$Uri,$Headers,$ErrorAction)
            $script:TransportAttempt++
            throw "HTTP $script:TransportStatusCode failure"
        }
    } $code
    Assert-Throws -Name "HTTP $code is not retried" -ExpectedMessage "HTTP $code" -ScriptBlock {
        & $module { Invoke-WindowsDeviceLinkGraphGet -Uri 'https://graph.microsoft.com/beta/test' -AccessToken 'synthetic' -MaxAttempts 3 }
    }
    $attempts = & $module { $script:TransportAttempt }
    Assert-True ($attempts -eq 1) "HTTP $code should have exactly one attempt; got $attempts."
}

# Paging: three pages, including an empty middle page, must preserve records.
& $module {
    $script:PageCalls = 0
    function Invoke-WindowsDeviceLinkGraphGet {
        param([string]$Uri,[string]$AccessToken,[switch]$SdkMode,[int]$MaxAttempts=3)
        $script:PageCalls++
        switch ($script:PageCalls) {
            1 { [pscustomobject]@{ value=@([pscustomobject]@{id='one'}); '@odata.nextLink'='https://graph.microsoft.com/beta/page2' } }
            2 { [pscustomobject]@{ value=@(); '@odata.nextLink'='https://graph.microsoft.com/beta/page3' } }
            3 { [pscustomobject]@{ value=@([pscustomobject]@{id='three'}) } }
            default { throw 'Unexpected extra page request.' }
        }
    }
}
$records = @(& $module { Get-WindowsDeviceLinkGraphCollection -Uri 'https://graph.microsoft.com/beta/page1' -AccessToken 'synthetic' })
Assert-True ($records.Count -eq 2) "three-page collection expected 2 records, got $($records.Count)."
Assert-True ($records[0].id -eq 'one' -and $records[1].id -eq 'three') 'paged records were not returned in order.'
Write-Host 'PASS: bounded paging follows multiple pages and tolerates an empty page'

# A repeated nextLink must stop instead of looping forever.
& $module {
    function Invoke-WindowsDeviceLinkGraphGet {
        param([string]$Uri,[string]$AccessToken,[switch]$SdkMode,[int]$MaxAttempts=3)
        [pscustomobject]@{ value=@(); '@odata.nextLink'='https://graph.microsoft.com/beta/loop' }
    }
}
Assert-Throws -Name 'Repeated nextLink is rejected' -ExpectedMessage 'repeated @odata.nextLink' -ScriptBlock {
    & $module { Get-WindowsDeviceLinkGraphCollection -Uri 'https://graph.microsoft.com/beta/loop' -AccessToken 'synthetic' }
}

# nextLink is server-provided input: never follow a different host or non-HTTPS URL.
& $module {
    function Invoke-WindowsDeviceLinkGraphGet {
        param([string]$Uri,[string]$AccessToken,[switch]$SdkMode,[int]$MaxAttempts=3)
        [pscustomobject]@{ value=@(); '@odata.nextLink'='https://example.invalid/steal-token' }
    }
}
Assert-Throws -Name 'Foreign nextLink host is rejected' -ExpectedMessage 'invalid or unexpected @odata.nextLink' -ScriptBlock {
    & $module { Get-WindowsDeviceLinkGraphCollection -Uri 'https://graph.microsoft.com/beta/page1' -AccessToken 'synthetic' }
}

Write-Host ''
Write-Host 'Graph transport regression set passed.'
