<#
Validates native Graph DELETE error redaction through the production transport helper.
No Graph request is sent.
#>
[CmdletBinding()] param([string]$ModulePath)
$ErrorActionPreference='Stop'
if(-not $ModulePath){$ModulePath=Join-Path $PSScriptRoot '..\src\WindowsDeviceLink\WindowsDeviceLink.psd1'}
Remove-Module WindowsDeviceLink -Force -ErrorAction SilentlyContinue
Import-Module (Resolve-Path -LiteralPath $ModulePath).Path -Force -ErrorAction Stop
$module=Get-Module WindowsDeviceLink|Select-Object -First 1

$marker='WDL-DELETE-ACCESS-TOKEN'
$request={param($Uri,$SdkMode,$AccessToken)throw "HTTP 403 Authorization: Bearer $AccessToken"}
try {
    & $module {param($Request,$Token)Invoke-WindowsDeviceLinkGraphDelete -Uri 'https://graph.microsoft.com/beta/deviceManagement/tenantAssociatedDevices/test' -AccessToken $Token -RequestScript $Request} $request $marker
    throw 'FAIL: DELETE helper expected an exception.'
}
catch {
    $message=[string]$_.Exception.Message
    if($message -notlike '*HTTP 403*'){throw "FAIL: DELETE error lost HTTP context: $message"}
    if($message.Contains($marker)){throw 'FAIL: DELETE error leaked bearer token.'}
    Write-Host 'PASS: Graph DELETE transport error redacts bearer token'
}

# Static wiring guard: the public removal command must use the hardened DELETE helper.
$command=(Get-Command Remove-WindowsDeviceLinkAssociation -Module WindowsDeviceLink).ScriptBlock.ToString()
if($command -notmatch 'Invoke-WindowsDeviceLinkGraphDelete'){throw 'FAIL: public removal command is not wired to the hardened DELETE helper.'}
Write-Host 'PASS: public removal command uses hardened DELETE transport'
