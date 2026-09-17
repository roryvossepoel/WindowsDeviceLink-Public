<#
Deterministic DeviceLink preflight decision tests.
No hardware, firmware, TPM, Secure Boot, Graph or network access is required.
#>
[CmdletBinding()] param([string]$ModulePath)
$ErrorActionPreference='Stop'
function Assert-True { param([bool]$Condition,[string]$Message) if(-not $Condition){throw "FAIL: $Message"} }
if(-not $ModulePath){$ModulePath=Join-Path $PSScriptRoot '..\src\WindowsDeviceLink\WindowsDeviceLink.psd1'}
Remove-Module WindowsDeviceLink -Force -ErrorAction SilentlyContinue
Import-Module (Resolve-Path -LiteralPath $ModulePath).Path -Force -ErrorAction Stop
$module=Get-Module WindowsDeviceLink|Select-Object -First 1

function New-Check([string]$Name,[string]$State){[pscustomobject]@{Name=$Name;State=$State}}

$ready=& $module {param($Checks) Resolve-WindowsDeviceLinkPreflightState -Checks $Checks} @(
    (New-Check Runtime Ready),(New-Check FirmwareAccess Ready),(New-Check TPM Ready),(New-Check SecureBoot Ready),(New-Check LocalIdentity Ready)
)
Assert-True ($ready.State -eq 'Ready' -and $ready.Ready -and $ready.BlockingCount -eq 0 -and $ready.WarningCount -eq 0) 'All-ready preflight matrix did not resolve to Ready.'
Write-Host 'PASS: all-ready preflight resolves Ready'

$warning=& $module {param($Checks) Resolve-WindowsDeviceLinkPreflightState -Checks $Checks} @(
    (New-Check Runtime Ready),(New-Check TPM Warning),(New-Check SecureBoot Ready)
)
Assert-True ($warning.State -eq 'Warning' -and -not $warning.Ready -and $warning.BlockingCount -eq 0 -and $warning.WarningCount -eq 1) 'Warning preflight matrix did not preserve Warning.'
Write-Host 'PASS: unknown/non-blocking observation resolves Warning'

$blocked=& $module {param($Checks) Resolve-WindowsDeviceLinkPreflightState -Checks $Checks} @(
    (New-Check Runtime Blocked),(New-Check TPM Warning),(New-Check LocalIdentity Blocked)
)
Assert-True ($blocked.State -eq 'Blocked' -and -not $blocked.Ready -and $blocked.BlockingCount -eq 2 -and $blocked.WarningCount -eq 1) 'Blocked preflight matrix did not take precedence over warnings.'
Write-Host 'PASS: blockers take precedence and remain counted'

# Regression for Windows PowerShell 5.1 generic List[object] materialization.
# Direct @($genericList) can throw "Argument types do not match" in this runtime.
$generic = New-Object System.Collections.Generic.List[object]
$generic.Add((New-Check Runtime Ready)) | Out-Null
$generic.Add((New-Check TPM Warning)) | Out-Null
$materialized = @($generic | ForEach-Object { $_ })
Assert-True ($materialized -is [object[]]) 'Generic preflight check list did not materialize to Object[].'
$genericResult=& $module {param($Checks) Resolve-WindowsDeviceLinkPreflightState -Checks $Checks} $materialized
Assert-True ($genericResult.State -eq 'Warning' -and $genericResult.WarningCount -eq 1) 'Materialized generic preflight list did not resolve correctly.'
Write-Host 'PASS: Windows PowerShell generic-list materialization regression'

Write-Host ''
Write-Host 'Preflight decision regression set passed.'
