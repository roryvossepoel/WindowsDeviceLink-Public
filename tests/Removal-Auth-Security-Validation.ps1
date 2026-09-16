<#
Validates native association-removal error redaction.
No Graph request is sent.
#>
[CmdletBinding()] param([string]$ModulePath)
$ErrorActionPreference='Stop'
if(-not $ModulePath){$ModulePath=Join-Path $PSScriptRoot '..\src\WindowsDeviceLink\WindowsDeviceLink.psd1'}
Remove-Module WindowsDeviceLink -Force -ErrorAction SilentlyContinue
Import-Module (Resolve-Path -LiteralPath $ModulePath).Path -Force -ErrorAction Stop
$module=Get-Module WindowsDeviceLink|Select-Object -First 1

$marker='WDL-DELETE-ACCESS-TOKEN'
$secure=ConvertTo-SecureString $marker -AsPlainText -Force
& $module {
    function Invoke-RestMethod {
        param($Method,$Uri,$Headers,$ErrorAction)
        throw "HTTP 403 Authorization: $($Headers.Authorization)"
    }
}
try {
    try {
        & $module {param($Token) Remove-WindowsDeviceLinkAssociation -AssociationId '11111111-1111-1111-1111-111111111111' -Method AccessToken -TenantId 'tenant-test' -AccessToken $Token -Confirm:$false} $secure
        throw 'FAIL: removal expected an exception.'
    }
    catch {
        $message=[string]$_.Exception.Message
        if($message -notlike '*HTTP 403*'){throw "FAIL: removal error lost HTTP context: $message"}
        if($message.Contains($marker)){throw 'FAIL: removal error leaked bearer token.'}
        Write-Host 'PASS: removal transport error redacts bearer token'
    }
}
finally {
    & $module {Remove-Item Function:\Invoke-RestMethod -Force -ErrorAction SilentlyContinue}
}
