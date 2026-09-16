<#
WindowsDeviceLink authentication orchestration regression tests.
Hardware- and tenant-independent; all authentication and cloud calls are mocked in module scope.
#>
[CmdletBinding()] param([string]$ModulePath)
$ErrorActionPreference='Stop'

function Assert-True { param([bool]$Condition,[string]$Message) if(-not $Condition){throw "FAIL: $Message"} }
if(-not $ModulePath){$ModulePath=Join-Path $PSScriptRoot '..\src\WindowsDeviceLink\WindowsDeviceLink.psd1'}
$resolvedModulePath=(Resolve-Path -LiteralPath $ModulePath).Path

function Import-TestModule {
    Remove-Module WindowsDeviceLink -Force -ErrorAction SilentlyContinue
    Import-Module $resolvedModulePath -Force -ErrorAction Stop
    $m=Get-Module WindowsDeviceLink|Select-Object -First 1
    if(-not $m){throw 'FAIL: WindowsDeviceLink did not load.'}
    $m
}

$module=Import-TestModule

# DeviceCode initialization must obtain exactly one token and reuse it as AccessToken
# for initial lookup, registration and verification.
& $module {
    $script:WdlTokenCalls=0
    $script:WdlStatusCalls=0
    $script:WdlObservedMethods=@()
    $script:WdlObservedTokens=@()
    $script:WdlRegistrationMethod=$null
    $script:WdlRegistrationToken=$null
    $script:WdlSyntheticToken='WDL-SINGLE-TOKEN'

    function Get-WindowsDeviceLinkDeviceCodeToken {
        param([string]$TenantId,[string]$ClientId)
        $script:WdlTokenCalls++
        [pscustomobject]@{AccessToken=$script:WdlSyntheticToken;TenantId=$TenantId;ClientId=$ClientId}
    }
    function Get-WindowsDeviceLinkStatus {
        [CmdletBinding()]
        param([switch]$Online,[string]$Method,[string]$TenantId,[securestring]$AccessToken,[string]$Environment,[double]$ClientTimeout,[int]$TimeoutSeconds,[string]$WindowsManagementServicePath)
        $script:WdlStatusCalls++
        $script:WdlObservedMethods += $Method
        if($AccessToken){$c=[pscredential]::new('token',$AccessToken);$script:WdlObservedTokens += $c.GetNetworkCredential().Password}
        $present=($script:WdlStatusCalls -ge 2)
        [pscustomobject]@{Environment='Windows';Supported=$true;DeviceLinkPresent=$true;SerialNumber='TEST-SERIAL';LinkId='TEST-LINK';FirmwareVariablesPresent='2/4';AssociationPresent=$present;AssociationState=if($present){'preassociated'}else{'NotAssociated'};AssociationId=if($present){'assoc-test'}else{$null}}
    }
    function Test-WindowsDeviceLinkHealth {
        [CmdletBinding()] param([Parameter(ValueFromPipeline)]$InputObject)
        process {
            if($InputObject.AssociationPresent){[pscustomobject]@{State='Preassociated';Severity='Information';Summary='preassociated';RecommendedAction='none'}}
            else{[pscustomobject]@{State='LocalOnly';Severity='Information';Summary='local only';RecommendedAction='register'}}
        }
    }
    function Get-WindowsDeviceLink {
        param([int]$TimeoutSeconds,[string]$WindowsManagementServicePath)
        $o=[pscustomobject]@{SerialNumber='TEST-SERIAL';DeviceLink='SYNTHETIC-DEVICE-LINK';LinkId='TEST-LINK'}
        $o.PSObject.TypeNames.Insert(0,'Windows.DeviceLink.Information')
        $o
    }
    function Register-WindowsDeviceLink {
        [CmdletBinding(SupportsShouldProcess)]
        param([Parameter(Mandatory)][psobject]$InputObject,[string]$Method,[string]$TenantId,[securestring]$AccessToken,[string]$Environment,[double]$ClientTimeout)
        $script:WdlRegistrationMethod=$Method
        if($AccessToken){$c=[pscredential]::new('token',$AccessToken);$script:WdlRegistrationToken=$c.GetNetworkCredential().Password}
        [pscustomobject]@{Id='assoc-test';AssociationState='preassociated'}
    }
}

$result=& $module { Initialize-WindowsDeviceLink -Method DeviceCode -TenantId 'tenant-test' -Confirm:$false }
$tokenCalls=& $module {$script:WdlTokenCalls}
$statusCalls=& $module {$script:WdlStatusCalls}
$observedMethods=& $module {,$script:WdlObservedMethods}
$observedTokens=& $module {,$script:WdlObservedTokens}
$registrationMethod=& $module {$script:WdlRegistrationMethod}
$registrationToken=& $module {$script:WdlRegistrationToken}

Assert-True ($tokenCalls -eq 1) "DeviceCode initializer expected one token acquisition, got $tokenCalls."
Assert-True ($statusCalls -eq 2) "Initializer expected initial and verification status calls, got $statusCalls."
Assert-True ((@($observedMethods)|Where-Object{$_ -ne 'AccessToken'}).Count -eq 0) 'Status calls did not consistently use AccessToken after DeviceCode acquisition.'
Assert-True ((@($observedTokens)|Where-Object{$_ -ne 'WDL-SINGLE-TOKEN'}).Count -eq 0) 'Status calls did not reuse the acquired token.'
Assert-True ($registrationMethod -eq 'AccessToken') 'Registration did not use AccessToken mode after DeviceCode acquisition.'
Assert-True ($registrationToken -eq 'WDL-SINGLE-TOKEN') 'Registration did not reuse the acquired DeviceCode token.'
Assert-True ($result.BeforeState -eq 'LocalOnly' -and $result.AfterState -eq 'Preassociated' -and $result.Changed) 'Initializer synthetic lifecycle result was unexpected.'
Write-Host 'PASS: DeviceCode initializer acquires one token and reuses it end-to-end'

# Reload originals before testing Connect-WindowsDeviceLink SDK argument forwarding.
$module=Import-TestModule
& $module {
    $script:WdlConnectCalls=@()
    function Initialize-WindowsDeviceLinkOnline { }
    function Connect-MgGraph {
        [CmdletBinding()]
        param(
            [string]$TenantId,[string]$ClientId,[string[]]$Scopes,[string]$ContextScope,[switch]$UseDeviceCode,
            [securestring]$AccessToken,[System.Security.Cryptography.X509Certificates.X509Certificate2]$Certificate,
            [string]$CertificateThumbprint,[string]$CertificateSubjectName,[bool]$SendCertificateChain,
            [pscredential]$ClientSecretCredential,[switch]$Identity,[string]$Environment,[double]$ClientTimeout,[switch]$NoWelcome
        )
        $copy=@{};foreach($k in $PSBoundParameters.Keys){$copy[$k]=$PSBoundParameters[$k]}
        $script:WdlConnectCalls += ,$copy
    }
}

& $module { Connect-WindowsDeviceLink -TenantId 'tenant-test' -ClientId 'client-test' -CertificateThumbprint 'ABC123' -SendCertificateChain $true | Out-Null }
& $module { Connect-WindowsDeviceLink -Identity -ClientId 'mi-client' | Out-Null }
$secret=ConvertTo-SecureString 'WDL-SDK-CLIENT-SECRET' -AsPlainText -Force
& $module { param($Secret) Connect-WindowsDeviceLink -TenantId 'tenant-test' -ClientId 'client-test' -ClientSecret $Secret | Out-Null } $secret
$calls=& $module {,$script:WdlConnectCalls}

Assert-True ($calls.Count -eq 3) "Expected three mocked Connect-MgGraph calls, got $($calls.Count)."
Assert-True ($calls[0].CertificateThumbprint -eq 'ABC123' -and $calls[0].SendCertificateChain -eq $true) 'CertificateThumbprint arguments were not forwarded correctly.'
Assert-True ($calls[1].Identity -eq $true -and $calls[1].ClientId -eq 'mi-client' -and -not $calls[1].ContainsKey('TenantId')) 'ManagedIdentity arguments were not forwarded correctly.'
Assert-True ($calls[2].ClientSecretCredential -is [pscredential]) 'ClientSecret was not wrapped in PSCredential for SDK authentication.'
Assert-True (-not $calls[2].ContainsKey('ClientSecret')) 'Plain ClientSecret parameter was forwarded to Connect-MgGraph.'
Write-Host 'PASS: SDK authentication parameters are forwarded through explicit safe shapes'

Write-Host ''
Write-Host 'Authentication orchestration regression set passed.'
