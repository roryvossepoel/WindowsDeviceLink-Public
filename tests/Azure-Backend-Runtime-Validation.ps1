[CmdletBinding()]
param([string]$FunctionRoot = (Join-Path $PSScriptRoot '../function-app'))

$ErrorActionPreference = 'Stop'
Import-Module Microsoft.PowerShell.Utility

# Only the Functions output binding and outbound HTTP transport are mocked.
# The deployed run.ps1, certificate loading/signing and result handling execute unchanged.
class HttpResponseContext {
    [int]$StatusCode
    [hashtable]$Headers
    [object]$Body
}

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "FAIL: $Message" }
}

$global:wdlBackendTest_tenantA = '11111111-1111-1111-1111-111111111111'
$global:wdlBackendTest_tenantB = '22222222-2222-2222-2222-222222222222'
$global:wdlBackendTest_serial = 'UNASSOCIATED-TEST-DEVICE'
$global:wdlBackendTest_correlation = '33333333-3333-3333-3333-333333333333'
$global:wdlBackendTest_secretMarker = 'DO-NOT-EXPOSE-UPSTREAM-BODY'
$global:wdlBackendTest_scenario = 'absent'
$global:wdlBackendTest_httpCalls = [System.Collections.Generic.List[object]]::new()
$global:wdlBackendTest_response = $null

function Push-OutputBinding {
    param([string]$Name, [object]$Value)
    Assert-True ($Name -eq 'Response') 'Unexpected output binding.'
    $global:wdlBackendTest_response = $Value
}

function Throw-UpstreamTestError {
    param([int]$StatusCode, [string]$Detail)
    $http = [System.Net.Http.HttpResponseMessage]::new([System.Net.HttpStatusCode]$StatusCode)
    $exception = [Microsoft.PowerShell.Commands.HttpResponseException]::new($global:wdlBackendTest_secretMarker, $http)
    $record = [System.Management.Automation.ErrorRecord]::new($exception, 'MockUpstreamFailure', 'InvalidOperation', $null)
    $record.ErrorDetails = [System.Management.Automation.ErrorDetails]::new($Detail)
    throw $record
}

function Invoke-RestMethod {
    [CmdletBinding()]
    param([string]$Method, [string]$Uri, [object]$Headers, [object]$Body, [string]$ContentType)
    $global:wdlBackendTest_httpCalls.Add([pscustomobject]@{ Method = $Method; Uri = $Uri })
    if ($Uri -like 'https://login.microsoftonline.com/*/oauth2/v2.0/token') {
        Assert-True ($Method -eq 'POST') 'Token request must use POST.'
        Assert-True ($Body.scope -eq 'https://graph.microsoft.com/.default') 'Unexpected token scope.'
        Assert-True (-not [string]::IsNullOrWhiteSpace($Body.client_assertion)) 'Certificate assertion missing.'
        $tenant = ([uri]$Uri).Segments[1].TrimEnd('/')
        if ($global:wdlBackendTest_scenario -eq 'token401' -or ($global:wdlBackendTest_scenario -eq 'partial' -and $tenant -eq $global:wdlBackendTest_tenantB)) {
            Throw-UpstreamTestError 401 (@{
                error = 'invalid_client'
                error_codes = @(700027)
                error_description = $global:wdlBackendTest_secretMarker
                correlation_id = $global:wdlBackendTest_correlation
            } | ConvertTo-Json -Compress)
        }
        return @{ access_token = "mock-token-$tenant" }
    }

    Assert-True ($Uri -like 'https://graph.microsoft.com/beta/deviceManagement/tenantAssociatedDevices*') 'Unexpected outbound endpoint.'
    $tenant = ([string]$Headers.Authorization).Replace('Bearer mock-token-', '')
    if ($global:wdlBackendTest_scenario.StartsWith('operation-')) {
        $scenario = $global:wdlBackendTest_scenario
        if ($Method -eq 'DELETE') {
            Assert-True ($tenant -eq $global:wdlBackendTest_tenantA -and $Uri.EndsWith("/association-$tenant")) 'Delete must target the exact source record.'
            if ($scenario -eq 'operation-delete403') {
                Throw-UpstreamTestError 403 '{"error":{"code":"Authorization_RequestDenied","message":"DO-NOT-EXPOSE-UPSTREAM-BODY"}}'
            }
            $global:wdlBackendTest_graphState[$tenant] = $false
            return
        }
        if ($Method -eq 'POST') {
            Assert-True ($Uri.EndsWith('/importTenantAssociatedDevice')) 'Unexpected mutation endpoint.'
            Assert-True ($tenant -eq $global:wdlBackendTest_tenantB) 'Import must target tenant B.'
            Assert-True (($Body | ConvertFrom-Json).deviceLink -eq 'synthetic-device-link') 'Import lost the DeviceLink payload.'
            $global:wdlBackendTest_postAttempted = $true
            if ($scenario -match '^operation-import(403|409|429)$') {
                $status = [int]$Matches[1]
                $code = switch ($status) { 403 { 'Authorization_RequestDenied' } 409 { 'BadRequest' } 429 { 'TooManyRequests' } }
                Throw-UpstreamTestError $status (@{ error = @{ code = $code; message = $global:wdlBackendTest_secretMarker; innerError = @{ 'request-id' = $global:wdlBackendTest_correlation } } } | ConvertTo-Json -Depth 5 -Compress)
            }
            $global:wdlBackendTest_graphState[$tenant] = $true
            if ($scenario -eq 'operation-committed500') {
                Throw-UpstreamTestError 500 '{"error":{"code":"InternalServerError","message":"DO-NOT-EXPOSE-UPSTREAM-BODY"}}'
            }
            return @{ id = "association-$tenant"; associationState = 'preassociated' }
        }
        Assert-True ($Method -eq 'GET') 'Unexpected operation method.'
        if ($scenario -eq 'operation-lookup403' -or ($scenario -eq 'operation-verify503' -and $global:wdlBackendTest_postAttempted)) {
            Throw-UpstreamTestError 503 '{"error":{"code":"ServiceNotAvailable","message":"DO-NOT-EXPOSE-UPSTREAM-BODY"}}'
        }
        if ($global:wdlBackendTest_graphState[$tenant]) {
            return @{ value = @([pscustomobject]@{ id = "association-$tenant"; serialNumber = $global:wdlBackendTest_serial; associationState = 'preassociated' }) }
        }
        return @{ value = @() }
    }
    Assert-True ($Method -eq 'GET') 'Lookup must never mutate Graph state.'
    $fallback = -not $Uri.Contains('?')
    if ($global:wdlBackendTest_scenario -eq 'graph401' -or ($global:wdlBackendTest_scenario -eq 'fallback401' -and $fallback)) {
        Throw-UpstreamTestError 401 (@{
            error = @{ code = 'InvalidAuthenticationToken'; message = $global:wdlBackendTest_secretMarker }
        } | ConvertTo-Json -Depth 4 -Compress)
    }
    if ($global:wdlBackendTest_scenario -eq 'malformed401') {
        Throw-UpstreamTestError 401 "<html>$($global:wdlBackendTest_secretMarker)</html>"
    }
    if ($global:wdlBackendTest_scenario -eq 'duplicate' -or
        (($global:wdlBackendTest_scenario -eq 'one' -or $global:wdlBackendTest_scenario -eq 'partial') -and $tenant -eq $global:wdlBackendTest_tenantA) -or
        ($global:wdlBackendTest_scenario -eq 'fallbackMatch' -and $fallback -and $tenant -eq $global:wdlBackendTest_tenantA)) {
        return @{ value = @([pscustomobject]@{
            id = "association-$tenant"
            serialNumber = $global:wdlBackendTest_serial
            associationState = 'preassociated'
        }) }
    }
    return @{ value = @() }
}

function Invoke-LookupTest {
    param([string]$Scenario, [string]$ApiKey = 'synthetic-api-key', [string]$TenantId)
    $global:wdlBackendTest_scenario = $Scenario
    $global:wdlBackendTest_httpCalls.Clear()
    $global:wdlBackendTest_response = $null
    $query = @{ serialNumber = $global:wdlBackendTest_serial }
    if ($TenantId) { $query.tenantId = $TenantId }
    $request = [pscustomobject]@{
        Headers = @{ 'X-WindowsDeviceLink-Key' = $ApiKey }
        Query = $query
    }
    $logs = & $global:wdlBackendTest_lookupScript -Request $request -TriggerMetadata @{} *>&1
    Assert-True ($null -ne $global:wdlBackendTest_response) "$Scenario produced no HTTP response."
    $body = $global:wdlBackendTest_response.Body | ConvertFrom-Json
    $captured = ($logs | Out-String) + [string]$global:wdlBackendTest_response.Body
    Assert-True (-not $captured.Contains($global:wdlBackendTest_secretMarker)) "$Scenario leaked upstream exception/body content."
    Assert-True (-not $captured.Contains('synthetic-api-key')) "$Scenario leaked the API key."
    Assert-True (-not $captured.Contains('mock-token-')) "$Scenario leaked an access token."
    [pscustomobject]@{ StatusCode = $global:wdlBackendTest_response.StatusCode; Body = $body }
}

function Invoke-WorkflowTest {
    param(
        [ValidateSet('Register','Reconcile')][string]$FunctionName,
        [string]$Scenario,
        [bool]$SourcePresent = $false,
        [string]$SourceTenantId,
        [string]$TargetTenantId = $global:wdlBackendTest_tenantB
    )
    $global:wdlBackendTest_scenario = $Scenario
    $global:wdlBackendTest_httpCalls.Clear()
    $global:wdlBackendTest_response = $null
    $global:wdlBackendTest_postAttempted = $false
    $global:wdlBackendTest_graphState = @{}
    $global:wdlBackendTest_graphState[$global:wdlBackendTest_tenantA] = $SourcePresent
    $global:wdlBackendTest_graphState[$global:wdlBackendTest_tenantB] = $false
    $requestId = [guid]::NewGuid().ToString()
    $body = @{
        schemaVersion = 1
        requestType = if ($FunctionName -eq 'Register') { 'DeviceLinkPreassociation' } else { 'DeviceLinkReconcile' }
        requestId = $requestId
        tenantId = $TargetTenantId
        targetTenantId = $TargetTenantId
        device = @{ serialNumber = $global:wdlBackendTest_serial; deviceLink = 'synthetic-device-link' }
    }
    if ($SourceTenantId) { $body.sourceTenantId = $SourceTenantId }
    $request = [pscustomobject]@{
        Headers = @{ 'X-WindowsDeviceLink-Key' = 'synthetic-api-key'; 'X-WindowsDeviceLink-Schema' = '1'; 'X-WindowsDeviceLink-RequestId' = $requestId }
        Body = $body
    }
    $path = Join-Path $global:wdlBackendTest_stageRoot "$FunctionName-WindowsDeviceLink/run.ps1"
    $logs = & $path -Request $request -TriggerMetadata @{} *>&1
    Assert-True ($null -ne $global:wdlBackendTest_response) "$FunctionName / $Scenario produced no response."
    $captured = ($logs | Out-String) + [string]$global:wdlBackendTest_response.Body
    foreach ($sensitive in @($global:wdlBackendTest_secretMarker,'synthetic-api-key','mock-token-','synthetic-device-link')) {
        Assert-True (-not $captured.Contains($sensitive)) "$FunctionName / $Scenario leaked sensitive material."
    }
    [pscustomobject]@{
        StatusCode = $global:wdlBackendTest_response.StatusCode
        Body = $global:wdlBackendTest_response.Body | ConvertFrom-Json
        DeleteCount = @($global:wdlBackendTest_httpCalls.ToArray() | Where-Object Method -eq DELETE).Count
        ImportCount = @($global:wdlBackendTest_httpCalls.ToArray() | Where-Object { $_.Method -eq 'POST' -and $_.Uri.EndsWith('/importTenantAssociatedDevice') }).Count
    }
}

$stageRoot = Join-Path ([IO.Path]::GetTempPath()) ('wdl-backend-test-' + [guid]::NewGuid().ToString('N'))
$savedEnvironment = @{}
$environmentNames = @(
    'WINDOWSDEVICELINK_API_KEY','WINDOWSDEVICELINK_CLIENT_ID',
    'WINDOWSDEVICELINK_ALLOWED_TENANTS','WINDOWSDEVICELINK_TENANT_NAMES_JSON',
    'WINDOWSDEVICELINK_CERTIFICATE_PFX_BASE64','WINDOWSDEVICELINK_CERTIFICATE_PASSWORD',
    'WINDOWSDEVICELINK_CLIENT_SECRET'
)
foreach ($name in $environmentNames) {
    $savedEnvironment[$name] = [Environment]::GetEnvironmentVariable($name)
}
$rsa = $null
$certificate = $null
try {
    $null = New-Item -ItemType Directory -Path $stageRoot
    Copy-Item -Path (Join-Path $FunctionRoot '*') -Destination $stageRoot -Recurse
    foreach ($config in Get-ChildItem $stageRoot -Filter function.json -Recurse) {
        Copy-Item (Join-Path $stageRoot 'shared/BackendAuth.ps1') $config.Directory.FullName -Force
        Copy-Item (Join-Path $stageRoot 'shared/AssociationOperations.ps1') $config.Directory.FullName -Force
    }
    $global:wdlBackendTest_lookupScript = Join-Path $stageRoot 'Lookup-WindowsDeviceLink/run.ps1'
    $global:wdlBackendTest_stageRoot = $stageRoot
    foreach ($path in Get-ChildItem $stageRoot -Filter '*.ps1' -Recurse) {
        $tokens = $null
        $parseErrors = $null
        $null = [System.Management.Automation.Language.Parser]::ParseFile($path.FullName, [ref]$tokens, [ref]$parseErrors)
        Assert-True ($parseErrors.Count -eq 0) "Parse errors in $($path.FullName)"
    }

    $rsa = [System.Security.Cryptography.RSA]::Create(2048)
    $request = [System.Security.Cryptography.X509Certificates.CertificateRequest]::new(
        'CN=WindowsDeviceLink-Offline-Test', $rsa,
        [System.Security.Cryptography.HashAlgorithmName]::SHA256,
        [System.Security.Cryptography.RSASignaturePadding]::Pkcs1
    )
    $certificate = $request.CreateSelfSigned([DateTimeOffset]::UtcNow.AddMinutes(-5), [DateTimeOffset]::UtcNow.AddHours(1))
    $env:WINDOWSDEVICELINK_API_KEY = 'synthetic-api-key'
    $env:WINDOWSDEVICELINK_CLIENT_ID = '44444444-4444-4444-4444-444444444444'
    $env:WINDOWSDEVICELINK_ALLOWED_TENANTS = "$global:wdlBackendTest_tenantA,$global:wdlBackendTest_tenantB"
    $env:WINDOWSDEVICELINK_TENANT_NAMES_JSON = "{`"$global:wdlBackendTest_tenantA`":`"Tenant A`",`"$global:wdlBackendTest_tenantB`":`"Tenant B`"}"
    $env:WINDOWSDEVICELINK_CERTIFICATE_PFX_BASE64 = [Convert]::ToBase64String($certificate.Export([System.Security.Cryptography.X509Certificates.X509ContentType]::Pfx))
    $env:WINDOWSDEVICELINK_CERTIFICATE_PASSWORD = ''
    $env:WINDOWSDEVICELINK_CLIENT_SECRET = ''

    $global:wdlBackendTest_response = $null
    $tenantRequest = [pscustomobject]@{ Headers=@{ 'X-WindowsDeviceLink-Key'='synthetic-api-key' } }
    $tenantLogs = & (Join-Path $stageRoot 'Get-WindowsDeviceLinkTenants/run.ps1') -Request $tenantRequest -TriggerMetadata @{} *>&1
    $tenantBody = $global:wdlBackendTest_response.Body | ConvertFrom-Json
    Assert-True ($global:wdlBackendTest_response.StatusCode -eq 200 -and $tenantBody.success -eq $true -and $tenantBody.tenantCount -eq 2) 'Tenant catalog did not return both allowed tenants.'
    Assert-True ($tenantBody.apiVersion -eq '1.0' -and $tenantBody.minimumModuleVersion -eq '0.10.0') 'Tenant catalog did not return the expected compatibility contract.'
    Assert-True (@($tenantBody.capabilities).Count -ge 3 -and 'Reconcile' -in @($tenantBody.capabilities)) 'Tenant catalog did not advertise required capabilities.'
    Assert-True (@($tenantBody.tenants | Where-Object name -eq 'Tenant A').Count -eq 1) 'Tenant catalog lost its friendly-name mapping.'
    Assert-True (-not (($tenantLogs | Out-String) + $global:wdlBackendTest_response.Body).Contains('synthetic-api-key')) 'Tenant catalog leaked the API key.'
    $global:wdlBackendTest_response = $null
    $tenantRequest.Headers['X-WindowsDeviceLink-Key'] = 'wrong-key'
    $null = & (Join-Path $stageRoot 'Get-WindowsDeviceLinkTenants/run.ps1') -Request $tenantRequest -TriggerMetadata @{} *>&1
    Assert-True ($global:wdlBackendTest_response.StatusCode -eq 401) 'Tenant catalog must reject an invalid API key.'
    Write-Host 'PASS: authenticated tenant catalog and friendly names'

    $result = Invoke-LookupTest absent
    Assert-True ($result.StatusCode -eq 200) 'Absent device must return HTTP 200.'
    Assert-True ($result.Body.matchCount -eq 0 -and $result.Body.successfulTenantCount -eq 2 -and $result.Body.failedTenantCount -eq 0) 'Absent device must have zero matches and two successful tenant searches.'
    Assert-True ($result.Body.matches -is [array] -and $result.Body.matches.Count -eq 0) 'Zero matches must serialize as an empty JSON array.'
    Assert-True ($result.Body.tenantErrors -is [array] -and $result.Body.tenantErrors.Count -eq 0) 'Zero failures must serialize as an empty JSON array.'
    Assert-True ($global:wdlBackendTest_httpCalls.Count -eq 6) 'Absent device must check filtered and fallback collections in both tenants.'
    Write-Host 'PASS: absent device / empty Graph collections'

    foreach ($case in @('one','duplicate','fallbackMatch')) {
        $result = Invoke-LookupTest $case
        $expectedCount = if ($case -eq 'duplicate') { 2 } else { 1 }
        Assert-True ($result.Body.matchCount -eq $expectedCount -and $result.Body.failedTenantCount -eq 0) "$case returned incorrect results."
        Assert-True ($result.Body.matches -is [array] -and $result.Body.matches.Count -eq $expectedCount) "$case did not preserve JSON array shape."
        Write-Host "PASS: $case"
    }

    $result = Invoke-LookupTest token401
    Assert-True ($result.StatusCode -eq 200 -and $result.Body.successfulTenantCount -eq 0 -and $result.Body.failedTenantCount -eq 2) 'Two token failures must return the partial-results contract without crashing.'
    foreach ($errorItem in $result.Body.tenantErrors) {
        Assert-True ($errorItem.stage -eq 'GraphToken' -and $errorItem.statusCode -eq 401) 'Token failure stage/status missing.'
        Assert-True ($errorItem.upstreamErrorCode -eq 'invalid_client' -and $errorItem.aadstsCodes[0] -eq 'AADSTS700027') 'Sanitized Entra diagnostic missing.'
        Assert-True ($errorItem.upstreamCorrelationId -eq $global:wdlBackendTest_correlation) 'Entra correlation ID missing.'
    }
    Assert-True ($global:wdlBackendTest_httpCalls.Count -eq 2) 'Token failures must not call Graph.'
    Write-Host 'PASS: both tenants return token 401; sanitized diagnostics'

    foreach ($case in @('graph401','fallback401','malformed401')) {
        $result = Invoke-LookupTest $case
        $expectedStage = if ($case -eq 'fallback401') { 'GraphLookupFallback' } else { 'GraphLookup' }
        Assert-True ($result.Body.failedTenantCount -eq 2) "$case must retain both tenant errors."
        foreach ($errorItem in $result.Body.tenantErrors) {
            Assert-True ($errorItem.stage -eq $expectedStage -and $errorItem.statusCode -eq 401) "$case stage/status incorrect."
        }
        Write-Host "PASS: $case"
    }

    $result = Invoke-LookupTest partial
    Assert-True ($result.Body.successfulTenantCount -eq 1 -and $result.Body.failedTenantCount -eq 1 -and $result.Body.matchCount -eq 1) 'Partial failure lost successful results or coverage information.'
    Write-Host 'PASS: partial failure retains successful match'

    $result = Invoke-LookupTest absent -ApiKey 'incorrect-api-key'
    Assert-True ($result.StatusCode -eq 401 -and $global:wdlBackendTest_httpCalls.Count -eq 0) 'Invalid API key must be rejected before outbound HTTP.'
    $result = Invoke-LookupTest absent -TenantId '55555555-5555-5555-5555-555555555555'
    Assert-True ($result.StatusCode -eq 403 -and $global:wdlBackendTest_httpCalls.Count -eq 0) 'Disallowed tenant must be rejected before outbound HTTP.'
    Write-Host 'PASS: API key and tenant boundaries'

    . (Join-Path $stageRoot 'shared/BackendAuth.ps1')
    . (Join-Path $stageRoot 'shared/AssociationOperations.ps1')
    $global:wdlBackendTest_scenario = 'absent'
    $empty = Get-WindowsDeviceLinkTenantAssociation -TenantId $global:wdlBackendTest_tenantA -SerialNumber $global:wdlBackendTest_serial -ClientId $env:WINDOWSDEVICELINK_CLIENT_ID
    Assert-True ($empty.Matches -is [array] -and $empty.Matches.Count -eq 0) 'Shared association lookup must support an absent device.'
    Write-Host 'PASS: shared association helper accepts an empty collection'

    foreach ($status in @(403,409,429)) {
        $result = Invoke-WorkflowTest Reconcile "operation-import$status" -SourcePresent $true -SourceTenantId $global:wdlBackendTest_tenantA
        Assert-True ($result.StatusCode -eq 502 -and $result.Body.error -eq 'MoveIncomplete' -and $result.Body.decision -eq 'Move') 'Failed target import must retain the MoveIncomplete contract.'
        Assert-True ($result.Body.stage -eq 'GraphImportTarget' -and $result.Body.upstreamStatusCode -eq $status -and $result.Body.upstreamErrorCode) 'Move failure lost its upstream diagnostic.'
        Assert-True ($result.Body.upstreamCorrelationId -eq $global:wdlBackendTest_correlation) 'Move failure lost its Graph request ID.'
        Assert-True ($result.DeleteCount -eq 1 -and $result.ImportCount -eq 1) 'A move must not retry DELETE or POST.'
        Assert-True (-not $global:wdlBackendTest_graphState[$global:wdlBackendTest_tenantA] -and -not $global:wdlBackendTest_graphState[$global:wdlBackendTest_tenantB]) 'Failed target import must not claim a registered device.'
        Write-Host "PASS: Move target HTTP $status; safe diagnostics; one DELETE and one POST"
    }

    foreach ($functionName in @('Register','Reconcile')) {
        $result = Invoke-WorkflowTest $functionName 'operation-import403'
        Assert-True ($result.StatusCode -eq 502 -and $result.Body.upstreamStatusCode -eq 403 -and $result.Body.stage -eq 'GraphImportTarget') "$functionName creation failure lost its diagnostic."
        Assert-True ($result.DeleteCount -eq 0 -and $result.ImportCount -eq 1) 'Creation from empty state must not delete or retry.'
        $result = Invoke-WorkflowTest $functionName 'operation-success'
        Assert-True ($result.StatusCode -eq 200 -and $result.Body.success -and $result.Body.associationState -eq 'preassociated') "$functionName recovery failed."
        Assert-True ($result.DeleteCount -eq 0 -and $result.ImportCount -eq 1) 'Recovery must create once without deletion.'
        if ($functionName -eq 'Reconcile') { Assert-True ($result.Body.decision -eq 'New') 'Empty-state recovery must use New.' }
        Write-Host "PASS: $functionName recovery from empty state; no DELETE"
    }

    $result = Invoke-WorkflowTest Reconcile 'operation-success' -SourcePresent $true -SourceTenantId $global:wdlBackendTest_tenantA
    Assert-True ($result.StatusCode -eq 200 -and $result.Body.decision -eq 'Move' -and $result.DeleteCount -eq 1 -and $result.ImportCount -eq 1) 'Successful Move regressed.'
    $result = Invoke-WorkflowTest Reconcile 'operation-committed500' -SourcePresent $true -SourceTenantId $global:wdlBackendTest_tenantA
    Assert-True ($result.StatusCode -eq 200 -and $result.Body.success -and $result.ImportCount -eq 1) 'A committed target must be verified without a repeated POST.'
    Write-Host 'PASS: successful Move and ambiguous POST with verified commit'

    $result = Invoke-WorkflowTest Reconcile 'operation-delete403' -SourcePresent $true -SourceTenantId $global:wdlBackendTest_tenantA
    Assert-True ($result.StatusCode -eq 502 -and $result.Body.stage -eq 'GraphDeleteSource' -and $result.Body.upstreamStatusCode -eq 403 -and $result.DeleteCount -eq 1 -and $result.ImportCount -eq 0) 'Failed source deletion must block import and preserve its diagnostic.'
    Write-Host 'PASS: source DELETE failure blocks import'

    foreach ($present in @($false,$true)) {
        $source = if ($present) { $global:wdlBackendTest_tenantA } else { $null }
        $result = Invoke-WorkflowTest Reconcile 'operation-verify503' -SourcePresent $present -SourceTenantId $source
        Assert-True ($result.StatusCode -eq 502 -and $result.Body.stage -eq 'GraphVerifyTarget' -and $result.Body.upstreamStatusCode -eq 503 -and $result.ImportCount -eq 1) 'Verification read failures must return structured diagnostics without mutation retries.'
    }
    Write-Host 'PASS: verification failure after New and Move'

    $result = Invoke-WorkflowTest Reconcile 'operation-lookup403' -SourcePresent $true -SourceTenantId $global:wdlBackendTest_tenantA
    Assert-True ($result.Body.error -eq 'LookupIncomplete' -and $result.DeleteCount -eq 0 -and $result.ImportCount -eq 0) 'Incomplete lookup must prevent every mutation.'
    $result = Invoke-WorkflowTest Reconcile 'operation-success' -SourcePresent $false -SourceTenantId $global:wdlBackendTest_tenantA
    Assert-True ($result.Body.error -eq 'SourceStateMismatch' -and $result.DeleteCount -eq 0 -and $result.ImportCount -eq 0) 'An old Move request must not become New when the source is absent.'
    $result = Invoke-WorkflowTest Reconcile 'operation-success' -SourcePresent $true -SourceTenantId $global:wdlBackendTest_tenantA -TargetTenantId $global:wdlBackendTest_tenantA
    Assert-True ($result.Body.decision -eq 'Update' -and -not $result.Body.changed -and $result.DeleteCount -eq 0 -and $result.ImportCount -eq 0) 'Same-tenant Update must not mutate state.'
    Write-Host 'PASS: incomplete lookup, stale source and same-tenant Update guards'
    Write-Host "PASS: Azure backend runtime regressions on PowerShell $($PSVersionTable.PSVersion). No live cloud calls were made."
}
finally {
    foreach ($name in $environmentNames) { [Environment]::SetEnvironmentVariable($name, $savedEnvironment[$name]) }
    if ($certificate) { $certificate.Dispose() }
    if ($rsa) { $rsa.Dispose() }
    Remove-Variable -Name wdlBackendTest_* -Scope Global -ErrorAction SilentlyContinue
    Remove-Item $stageRoot -Recurse -Force -ErrorAction SilentlyContinue
}
