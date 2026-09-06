function Get-WindowsDeviceLinkClientSecretToken {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$TenantId,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$ClientId,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [securestring]$ClientSecret
    )

    [Net.ServicePointManager]::SecurityProtocol =
        [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

    $credential = New-Object System.Management.Automation.PSCredential($ClientId, $ClientSecret)
    $plainSecret = $credential.GetNetworkCredential().Password

    try {
        $response = Invoke-RestMethod `
            -Method POST `
            -Uri "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token" `
            -ContentType 'application/x-www-form-urlencoded' `
            -Body @{
                client_id     = $ClientId
                client_secret = $plainSecret
                grant_type    = 'client_credentials'
                scope         = 'https://graph.microsoft.com/.default'
            } `
            -ErrorAction Stop
    }
    finally {
        $plainSecret = $null
        $credential = $null
    }

    if (-not $response.access_token) {
        throw 'Client-secret authentication succeeded without returning an access token.'
    }

    [pscustomobject]@{
        AccessToken = [string]$response.access_token
        TokenType   = [string]$response.token_type
        ExpiresIn   = $response.expires_in
        TenantId    = $TenantId
        ClientId    = $ClientId
    }
}
