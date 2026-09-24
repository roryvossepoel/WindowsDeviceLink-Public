using namespace System.Security.Cryptography
using namespace System.Security.Cryptography.X509Certificates
using namespace System.Text

function Get-WindowsDeviceLinkBackendMetadata {
    [ordered]@{
        apiVersion = '1.0'
        minimumModuleVersion = '0.10.0'
        capabilities = @('TenantCatalog','MultitenantLookup','Reconcile','Offboarding')
    }
}

function Test-WindowsDeviceLinkSharedSecret {
    param(
        [Parameter(Mandatory)][string]$Expected,
        [Parameter(Mandatory)][string]$Provided
    )

    $left = [Encoding]::UTF8.GetBytes($Expected)
    $right = [Encoding]::UTF8.GetBytes($Provided)
    if ($left.Length -ne $right.Length) { return $false }
    [CryptographicOperations]::FixedTimeEquals($left, $right)
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

function Get-WindowsDeviceLinkBackendGraphToken {
    param(
        [Parameter(Mandatory)][string]$TenantId,
        [Parameter(Mandatory)][string]$ClientId
    )

    $tokenUri = "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token"
    $certificate = Get-BackendCertificate
    $clientSecret = [Environment]::GetEnvironmentVariable('WINDOWSDEVICELINK_CLIENT_SECRET')

    if ($certificate) {
        $assertion = $null
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

function Get-WindowsDeviceLinkAllowedTenants {
    $allowedRaw = [Environment]::GetEnvironmentVariable('WINDOWSDEVICELINK_ALLOWED_TENANTS')
    @(
        $allowedRaw -split '[,;\s]+' |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
            ForEach-Object { $_.Trim().ToLowerInvariant() } |
            Sort-Object -Unique
    )
}

function Get-WindowsDeviceLinkTenantNames {
    $raw = [Environment]::GetEnvironmentVariable('WINDOWSDEVICELINK_TENANT_NAMES_JSON')
    if ([string]::IsNullOrWhiteSpace($raw)) { return @{} }

    try {
        $obj = $raw | ConvertFrom-Json -ErrorAction Stop
        $result = @{}
        foreach ($property in $obj.PSObject.Properties) {
            $result[$property.Name.ToLowerInvariant()] = [string]$property.Value
        }
        return $result
    }
    catch {
        throw 'WINDOWSDEVICELINK_TENANT_NAMES_JSON is not valid JSON.'
    }
}

function Get-WindowsDeviceLinkUpstreamFailure {
    param(
        [Parameter(Mandatory)][System.Management.Automation.ErrorRecord]$ErrorRecord
    )

    # Never return exception messages, response bodies, tokens or assertions.
    $statusCode = $null
    $upstreamErrorCode = $null
    $aadstsCodes = @()
    $upstreamCorrelationId = $null
    try {
        if ($ErrorRecord.Exception.Response -and $ErrorRecord.Exception.Response.StatusCode) {
            $statusCode = [int]$ErrorRecord.Exception.Response.StatusCode
        }
    } catch {}

    try {
        $raw = [string]$ErrorRecord.ErrorDetails.Message
        if (-not [string]::IsNullOrWhiteSpace($raw) -and $raw.Length -le 65536) {
            $detail = $raw | ConvertFrom-Json -ErrorAction Stop
            $candidate = if ($detail.error -is [string]) { $detail.error } else { [string]$detail.error.code }
            # Only known protocol codes may reach logs or API responses.
            if ($candidate -in @(
                'invalid_request','invalid_client','invalid_grant','invalid_scope',
                'unauthorized_client','unsupported_grant_type','invalid_resource',
                'interaction_required','temporarily_unavailable','server_error',
                'InvalidAuthenticationToken','Authentication_MissingOrMalformed',
                'Authorization_RequestDenied','AccessDenied','Forbidden',
                'BadRequest','Request_BadRequest','ResourceNotFound',
                'Request_ResourceNotFound','TooManyRequests','ServiceNotAvailable',
                'InternalServerError','UnknownError','NotSupported'
            )) {
                $upstreamErrorCode = [string]$candidate
            }

            $aadstsCodes = @(
                foreach ($code in @($detail.error_codes)) {
                    if ([string]$code -match '^[0-9]{3,10}$') { 'AADSTS' + [string]$code }
                }
            )
            if ($aadstsCodes.Count -eq 0 -and [string]$detail.error_description -match '\bAADSTS([0-9]{3,10})\b') {
                $aadstsCodes = @('AADSTS' + $Matches[1])
            }

            $correlation = [string]$detail.correlation_id
            if (-not $correlation -and $detail.error -isnot [string]) {
                $correlation = [string]$detail.error.innerError.'request-id'
            }
            $parsedId = [guid]::Empty
            if ([guid]::TryParse($correlation, [ref]$parsedId)) {
                $upstreamCorrelationId = $parsedId.ToString()
            }
        }
    } catch {}

    [pscustomobject]@{
        statusCode = $statusCode
        upstreamErrorCode = $upstreamErrorCode
        aadstsCodes = $aadstsCodes
        upstreamCorrelationId = $upstreamCorrelationId
    }
}

function Invoke-WindowsDeviceLinkGraphCollection {
    param(
        [Parameter(Mandatory)][string]$Uri,
        [Parameter(Mandatory)][string]$AccessToken,
        [ValidateRange(1,1000)][int]$MaxPages = 100
    )

    $headers = @{ Authorization = "Bearer $AccessToken" }
    $next = $Uri
    $page = 0

    while ($next) {
        $page++
        if ($page -gt $MaxPages) {
            throw "Graph collection paging exceeded the safety limit of $MaxPages pages."
        }

        $response = Invoke-RestMethod -Method GET -Uri $next -Headers $headers -ErrorAction Stop
        foreach ($record in @($response.value)) {
            $record
        }
        $next = [string]$response.'@odata.nextLink'
    }
}
