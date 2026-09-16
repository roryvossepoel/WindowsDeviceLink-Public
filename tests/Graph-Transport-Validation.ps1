<#
WindowsDeviceLink Microsoft Graph transport regression tests.
Hardware- and tenant-independent. Test-only scriptblock seams ensure CI never performs real network requests.
#>
[CmdletBinding()] param([string]$ModulePath)
$ErrorActionPreference='Stop'
function Assert-True { param([bool]$Condition,[string]$Message) if(-not $Condition){throw "FAIL: $Message"} }
function Assert-Throws { param([string]$Name,[scriptblock]$ScriptBlock,[string]$ExpectedMessage) try{& $ScriptBlock;throw "FAIL: $Name - expected an exception but none was thrown."}catch{if($_.Exception.Message -notlike "*$ExpectedMessage*"){throw "FAIL: $Name - expected '$ExpectedMessage', got '$($_.Exception.Message)'."};Write-Host "PASS: $Name"} }
if(-not $ModulePath){$ModulePath=Join-Path $PSScriptRoot '..\src\WindowsDeviceLink\WindowsDeviceLink.psd1'}
$resolvedModulePath=(Resolve-Path -LiteralPath $ModulePath).Path
Remove-Module WindowsDeviceLink -Force -ErrorAction SilentlyContinue;Import-Module $resolvedModulePath -Force -ErrorAction Stop
$module=Get-Module WindowsDeviceLink|Select-Object -First 1;if(-not $module){throw 'FAIL: WindowsDeviceLink did not load.'}

# GET retries are limited to idempotent reads. Exercise retryable HTTP and transport failures.
foreach($case in @(
    @{Name='HTTP 429';Message='HTTP 429 Too Many Requests';Failures=1;ExpectedAttempts=2},
    @{Name='HTTP 500';Message='HTTP 500 Internal Server Error';Failures=1;ExpectedAttempts=2},
    @{Name='HTTP 502';Message='HTTP 502 Bad Gateway';Failures=1;ExpectedAttempts=2},
    @{Name='HTTP 503';Message='HTTP 503 Service Unavailable';Failures=2;ExpectedAttempts=3},
    @{Name='HTTP 504';Message='HTTP 504 Gateway Timeout';Failures=1;ExpectedAttempts=2},
    @{Name='timeout';Message='The operation timed out.';Failures=1;ExpectedAttempts=2},
    @{Name='connection closed';Message='The connection was closed unexpectedly.';Failures=1;ExpectedAttempts=2}
)){
    $state=[pscustomobject]@{Attempts=0;Sleeps=0}
    $message=$case.Message;$failures=$case.Failures
    $request={param($Uri,$SdkMode,$AccessToken)$state.Attempts++;if($state.Attempts -le $failures){throw $message};[pscustomobject]@{value=@('ok')}}.GetNewClosure()
    $sleep={param($Seconds)$state.Sleeps++}.GetNewClosure()
    $result=& $module {param($Request,$Sleep)Invoke-WindowsDeviceLinkGraphGet -Uri 'https://graph.microsoft.com/beta/test' -AccessToken 'synthetic' -MaxAttempts 3 -RequestScript $Request -SleepScript $Sleep} $request $sleep
    Assert-True ($state.Attempts -eq $case.ExpectedAttempts) "$($case.Name) expected $($case.ExpectedAttempts) attempts, got $($state.Attempts)."
    Assert-True ($state.Sleeps -eq ($case.ExpectedAttempts-1)) "$($case.Name) wait count is incorrect."
    Assert-True ($result.value[0] -eq 'ok') "$($case.Name) did not return eventual success."
    Write-Host "PASS: transient GET retry - $($case.Name)"
}

# Authentication, authorization, not-found and conflict failures are not transient and must not retry.
foreach($code in @(401,403,404,409)){
    $state=[pscustomobject]@{Attempts=0};$message="HTTP $code failure"
    $request={param($Uri,$SdkMode,$AccessToken)$state.Attempts++;throw $message}.GetNewClosure()
    Assert-Throws -Name "HTTP $code is not retried" -ExpectedMessage "HTTP $code" -ScriptBlock {& $module {param($Request)Invoke-WindowsDeviceLinkGraphGet -Uri 'https://graph.microsoft.com/beta/test' -AccessToken 'synthetic' -MaxAttempts 3 -RequestScript $Request} $request}
    Assert-True ($state.Attempts -eq 1) "HTTP $code should have exactly one attempt; got $($state.Attempts)."
}

# Paging over three pages, including an empty middle page.
$request={param($Uri,$SdkMode,$AccessToken)switch($Uri){
    'https://graph.microsoft.com/beta/page1'{[pscustomobject]@{value=@([pscustomobject]@{id='one'});'@odata.nextLink'='https://graph.microsoft.com/beta/page2'}}
    'https://graph.microsoft.com/beta/page2'{[pscustomobject]@{value=@();'@odata.nextLink'='https://graph.microsoft.com/beta/page3'}}
    'https://graph.microsoft.com/beta/page3'{[pscustomobject]@{value=@([pscustomobject]@{id='three'})}}
    default{throw "Unexpected page URI: $Uri"}
}}
$records=@(& $module {param($Request)Get-WindowsDeviceLinkGraphCollection -Uri 'https://graph.microsoft.com/beta/page1' -AccessToken 'synthetic' -RequestScript $Request} $request)
Assert-True ($records.Count -eq 2) "three-page collection expected 2 records, got $($records.Count)."
Assert-True ($records[0].id -eq 'one' -and $records[1].id -eq 'three') 'paged records were not returned in order.'
Write-Host 'PASS: bounded paging follows multiple pages and tolerates an empty value array'

# A null response is indeterminate, never a confirmed empty collection.
$request={param($Uri,$SdkMode,$AccessToken)$null}
Assert-Throws -Name 'Null collection response is rejected' -ExpectedMessage 'empty response' -ScriptBlock {& $module {param($Request)Get-WindowsDeviceLinkGraphCollection -Uri 'https://graph.microsoft.com/beta/test' -AccessToken 'synthetic' -RequestScript $Request} $request}

# OData collection responses must contain a non-null value property. Missing/malformed
# response shape must not become confirmed NotAssociated higher in the call chain.
$request={param($Uri,$SdkMode,$AccessToken)[pscustomobject]@{'@odata.context'='synthetic'}}
Assert-Throws -Name 'Missing collection value property is rejected' -ExpectedMessage "required 'value' property is missing" -ScriptBlock {& $module {param($Request)Get-WindowsDeviceLinkGraphCollection -Uri 'https://graph.microsoft.com/beta/test' -AccessToken 'synthetic' -RequestScript $Request} $request}

$request={param($Uri,$SdkMode,$AccessToken)[pscustomobject]@{value=$null}}
Assert-Throws -Name 'Null collection value property is rejected' -ExpectedMessage "required 'value' property is null" -ScriptBlock {& $module {param($Request)Get-WindowsDeviceLinkGraphCollection -Uri 'https://graph.microsoft.com/beta/test' -AccessToken 'synthetic' -RequestScript $Request} $request}

# A repeated nextLink must stop instead of looping forever.
$request={param($Uri,$SdkMode,$AccessToken)[pscustomobject]@{value=@();'@odata.nextLink'='https://graph.microsoft.com/beta/loop'}}
Assert-Throws -Name 'Repeated nextLink is rejected' -ExpectedMessage 'repeated @odata.nextLink' -ScriptBlock {& $module {param($Request)Get-WindowsDeviceLinkGraphCollection -Uri 'https://graph.microsoft.com/beta/loop' -AccessToken 'synthetic' -RequestScript $Request} $request}

# Server-provided nextLink must never move bearer-token traffic to another host.
$request={param($Uri,$SdkMode,$AccessToken)[pscustomobject]@{value=@();'@odata.nextLink'='https://example.invalid/steal-token'}}
Assert-Throws -Name 'Foreign nextLink host is rejected' -ExpectedMessage 'invalid or unexpected @odata.nextLink' -ScriptBlock {& $module {param($Request)Get-WindowsDeviceLinkGraphCollection -Uri 'https://graph.microsoft.com/beta/page1' -AccessToken 'synthetic' -RequestScript $Request} $request}

# Paging has a hard upper bound even if every nextLink is unique.
$request={param($Uri,$SdkMode,$AccessToken)
    $page=[int](($Uri -split 'page')[-1])
    [pscustomobject]@{value=@();'@odata.nextLink'="https://graph.microsoft.com/beta/page$($page+1)"}
}
Assert-Throws -Name 'Page safety limit is enforced' -ExpectedMessage 'safety limit of 2 pages' -ScriptBlock {& $module {param($Request)Get-WindowsDeviceLinkGraphCollection -Uri 'https://graph.microsoft.com/beta/page1' -AccessToken 'synthetic' -MaxPages 2 -RequestScript $Request} $request}

Write-Host '';Write-Host 'Graph transport regression set passed.'
