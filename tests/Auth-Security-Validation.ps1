<#
WindowsDeviceLink authentication and secret-handling regression tests.
Hardware- and tenant-independent. No real authentication or network traffic is performed.
#>
[CmdletBinding()] param([string]$ModulePath)
$ErrorActionPreference='Stop'

function Assert-True { param([bool]$Condition,[string]$Message) if(-not $Condition){throw "FAIL: $Message"} }
function Assert-Throws {
    param([string]$Name,[scriptblock]$ScriptBlock,[string]$ExpectedMessage,[string[]]$ForbiddenText)
    try { & $ScriptBlock; throw "FAIL: $Name - expected an exception but none was thrown." }
    catch {
        $message=[string]$_.Exception.Message
        if($ExpectedMessage -and $message -notlike "*$ExpectedMessage*"){throw "FAIL: $Name - expected '$ExpectedMessage', got '$message'."}
        foreach($forbidden in @($ForbiddenText)){ if($forbidden -and $message.Contains($forbidden)){throw "FAIL: $Name - exception leaked forbidden text '$forbidden'."} }
        Write-Host "PASS: $Name"
    }
}

if(-not $ModulePath){$ModulePath=Join-Path $PSScriptRoot '..\src\WindowsDeviceLink\WindowsDeviceLink.psd1'}
$resolvedModulePath=(Resolve-Path -LiteralPath $ModulePath).Path
Remove-Module WindowsDeviceLink -Force -ErrorAction SilentlyContinue
Import-Module $resolvedModulePath -Force -ErrorAction Stop
$module=Get-Module WindowsDeviceLink|Select-Object -First 1
if(-not $module){throw 'FAIL: WindowsDeviceLink did not load.'}

$redacted=& $module { Protect-WindowsDeviceLinkSensitiveText -Text 'secret=CLIENT-SECRET Authorization: Bearer ACCESS-TOKEN payload=DEVICE-JWT' -SensitiveValue @('CLIENT-SECRET','DEVICE-JWT') }
Assert-True ($redacted -notmatch 'CLIENT-SECRET|ACCESS-TOKEN|DEVICE-JWT') 'redaction helper leaked a sensitive marker.'
Assert-True ($redacted -match '\[REDACTED\]') 'redaction helper did not emit a redaction marker.'
Write-Host 'PASS: sensitive-text redaction helper'

$clientSecretMarker='WDL-CLIENT-SECRET-MARKER'
$secureClientSecret=ConvertTo-SecureString $clientSecretMarker -AsPlainText -Force
$clientSecretRequest={param($Uri,$Body)throw "Synthetic OAuth failure containing $($Body.client_secret)"}
Assert-Throws -Name 'Client-secret transport error is redacted' -ExpectedMessage 'Client-secret authentication failed' -ForbiddenText @($clientSecretMarker) -ScriptBlock {
    & $module {param($Secret,$Request) Get-WindowsDeviceLinkClientSecretToken -TenantId 'tenant-test' -ClientId 'client-test' -ClientSecret $Secret -RequestScript $Request} $secureClientSecret $clientSecretRequest
}

$deviceCodeMarker='WDL-DEVICE-CODE-SECRET'
$deviceCodeRequest={
    param($Stage,$Uri,$Body)
    if($Stage -eq 'DeviceCode'){
        return [pscustomobject]@{device_code='WDL-DEVICE-CODE-SECRET';user_code='SAFE-USER-CODE';verification_uri='https://example.invalid/device';expires_in=60;interval=1}
    }
    throw "Synthetic device-code token failure containing $($Body.device_code)"
}
$noSleep={param($Seconds)}
Assert-Throws -Name 'Device-code transport error redacts device_code' -ExpectedMessage 'Device code authentication failed' -ForbiddenText @($deviceCodeMarker) -ScriptBlock {
    & $module {param($Request,$Sleep) Get-WindowsDeviceLinkDeviceCodeToken -TenantId 'tenant-test' -RequestScript $Request -SleepScript $Sleep} $deviceCodeRequest $noSleep
}

$apiKeyMarker='WDL-WEBHOOK-KEY-MARKER';$deviceLinkMarker='WDL-RAW-DEVICE-LINK-MARKER'
$webhookRequest={param($Uri,$Headers,$Body)throw "Synthetic webhook failure key=$($Headers['X-WindowsDeviceLink-Key']) payload=$Body"}
Assert-Throws -Name 'Webhook transport error redacts key and DeviceLink' -ExpectedMessage 'DeviceLink webhook could not be reached' -ForbiddenText @($apiKeyMarker,$deviceLinkMarker) -ScriptBlock {
    & $module {
        param($Key,$Payload,$Request)
        $input=[pscustomobject]@{SerialNumber='TEST-SERIAL';Manufacturer='Test';Model='Test';SmbiosUuid='00000000-0000-0000-0000-000000000001';LinkId='00000000-0000-0000-0000-000000000002';PayloadCreationTimeUtc='2026-09-16T00:00:00Z';DeviceLink=$Payload;Environment='Windows';DllSource='System';DllVersion='test';ActivationMode='RegisteredWinRT'}
        $input.PSObject.TypeNames.Insert(0,'Windows.DeviceLink.Information')
        Invoke-WindowsDeviceLinkWebhook -InputObject $input -WebhookUri 'https://example.invalid/' -WebhookApiKey $Key -RequestScript $Request
    } $apiKeyMarker $deviceLinkMarker $webhookRequest
}

$accessTokenMarker='WDL-ACCESS-TOKEN-MARKER'
$request={ param($Uri,$SdkMode,$AccessToken) throw "HTTP 401 Authorization: Bearer $AccessToken" }
Assert-Throws -Name 'Graph GET redacts bearer token' -ExpectedMessage 'HTTP 401' -ForbiddenText @($accessTokenMarker) -ScriptBlock { & $module { param($Request,$Token) Invoke-WindowsDeviceLinkGraphGet -Uri 'https://graph.microsoft.com/beta/test' -AccessToken $Token -RequestScript $Request } $request $accessTokenMarker }

$registrationToken='WDL-REGISTRATION-TOKEN';$registrationPayload='WDL-REGISTRATION-DEVICE-LINK'
$registrationRequest={ param($Uri,$Body,$AccessToken) throw "HTTP 403 token=$AccessToken body=$Body" }
Assert-Throws -Name 'Graph registration redacts token and DeviceLink payload' -ExpectedMessage 'HTTP 403' -ForbiddenText @($registrationToken,$registrationPayload) -ScriptBlock {
    & $module {
        param($Payload,$Request,$Token)
        $input=[pscustomobject]@{SerialNumber='TEST-SERIAL';DeviceLink=$Payload}
        $input.PSObject.TypeNames.Insert(0,'Windows.DeviceLink.Information')
        Invoke-WindowsDeviceLinkGraphRegistration -InputObject $input -AccessToken $Token -TenantId 'tenant-test' -RequestScript $Request
    } $registrationPayload $registrationRequest $registrationToken
}

Assert-Throws -Name 'Register AccessToken requires token' -ExpectedMessage '-AccessToken is required' -ScriptBlock {
    & $module {
        $input=[pscustomobject]@{SerialNumber='TEST-SERIAL';DeviceLink='TEST-PAYLOAD'}
        $input.PSObject.TypeNames.Insert(0,'Windows.DeviceLink.Information')
        $input | Register-WindowsDeviceLink -Method AccessToken -TenantId 'tenant-test'
    }
}
Assert-Throws -Name 'Lookup Certificate requires certificate object' -ExpectedMessage '-TenantId, -ClientId, and -Certificate are required' -ScriptBlock { Get-WindowsDeviceLinkAssociation -SerialNumber 'TEST-SERIAL' -Method Certificate -TenantId 'tenant-test' -ClientId 'client-test' }
Assert-Throws -Name 'Lookup CertificateThumbprint requires thumbprint' -ExpectedMessage '-TenantId, -ClientId, and -CertificateThumbprint are required' -ScriptBlock { Get-WindowsDeviceLinkAssociation -SerialNumber 'TEST-SERIAL' -Method CertificateThumbprint -TenantId 'tenant-test' -ClientId 'client-test' }
Assert-Throws -Name 'Lookup CertificateSubjectName requires subject' -ExpectedMessage '-TenantId, -ClientId, and -CertificateSubjectName are required' -ScriptBlock { Get-WindowsDeviceLinkAssociation -SerialNumber 'TEST-SERIAL' -Method CertificateSubjectName -TenantId 'tenant-test' -ClientId 'client-test' }
Assert-Throws -Name 'ManagedIdentity rejects TenantId' -ExpectedMessage 'not valid with -Method ManagedIdentity' -ScriptBlock { Get-WindowsDeviceLinkAssociation -SerialNumber 'TEST-SERIAL' -Method ManagedIdentity -TenantId 'tenant-test' }

$envNames=@('AZURE_TENANT_ID','AZURE_CLIENT_ID','AZURE_CLIENT_SECRET');$saved=@{}
foreach($name in $envNames){$saved[$name]=[Environment]::GetEnvironmentVariable($name);[Environment]::SetEnvironmentVariable($name,$null)}
try { Assert-Throws -Name 'EnvironmentVariable reports missing names safely' -ExpectedMessage 'AZURE_TENANT_ID' -ScriptBlock { Get-WindowsDeviceLinkAssociation -SerialNumber 'TEST-SERIAL' -Method EnvironmentVariable } }
finally { foreach($name in $envNames){[Environment]::SetEnvironmentVariable($name,$saved[$name])} }

Write-Host ''
Write-Host 'Authentication and secret-handling regression set passed.'
