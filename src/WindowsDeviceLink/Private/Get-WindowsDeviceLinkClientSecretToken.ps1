function Get-WindowsDeviceLinkClientSecretToken {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$TenantId,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$ClientId,
        [Parameter(Mandatory)][ValidateNotNull()][securestring]$ClientSecret,
        [scriptblock]$RequestScript
    )

    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

    $credential = New-Object System.Management.Automation.PSCredential($ClientId, $ClientSecret)
    $plainSecret = $credential.GetNetworkCredential().Password
    $response = $null
    $uri = "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token"
    $body = @{
        client_id     = $ClientId
        client_secret = $plainSecret
        grant_type    = 'client_credentials'
        scope         = 'https://graph.microsoft.com/.default'
    }

    try {
        if ($RequestScript) {
            $response = & $RequestScript $uri $body
        }
        else {
            $response = Invoke-RestMethod -Method POST -Uri $uri -ContentType 'application/x-www-form-urlencoded' -Body $body -ErrorAction Stop
        }
    }
    catch {
        $statusCode = $null
        try { if ($_.Exception.Response -and $_.Exception.Response.StatusCode) { $statusCode = [int]$_.Exception.Response.StatusCode } } catch {}
        $detail = Protect-WindowsDeviceLinkSensitiveText -Text ([string]$_.Exception.Message) -SensitiveValue @($plainSecret)
        $statusText = if ($statusCode) { " HTTP $statusCode." } else { '' }
        if ([string]::IsNullOrWhiteSpace($detail)) { throw "Client-secret authentication failed for tenant '$TenantId' and client '$ClientId'.$statusText" }
        throw "Client-secret authentication failed for tenant '$TenantId' and client '$ClientId'.$statusText $detail"
    }
    finally {
        $body.client_secret = $null
        $plainSecret = $null
        $credential = $null
    }

    if (-not $response -or -not $response.access_token) {
        throw 'Client-secret authentication completed without returning an access token.'
    }

    [pscustomobject]@{
        AccessToken = [string]$response.access_token
        TokenType   = [string]$response.token_type
        ExpiresIn   = $response.expires_in
        TenantId    = $TenantId
        ClientId    = $ClientId
    }
}
