function Get-WindowsDeviceLinkDeviceCodeToken {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$TenantId,

        [ValidateNotNullOrEmpty()]
        [string]$ClientId = '14d82eec-204b-4c2f-b7e8-296a70dab67e',

        [ValidateNotNullOrEmpty()]
        [string]$Scope = 'https://graph.microsoft.com/DeviceManagementServiceConfig.ReadWrite.All offline_access openid profile'
    )

    [Net.ServicePointManager]::SecurityProtocol =
        [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

    $authority = "https://login.microsoftonline.com/$TenantId/oauth2/v2.0"

    $deviceCodeResponse = Invoke-RestMethod `
        -Method POST `
        -Uri "$authority/devicecode" `
        -ContentType 'application/x-www-form-urlencoded' `
        -Body @{
            client_id = $ClientId
            scope     = $Scope
        } `
        -ErrorAction Stop

    $verificationUri = if ($deviceCodeResponse.verification_uri) { $deviceCodeResponse.verification_uri } else { $deviceCodeResponse.verification_url }

    Write-Information -InformationAction Continue -MessageData (
        "To sign in, open {0} and enter code {1}." -f $verificationUri, $deviceCodeResponse.user_code
    )

    $interval = if ($deviceCodeResponse.interval) { [int]$deviceCodeResponse.interval } else { 5 }
    $expiresAt = [DateTime]::UtcNow.AddSeconds([int]$deviceCodeResponse.expires_in)
    $lastStatusAt = [DateTime]::MinValue

    while ([DateTime]::UtcNow -lt $expiresAt) {
        Start-Sleep -Seconds $interval
        $remaining = $expiresAt - [DateTime]::UtcNow
        if (($remaining.TotalSeconds -gt 0) -and (([DateTime]::UtcNow - $lastStatusAt).TotalSeconds -ge 30)) {
            Write-Information -InformationAction Continue -MessageData ('Waiting for authentication... {0:mm\:ss} remaining.' -f $remaining)
            $lastStatusAt = [DateTime]::UtcNow
        }

        try {
            $tokenResponse = Invoke-RestMethod -Method POST -Uri "$authority/token" -ContentType 'application/x-www-form-urlencoded' -Body @{
                grant_type  = 'urn:ietf:params:oauth:grant-type:device_code'
                client_id   = $ClientId
                device_code = $deviceCodeResponse.device_code
            } -ErrorAction Stop

            if ($tokenResponse.access_token) {
                Write-Information -InformationAction Continue -MessageData 'Device code authentication succeeded.'
                return [pscustomobject]@{
                    AccessToken = $tokenResponse.access_token
                    TokenType   = $tokenResponse.token_type
                    ExpiresIn   = $tokenResponse.expires_in
                    Scope       = $tokenResponse.scope
                    ClientId    = $ClientId
                    TenantId    = $TenantId
                }
            }
        }
        catch {
            $errorCode = $null
            $errorDescription = $null
            $rawBody = if ($_.ErrorDetails -and $_.ErrorDetails.Message) { [string]$_.ErrorDetails.Message } else { $null }
            if ($rawBody) {
                try {
                    $errorJson = $rawBody | ConvertFrom-Json
                    $errorCode = [string]$errorJson.error
                    $errorDescription = [string]$errorJson.error_description
                }
                catch {
                    if ($rawBody -match 'authorization_pending|AADSTS70016') { $errorCode = 'authorization_pending' }
                    elseif ($rawBody -match 'slow_down') { $errorCode = 'slow_down' }
                    elseif ($rawBody -match 'authorization_declined|access_denied') { $errorCode = 'authorization_declined' }
                    elseif ($rawBody -match 'expired_token') { $errorCode = 'expired_token' }
                }
            }
            if (-not $errorCode) {
                $combinedErrorText = @([string]$_.Exception.Message,[string]$_,[string]$_.FullyQualifiedErrorId) -join ' '
                if ($combinedErrorText -match 'authorization_pending|AADSTS70016') { $errorCode = 'authorization_pending' }
                elseif ($combinedErrorText -match 'slow_down') { $errorCode = 'slow_down' }
                elseif ($combinedErrorText -match 'authorization_declined|access_denied') { $errorCode = 'authorization_declined' }
                elseif ($combinedErrorText -match 'expired_token') { $errorCode = 'expired_token' }
            }
            switch ($errorCode) {
                'authorization_pending' { continue }
                'slow_down' { $interval += 5; continue }
                'authorization_declined' { throw 'Device code authentication was declined by the user.' }
                'access_denied' { throw 'Device code authentication was denied.' }
                'expired_token' { throw 'The device code expired before authentication completed.' }
                default { if ($errorDescription) { throw "Device code authentication failed: $errorDescription" }; throw }
            }
        }
    }

    throw 'The device code expired before authentication completed.'
}
