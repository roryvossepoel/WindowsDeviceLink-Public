<#
Validates SDK authentication error redaction through the production connection helper.
No Microsoft Graph dependency or network access is required.
#>
[CmdletBinding()] param([string]$ModulePath)
$ErrorActionPreference='Stop'
function Assert-ThrowsSafe {
    param([string]$Name,[scriptblock]$ScriptBlock,[string]$Expected,[string]$Forbidden)
    try { & $ScriptBlock; throw "FAIL: $Name - expected an exception." }
    catch {
        $m=[string]$_.Exception.Message
        if($m -notlike "*$Expected*"){throw "FAIL: $Name - unexpected message '$m'."}
        if($Forbidden -and $m.Contains($Forbidden)){throw "FAIL: $Name - leaked '$Forbidden'."}
        Write-Host "PASS: $Name"
    }
}
if(-not $ModulePath){$ModulePath=Join-Path $PSScriptRoot '..\src\WindowsDeviceLink\WindowsDeviceLink.psd1'}
Remove-Module WindowsDeviceLink -Force -ErrorAction SilentlyContinue
Import-Module (Resolve-Path -LiteralPath $ModulePath).Path -Force -ErrorAction Stop
$module=Get-Module WindowsDeviceLink|Select-Object -First 1

foreach($case in @(
    @{Name='SDK AccessToken failure is redacted';Method='AccessToken';Secret='WDL-SDK-ACCESS-TOKEN'},
    @{Name='SDK ClientSecret failure is redacted';Method='ClientSecret';Secret='WDL-SDK-CLIENT-SECRET'},
    @{Name='SDK EnvironmentVariable failure is redacted';Method='EnvironmentVariable';Secret='WDL-SDK-ENV-SECRET'}
)){
    $request={param($Parameters,$MethodName)throw "Synthetic SDK $MethodName failure secret=$($case.Secret)"}.GetNewClosure()
    Assert-ThrowsSafe -Name $case.Name -Expected "method '$($case.Method)'" -Forbidden $case.Secret -ScriptBlock {
        & $module {param($Method,$Secret,$Request)Invoke-WindowsDeviceLinkGraphConnect -Parameters @{NoWelcome=$true} -MethodName $Method -SensitiveValue @($Secret) -RequestScript $Request} $case.Method $case.Secret $request
    }
}

$command=(Get-Command Connect-WindowsDeviceLink -Module WindowsDeviceLink).ScriptBlock.ToString()
if($command -notmatch 'Invoke-WindowsDeviceLinkGraphConnect'){throw 'FAIL: Connect-WindowsDeviceLink is not wired to the hardened connection helper.'}
Write-Host 'PASS: Connect-WindowsDeviceLink uses hardened SDK connection transport'

Write-Host ''
Write-Host 'Connect authentication security regression set passed.'
