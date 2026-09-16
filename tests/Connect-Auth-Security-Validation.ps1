<#
Validates Connect-WindowsDeviceLink SDK authentication error redaction.
No real Microsoft Graph dependency or network access is required.
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

& $module {
    function Initialize-WindowsDeviceLinkOnline { }
    function Connect-MgGraph {
        [CmdletBinding()]
        param(
            [string]$TenantId,[string]$ClientId,[string[]]$Scopes,[string]$ContextScope,[switch]$UseDeviceCode,
            [securestring]$AccessToken,[System.Security.Cryptography.X509Certificates.X509Certificate2]$Certificate,
            [string]$CertificateThumbprint,[string]$CertificateSubjectName,[bool]$SendCertificateChain,
            [pscredential]$ClientSecretCredential,[switch]$Identity,[switch]$EnvironmentVariable,
            [string]$Environment,[double]$ClientTimeout,[switch]$NoWelcome
        )
        if($AccessToken){$c=[pscredential]::new('token',$AccessToken);throw "Synthetic SDK failure token=$($c.GetNetworkCredential().Password)"}
        if($ClientSecretCredential){throw "Synthetic SDK failure secret=$($ClientSecretCredential.GetNetworkCredential().Password)"}
        if($EnvironmentVariable){throw "Synthetic SDK failure envsecret=$env:AZURE_CLIENT_SECRET"}
        throw 'Synthetic SDK failure'
    }
}

$tokenMarker='WDL-SDK-ACCESS-TOKEN'
$secureToken=ConvertTo-SecureString $tokenMarker -AsPlainText -Force
Assert-ThrowsSafe -Name 'SDK AccessToken failure is redacted' -Expected "method 'AccessToken'" -Forbidden $tokenMarker -ScriptBlock {
    & $module {param($Token) Connect-WindowsDeviceLink -AccessToken $Token} $secureToken
}

$secretMarker='WDL-SDK-CLIENT-SECRET'
$secureSecret=ConvertTo-SecureString $secretMarker -AsPlainText -Force
Assert-ThrowsSafe -Name 'SDK ClientSecret failure is redacted' -Expected "method 'ClientSecret'" -Forbidden $secretMarker -ScriptBlock {
    & $module {param($Secret) Connect-WindowsDeviceLink -TenantId 'tenant-test' -ClientId 'client-test' -ClientSecret $Secret} $secureSecret
}

$oldTenant=$env:AZURE_TENANT_ID;$oldClient=$env:AZURE_CLIENT_ID;$oldSecret=$env:AZURE_CLIENT_SECRET
$env:AZURE_TENANT_ID='tenant-test';$env:AZURE_CLIENT_ID='client-test';$env:AZURE_CLIENT_SECRET='WDL-SDK-ENV-SECRET'
try {
    Assert-ThrowsSafe -Name 'SDK EnvironmentVariable failure is redacted' -Expected "method 'EnvironmentVariable'" -Forbidden 'WDL-SDK-ENV-SECRET' -ScriptBlock {
        & $module {Connect-WindowsDeviceLink -EnvironmentVariable}
    }
}
finally {$env:AZURE_TENANT_ID=$oldTenant;$env:AZURE_CLIENT_ID=$oldClient;$env:AZURE_CLIENT_SECRET=$oldSecret}

Write-Host ''
Write-Host 'Connect authentication security regression set passed.'
