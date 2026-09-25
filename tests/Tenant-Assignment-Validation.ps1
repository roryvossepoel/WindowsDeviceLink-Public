[CmdletBinding()]
param([string]$ModulePath = (Join-Path $PSScriptRoot '..\src\WindowsDeviceLink\WindowsDeviceLink.psd1'))

$ErrorActionPreference = 'Stop'
function Assert-True([bool]$Condition,[string]$Message) { if (-not $Condition) { throw "FAIL: $Message" } }

Remove-Module WindowsDeviceLink -Force -ErrorAction SilentlyContinue
Import-Module (Resolve-Path $ModulePath) -Force
$module = Get-Module WindowsDeviceLink
$tenantA = '11111111-1111-1111-1111-111111111111'
$tenantB = '22222222-2222-2222-2222-222222222222'
$serial = 'TEST-SERIAL'
$apiMarker = 'DO-NOT-LOG-TENANT-ASSIGNMENT-KEY'
$secureKey = ConvertTo-SecureString $apiMarker -AsPlainText -Force

& $module {
    $script:AssignmentScenario = 'none'
    $script:AssignmentReset = $false
    $script:AssignmentReconciled = $false
    $script:AssignmentReconcileCount = 0
    $script:AssignmentSource = $null
    $script:AssignmentTarget = $null
    $script:AssignmentRepair = $false
    $script:DirectTenant = $null
    $script:DirectMethod = $null

    function script:Initialize-WindowsDeviceLink {
        param($Method,$TenantId,$ClientId,$AccessToken,$Certificate,$CertificateThumbprint,$CertificateSubjectName,$SendCertificateChain,$ClientSecret,$Environment,$ClientTimeout,$TimeoutSeconds,$WindowsManagementServicePath)
        $script:DirectTenant=$TenantId
        $script:DirectMethod=$Method
        $effectiveTenant = if ($TenantId) { $TenantId } else { '33333333-3333-3333-3333-333333333333' }
        [pscustomobject]@{
            Action='Register'; Changed=$true; Message='Direct registration completed.'; SerialNumber='TEST-SERIAL'
            LinkId='AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA'; AssociationId='direct-association'; AssociationState='preassociated'
            AfterStatus=[pscustomobject]@{ TenantId=$effectiveTenant; AssociationId='direct-association'; AssociationState='preassociated' }
        }
    }

    function script:Invoke-WindowsDeviceLinkBackendTenantCatalog {
        param($BackendUri,$BackendApiKey,$TimeoutSeconds)
        [pscustomobject]@{ success=$true; tenantCount=2; tenants=@(
            [pscustomobject]@{ name='Tenant A'; tenantId='11111111-1111-1111-1111-111111111111' },
            [pscustomobject]@{ name='Tenant B'; tenantId='22222222-2222-2222-2222-222222222222' }
        ) }
    }
    function script:Get-WindowsDeviceLink {
        param($TimeoutSeconds,$WindowsManagementServicePath)
        $link = if ($script:AssignmentReset) { 'BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB' } else { 'AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA' }
        [pscustomobject]@{ SerialNumber='TEST-SERIAL'; LinkId=$link; DeviceLink="payload-$link"; Manufacturer='Test'; Model='Test' }
    }
    function script:Get-WindowsDeviceLinkLocalAssociation {
        [pscustomobject]@{ ConflictDetected=$false; FirmwareState=if($script:AssignmentScenario -eq 'stale-new'){'4/4'}else{'2/4'}; TenantId=$null }
    }
    function script:Reset-WindowsDeviceLinkFirmwareState { param($Confirm) $script:AssignmentReset=$true; [pscustomobject]@{ Success=$true } }
    function script:Invoke-WindowsDeviceLinkBackendLookup {
        param($BackendUri,$BackendApiKey,$SerialNumber,$TimeoutSeconds)
        $rows = @(
            [pscustomobject]@{ tenantId='11111111-1111-1111-1111-111111111111'; success=$true },
            [pscustomobject]@{ tenantId='22222222-2222-2222-2222-222222222222'; success=$true }
        )
        if ($script:AssignmentScenario -eq 'incomplete') {
            $rows[1].success=$false
            return [pscustomobject]@{ success=$true; searchedTenantCount=2; successfulTenantCount=1; failedTenantCount=1; tenantErrors=@([pscustomobject]@{tenantId=$rows[1].tenantId}); tenants=$rows; matchCount=0; matches=@() }
        }
        $matches = @()
        if ($script:AssignmentReconciled -or $script:AssignmentScenario -in @('same','repair')) {
            $state = if ($script:AssignmentScenario -eq 'repair' -and -not $script:AssignmentReconciled) { 'associated' } else { 'preassociated' }
            $matches = @([pscustomobject]@{ tenantId='22222222-2222-2222-2222-222222222222'; associationId='new-association'; associationState=$state; serialNumber='TEST-SERIAL' })
        }
        elseif ($script:AssignmentScenario -in @('move','move-failure')) {
            $matches = @([pscustomobject]@{ tenantId='11111111-1111-1111-1111-111111111111'; associationId='old-association'; associationState='associated'; serialNumber='TEST-SERIAL' })
        }
        [pscustomobject]@{ success=$true; searchedTenantCount=2; successfulTenantCount=2; failedTenantCount=0; tenantErrors=@(); tenants=$rows; matchCount=$matches.Count; matches=$matches }
    }
    function script:Invoke-WindowsDeviceLinkBackendReconcile {
        param($BackendUri,$BackendApiKey,$InputObject,$SourceTenantId,$TargetTenantId,$RepairExistingAssociation,$TimeoutSeconds)
        $script:AssignmentReconcileCount++
        $script:AssignmentSource=$SourceTenantId
        $script:AssignmentTarget=$TargetTenantId
        $script:AssignmentRepair=[bool]$RepairExistingAssociation
        if ($script:AssignmentScenario -eq 'move-failure') { throw 'synthetic reconcile failure' }
        $script:AssignmentReconciled=$true
        [pscustomobject]@{ success=$true; requestId='33333333-3333-3333-3333-333333333333'; decision=if($SourceTenantId){'Move'}else{'New'} }
    }
}

function Reset-Scenario([string]$Name) {
    & $module { param($n) $script:AssignmentScenario=$n; $script:AssignmentReset=$false; $script:AssignmentReconciled=$false; $script:AssignmentReconcileCount=0; $script:AssignmentSource=$null; $script:AssignmentTarget=$null; $script:AssignmentRepair=$false } $Name
}
function Read-State { & $module { [pscustomobject]@{ Reset=$script:AssignmentReset; Reconciled=$script:AssignmentReconciled; Count=$script:AssignmentReconcileCount; Source=$script:AssignmentSource; Target=$script:AssignmentTarget; Repair=$script:AssignmentRepair } } }

$common = @{ BackendUri='https://example.test/api/devicelink'; BackendApiKey=$secureKey; Confirm=$false }

$sourceAllowsEmpty = & $module {
    $decisionAllowsEmpty = @((Get-Command Resolve-WindowsDeviceLinkTenantAssignmentDecision).Parameters['SourceTenantId'].Attributes |
        Where-Object { $_ -is [System.Management.Automation.AllowEmptyStringAttribute] }).Count -eq 1
    $setSource = (Get-Command Set-WindowsDeviceLinkTenant).ScriptBlock.ToString()
    $reconcileSourceIsConditional = $setSource -match '(?s)if \(-not \[string\]::IsNullOrWhiteSpace\(\$sourceId\)\).*reconcileParameters\.SourceTenantId'
    $decisionAllowsEmpty -and $reconcileSourceIsConditional
}
Assert-True $sourceAllowsEmpty 'Every New-route boundary must accept an empty SourceTenantId on Windows PowerShell 5.1.'
Write-Host 'PASS: all New-route boundaries accept an empty source tenant on Windows PowerShell 5.1'

$direct = Set-WindowsDeviceLinkTenant -Method DeviceCode -Confirm:$false
Assert-True ($direct.OperationMode -eq 'Direct' -and $direct.Decision -eq 'New' -and $direct.TargetTenantId -eq '33333333-3333-3333-3333-333333333333') 'Direct mode without TenantId must use the authenticated tenant returned by initialization.'
$directState = & $module { [pscustomobject]@{ Tenant=$script:DirectTenant; Method=$script:DirectMethod } }
Assert-True ([string]::IsNullOrWhiteSpace($directState.Tenant) -and $directState.Method -eq 'DeviceCode') 'Direct mode unexpectedly forced a TenantId.'
Write-Host 'PASS: Direct mode leaves TenantId implicit and reports the authenticated tenant'

$direct = Set-WindowsDeviceLinkTenant -Method DeviceCode -TenantId $tenantB -Confirm:$false
Assert-True ($direct.OperationMode -eq 'Direct' -and $direct.TargetTenantId -eq $tenantB) 'Direct mode lost the explicitly selected TenantId.'
Write-Host 'PASS: Direct mode accepts an explicit tenant selection'

$blocked=$false
try { $null=Set-WindowsDeviceLinkTenant -Method DeviceCode -BackendUri 'https://example.test/api/devicelink' -BackendApiKey $secureKey -TargetTenantId $tenantB -Confirm:$false } catch { $blocked=$true }
Assert-True $blocked 'Direct and Backend parameters must be mutually exclusive.'
$setCommand = Get-Command Set-WindowsDeviceLinkTenant -Module WindowsDeviceLink
$backendKeyAttributes = @($setCommand.Parameters['BackendApiKey'].Attributes | Where-Object {
    $_ -is [System.Management.Automation.ParameterAttribute] -and $_.ParameterSetName -in @('BackendById','BackendByName')
})
Assert-True ($backendKeyAttributes.Count -eq 2 -and @($backendKeyAttributes | Where-Object Mandatory).Count -eq 2) 'Backend mode must require its credential in every Backend parameter set.'
Write-Host 'PASS: Direct and Backend routes are explicit, mutually exclusive, and fail closed'

Reset-Scenario none
$result = Set-WindowsDeviceLinkTenant @common -TargetTenantId $tenantB
$state = Read-State
Assert-True ($result.Decision -eq 'New' -and $result.Changed -and $state.Reset -and $result.PreviousLinkId -ne $result.NewLinkId -and $state.Count -eq 1) 'New must renew the local identity and reconcile once.'
Assert-True ([string]::IsNullOrWhiteSpace($state.Source) -and $state.Target -eq $tenantB) 'New sent an unexpected source or target.'
Write-Host 'PASS: New renews identity and uses the selected target'

Reset-Scenario stale-new
$result = Set-WindowsDeviceLinkTenant @common -TargetTenantId $tenantB
$state = Read-State
Assert-True ($result.Decision -eq 'New' -and $state.Reset -and $result.PreviousLinkId -ne $result.NewLinkId -and $state.Count -eq 1) 'New with stale 4/4 local affinity must renew identity before registration.'
Write-Host 'PASS: New renews stale associated local identity'

Reset-Scenario same
$result = Set-WindowsDeviceLinkTenant @common -TargetTenantName 'tenant b'
$state = Read-State
Assert-True ($result.Decision -eq 'None' -and -not $result.Changed -and -not $state.Reset -and $state.Count -eq 0) 'Same-tenant assignment must be a no-op.'
Write-Host 'PASS: friendly-name resolution and same-tenant no-op'

Reset-Scenario repair
$result = Set-WindowsDeviceLinkTenant @common -TargetTenantId $tenantB -RepairExistingAssociation
$state = Read-State
Assert-True ($result.Decision -eq 'Repair' -and $result.Changed -and -not $state.Reset -and $state.Count -eq 1 -and $state.Repair) 'Same-tenant repair must reuse the current 2/4 identity and request one explicit backend replacement.'
Assert-True ($state.Source -eq $tenantB -and $state.Target -eq $tenantB -and $result.ReasonCode -eq 'WDL-BACKEND-REPAIR') 'Same-tenant repair lost its explicit same-tenant source/target boundary.'
Write-Host 'PASS: same-tenant repair replaces stale cloud state without another local reset'

Reset-Scenario move
$result = Set-WindowsDeviceLinkTenant @common -TargetTenantId $tenantB
$state = Read-State
Assert-True ($result.Decision -eq 'Move' -and $result.Changed -and $state.Reset -and $state.Count -eq 1) 'Move must renew firmware identity and reconcile exactly once.'
Assert-True ($result.PreviousLinkId -ne $result.NewLinkId -and $state.Source -eq $tenantA -and $state.Target -eq $tenantB) 'Move lost the old/new identity or source/target boundary.'
Write-Host 'PASS: Move renews identity, sends explicit source/target, and verifies once'

Reset-Scenario move
$result = Set-WindowsDeviceLinkTenant @common -TargetTenantId $tenantB -WhatIf
$state = Read-State
Assert-True ($result.Decision -eq 'Move' -and -not $result.Changed -and -not $state.Reset -and $state.Count -eq 0) 'WhatIf must not reset firmware or call reconcile.'
Write-Host 'PASS: WhatIf is non-mutating'

Reset-Scenario incomplete
$blocked=$false
try { $null=Set-WindowsDeviceLinkTenant @common -TargetTenantId $tenantB } catch { $blocked=$true }
$state=Read-State
Assert-True ($blocked -and -not $state.Reset -and $state.Count -eq 0) 'Incomplete tenant coverage must block before every mutation.'
Write-Host 'PASS: incomplete multitenant lookup fails closed'

Reset-Scenario move-failure
$blocked=$false; $message=''
try { $null=Set-WindowsDeviceLinkTenant @common -TargetTenantId $tenantB } catch { $blocked=$true; $message=$_.Exception.Message }
$state=Read-State
Assert-True ($blocked -and $state.Reset -and $state.Count -eq 1 -and $message -match 'fresh lookup') 'Post-reset reconcile failure must report uncertain recovery without retry.'
Assert-True (-not $message.Contains($apiMarker)) 'Failure text leaked the backend API key.'
Write-Host 'PASS: post-reset backend failure is explicit and never retried'

Write-Host 'Tenant assignment orchestration validation passed. No native firmware or cloud calls were made.'
