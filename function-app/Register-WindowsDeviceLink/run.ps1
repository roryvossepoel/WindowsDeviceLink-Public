using namespace System.Net
using namespace System.Security.Cryptography
using namespace System.Security.Cryptography.X509Certificates
using namespace System.Text

param($Request, $TriggerMetadata)

$ErrorActionPreference = 'Stop'

function Write-JsonResponse {
    param(
        [Parameter(Mandatory)][int]$StatusCode,
        [Parameter(Mandatory)][hashtable]$Body
    )

    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = $StatusCode
        Headers = @{ 'Content-Type' = 'application/json' }
        Body = ($Body | ConvertTo-Json -Depth 8 -Compress)
    })
}

function Get-HeaderValue {
    param(
        [Parameter(Mandatory)][object]$Headers,
        [Parameter(Mandatory)][string]$Name
    )

    foreach ($key in $Headers.Keys) {
        if ([string]$key -ieq $Name) {
            return [string]$Headers[$key]
        }
    }
    return $null
}

function Test-FixedTimeSecret {
    param(
        [Parameter(Mandatory)][string]$Expected,
        [Parameter(Mandatory)][string]$Provided
    )

    $left = [Encoding]::UTF8.GetBytes($Expected)
    $right = [Encoding]::UTF8.GetBytes($Provided)
    if ($left.Length -ne $right.Length) { return $false }
    return [CryptographicOperations]::FixedTimeEquals($left, $right)
}

function ConvertTo-Base64Url {
    param([Parameter(Mandatory)][byte[]]$Bytes)
    [Convert]::ToBase64String($Bytes).TrimEnd('=').Replace('+','-').Replace('/','_')
}

function Get-BackendCertificate {
    $pfxBase64 = [Environment]::GetEnvironmentVariable('WINDOWSDEVICELINK_CERTIFICATE_PFX_BASE64')
    if ([string]::IsNullOrWhiteSpace($pfxBase64)) { return $null }

    try {
        $bytes = [Convert]::FromBase64String($pfxBase64)
        $password = [Environment]::GetEnvironmentVariable('WINDOWSDEVICELINK_CERTIFICATE_PASSWORD')
        return [X509Certificate2]::new(
            $bytes,
            $password,
            [X509KeyStorageFlags]::EphemeralKeySet
        )
    }
    catch {
        throw 'The configured Graph certificate could not be loaded from the Key Vault-backed application setting.'
    }
}

function New-ClientAssertion {
    param(
        [Parameter(Mandatory)][string]$TenantId,
        [Parameter(Mandatory)][string]$ClientId,
        [Parameter(Mandatory)][X509Certificate2]$Certificate
    )

    $now = [DateTimeOffset]::UtcNow
    $audience = "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token"
    $header = @{
        alg = 'RS256'
        typ = 'JWT'
        x5t = ConvertTo-Base64Url -Bytes $Certificate.GetCertHash()
    } | ConvertTo-Json -Compress

    $payload = @{
        aud = $audience
        iss = $ClientId
        sub = $ClientId
        jti = [guid]::NewGuid().ToString()
        nbf = $now.AddMinutes(-2).ToUnixTimeSeconds()
        exp = $now.AddMinutes(8).ToUnixTimeSeconds()
    } | ConvertTo-Json -Compress

    $unsigned = '{0}.{1}' -f (
        ConvertTo-Base64Url -Bytes ([Encoding]::UTF8.GetBytes($header))
    ),(
        ConvertTo-Base64Url -Bytes ([Encoding]::UTF8.GetBytes($payload))
    )

    $rsa = [RSACertificateExtensions]::GetRSAPrivateKey($Certificate)
    if (-not $rsa) { throw 'The configured certificate does not contain an RSA private key.' }

    try {
        $signature = $rsa.SignData(
            [Encoding]::UTF8.GetBytes($unsigned),
            [HashAlgorithmName]::SHA256,
            [RSASignaturePadding]::Pkcs1
        )
    }
    finally {
        $rsa.Dispose()
    }

    '{0}.{1}' -f $unsigned,(ConvertTo-Base64Url -Bytes $signature)
}

function Get-GraphToken {
    param(
        [Parameter(Mandatory)][string]$TenantId,
        [Parameter(Mandatory)][string]$ClientId
    )

    $tokenUri = "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token"
    $certificate = Get-BackendCertificate
    $clientSecret = [Environment]::GetEnvironmentVariable('WINDOWSDEVICELINK_CLIENT_SECRET')

    if ($certificate) {
        try {
            $assertion = New-ClientAssertion -TenantId $TenantId -ClientId $ClientId -Certificate $certificate
            $body = @{
                client_id = $ClientId
                scope = 'https://graph.microsoft.com/.default'
                grant_type = 'client_credentials'
                client_assertion_type = 'urn:ietf:params:oauth:client-assertion-type:jwt-bearer'
                client_assertion = $assertion
            }
            return (Invoke-RestMethod -Method POST -Uri $tokenUri -ContentType 'application/x-www-form-urlencoded' -Body $body -ErrorAction Stop).access_token
        }
        finally {
            $certificate.Dispose()
            $assertion = $null
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($clientSecret)) {
        $body = @{
            client_id = $ClientId
            scope = 'https://graph.microsoft.com/.default'
            grant_type = 'client_credentials'
            client_secret = $clientSecret
        }
        return (Invoke-RestMethod -Method POST -Uri $tokenUri -ContentType 'application/x-www-form-urlencoded' -Body $body -ErrorAction Stop).access_token
    }

    throw 'No Graph credential is configured. Configure a certificate (preferred) or client secret through Key Vault-backed application settings.'
}

$requestId = Get-HeaderValue -Headers $Request.Headers -Name 'X-WindowsDeviceLink-RequestId'
$schemaHeader = Get-HeaderValue -Headers $Request.Headers -Name 'X-WindowsDeviceLink-Schema'
$providedApiKey = Get-HeaderValue -Headers $Request.Headers -Name 'X-WindowsDeviceLink-Key'
$expectedApiKey = [Environment]::GetEnvironmentVariable('WINDOWSDEVICELINK_API_KEY')

if ([string]::IsNullOrWhiteSpace($expectedApiKey)) {
    Write-JsonResponse -StatusCode 500 -Body @{
        success = $false
        requestId = $requestId
        error = 'BackendConfigurationError'
        message = 'The webhook API key is not configured on the Function App.'
    }
    return
}

if ([string]::IsNullOrWhiteSpace($providedApiKey) -or -not (Test-FixedTimeSecret -Expected $expectedApiKey -Provided $providedApiKey)) {
    Write-JsonResponse -StatusCode 401 -Body @{
        success = $false
        requestId = $requestId
        error = 'Unauthorized'
        message = 'Webhook API key validation failed.'
    }
    return
}

if ($schemaHeader -ne '1') {
    Write-JsonResponse -StatusCode 400 -Body @{
        success = $false
        requestId = $requestId
        error = 'UnsupportedSchema'
        message = 'X-WindowsDeviceLink-Schema must be 1.'
    }
    return
}

try {
    $body = $Request.Body
    if ($body -is [string]) { $body = $body | ConvertFrom-Json -ErrorAction Stop }

    if (-not $body) { throw 'Request body is empty.' }
    if ([int]$body.schemaVersion -ne 1) { throw "Unsupported schemaVersion '$($body.schemaVersion)'." }
    if ([string]$body.requestType -ne 'DeviceLinkPreassociation') { throw "Unsupported requestType '$($body.requestType)'." }
    if ([string]::IsNullOrWhiteSpace([string]$body.requestId)) { throw 'requestId is required.' }
    if ($requestId -and $requestId -ne [string]$body.requestId) { throw 'Request ID header and body do not match.' }
    $requestId = [string]$body.requestId
    if (-not $body.device -or [string]::IsNullOrWhiteSpace([string]$body.device.deviceLink)) { throw 'device.deviceLink is required.' }
}
catch {
    Write-JsonResponse -StatusCode 400 -Body @{
        success = $false
        requestId = $requestId
        error = 'InvalidRequest'
        message = $_.Exception.Message
    }
    return
}

$tenantId = [string]$body.tenantId
if ([string]::IsNullOrWhiteSpace($tenantId)) {
    $tenantId = [Environment]::GetEnvironmentVariable('WINDOWSDEVICELINK_DEFAULT_TENANT_ID')
}
if ([string]::IsNullOrWhiteSpace($tenantId)) {
    Write-JsonResponse -StatusCode 400 -Body @{
        success = $false
        requestId = $requestId
        error = 'TenantRequired'
        message = 'No tenantId was supplied and no default tenant is configured.'
    }
    return
}

$allowedRaw = [Environment]::GetEnvironmentVariable('WINDOWSDEVICELINK_ALLOWED_TENANTS')
$allowedTenants = @(
    $allowedRaw -split '[,;\s]+' |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
        ForEach-Object { $_.Trim().ToLowerInvariant() }
)
if ($allowedTenants.Count -eq 0) {
    Write-JsonResponse -StatusCode 500 -Body @{
        success = $false
        requestId = $requestId
        error = 'BackendConfigurationError'
        message = 'No allowed tenant list is configured. The backend fails closed.'
    }
    return
}
if ($tenantId.ToLowerInvariant() -notin $allowedTenants) {
    Write-JsonResponse -StatusCode 403 -Body @{
        success = $false
        requestId = $requestId
        tenantId = $tenantId
        error = 'TenantNotAllowed'
        message = 'The requested tenant is not in the backend allow list.'
    }
    return
}

$clientId = [Environment]::GetEnvironmentVariable('WINDOWSDEVICELINK_CLIENT_ID')
if ([string]::IsNullOrWhiteSpace($clientId)) {
    Write-JsonResponse -StatusCode 500 -Body @{
        success = $false
        requestId = $requestId
        error = 'BackendConfigurationError'
        message = 'WINDOWSDEVICELINK_CLIENT_ID is not configured.'
    }
    return
}

$token = $null
try {
    $token = Get-GraphToken -TenantId $tenantId -ClientId $clientId
    if ([string]::IsNullOrWhiteSpace($token)) { throw 'Microsoft identity platform returned no access token.' }

    $graphUri = 'https://graph.microsoft.com/beta/deviceManagement/tenantAssociatedDevices/importTenantAssociatedDevice'
    $graphBody = @{ deviceLink = [string]$body.device.deviceLink } | ConvertTo-Json -Compress
    $headers = @{ Authorization = "Bearer $token" }

    try {
        $result = Invoke-RestMethod -Method POST -Uri $graphUri -Headers $headers -ContentType 'application/json' -Body $graphBody -ErrorAction Stop
    }
    catch {
        $statusCode = $null
        try {
            if ($_.Exception.Response -and $_.Exception.Response.StatusCode) {
                $statusCode = [int]$_.Exception.Response.StatusCode
            }
        } catch {}

        if ($statusCode -eq 409 -or $_.Exception.Message -match '409\s+Conflict') {
            Write-JsonResponse -StatusCode 409 -Body @{
                success = $false
                requestId = $requestId
                tenantId = $tenantId
                serialNumber = [string]$body.device.serialNumber
                error = 'AssociationConflict'
                message = 'A DeviceLink pre-association already exists or conflicts with this device.'
            }
            return
        }

        throw
    }

    Write-Information "DeviceLink pre-association succeeded. RequestId=$requestId TenantId=$tenantId AssociationId=$($result.id) State=$($result.associationState)"

    Write-JsonResponse -StatusCode 200 -Body @{
        success = $true
        requestId = $requestId
        tenantId = $tenantId
        associationId = [string]$result.id
        associationState = [string]$result.associationState
        serialNumber = [string]$result.serialNumber
        manufacturer = [string]$result.manufacturerName
        model = [string]$result.modelName
        preassociationDateTime = $result.preassociationDateTime
    }
}
catch {
    Write-Warning "DeviceLink backend request failed. RequestId=$requestId TenantId=$tenantId ErrorType=$($_.Exception.GetType().Name)"
    Write-JsonResponse -StatusCode 502 -Body @{
        success = $false
        requestId = $requestId
        tenantId = $tenantId
        error = 'BackendGraphFailure'
        message = 'The backend could not complete the Microsoft Graph pre-association request.'
    }
}
finally {
    $token = $null
    $graphBody = $null
    $headers = $null
}
