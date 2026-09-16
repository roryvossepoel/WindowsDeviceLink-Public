<#
Validates that webhook responses cannot reflect sensitive request material back to callers.
No network traffic is performed.
#>
[CmdletBinding()] param([string]$ModulePath)
$ErrorActionPreference='Stop'
function Assert-True { param([bool]$Condition,[string]$Message) if(-not $Condition){throw "FAIL: $Message"} }
if(-not $ModulePath){$ModulePath=Join-Path $PSScriptRoot '..\src\WindowsDeviceLink\WindowsDeviceLink.psd1'}
Remove-Module WindowsDeviceLink -Force -ErrorAction SilentlyContinue
Import-Module (Resolve-Path -LiteralPath $ModulePath).Path -Force -ErrorAction Stop
$module=Get-Module WindowsDeviceLink|Select-Object -First 1

$key='WDL-WEBHOOK-KEY-REFLECTION'
$payload='WDL-DEVICE-LINK-REFLECTION'
$input=[pscustomobject]@{
    SerialNumber='TEST-SERIAL';Manufacturer='Test';Model='Test';SmbiosUuid='uuid';LinkId='link';PayloadCreationTimeUtc='2026-09-16T00:00:00Z'
    DeviceLink=$payload;Environment='Windows';DllSource='System';DllVersion='test';ActivationMode='RegisteredWinRT'
}
$input.PSObject.TypeNames.Insert(0,'Windows.DeviceLink.Information')

& $module {
    $script:WdlEchoKey='WDL-WEBHOOK-KEY-REFLECTION'
    $script:WdlEchoPayload='WDL-DEVICE-LINK-REFLECTION'
    function Invoke-RestMethod {
        [pscustomobject]@{
            status='ok'
            echoedKey=$script:WdlEchoKey
            nested=[pscustomobject]@{deviceLink=$script:WdlEchoPayload;authorization="Bearer $script:WdlEchoKey"}
            array=@('safe',$script:WdlEchoPayload)
        }
    }
}
try {
    $result=& $module { param($Input,$Key) Invoke-WindowsDeviceLinkWebhook -InputObject $Input -WebhookUri 'https://example.invalid/' -WebhookApiKey $Key } $input $key
    $serialized=$result.Response|ConvertTo-Json -Depth 8 -Compress
    Assert-True (-not $serialized.Contains($key)) 'Webhook result leaked reflected API key.'
    Assert-True (-not $serialized.Contains($payload)) 'Webhook result leaked reflected DeviceLink payload.'
    Assert-True ($serialized -match '\[REDACTED\]') 'Webhook response did not contain redaction markers.'
    Assert-True ($result.RequestId) 'Webhook result lost RequestId while sanitizing response.'
    Write-Host 'PASS: webhook reflected response is recursively sanitized'
}
finally {
    & $module { Remove-Item Function:\Invoke-RestMethod -Force -ErrorAction SilentlyContinue; Remove-Variable WdlEchoKey,WdlEchoPayload -Scope Script -ErrorAction SilentlyContinue }
}
