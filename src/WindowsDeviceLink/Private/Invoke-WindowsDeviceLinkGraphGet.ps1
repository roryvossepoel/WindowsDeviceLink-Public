function Invoke-WindowsDeviceLinkGraphGet {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$Uri,
        [AllowNull()][string]$AccessToken,
        [switch]$SdkMode,
        [ValidateRange(1, 5)][int]$MaxAttempts = 3,
        [ValidateRange(0, 60)][int]$MaxRetryAfterSeconds = 30,
        [scriptblock]$RequestScript,
        [scriptblock]$SleepScript
    )

    $attempt = 0
    while ($true) {
        $attempt++
        try {
            if ($RequestScript) { return & $RequestScript $Uri ([bool]$SdkMode) $AccessToken }
            if ($SdkMode) { return Invoke-MgGraphRequest -Method GET -Uri $Uri -ErrorAction Stop }
            if ([string]::IsNullOrWhiteSpace($AccessToken)) { throw 'A native Graph GET requires an access token.' }
            return Invoke-RestMethod -Method GET -Uri $Uri -Headers @{ Authorization = "Bearer $AccessToken" } -ErrorAction Stop
        }
        catch {
            $errorRecord = $_
            $statusCode = $null
            try {
                if ($errorRecord.Exception.Response -and $errorRecord.Exception.Response.StatusCode) { $statusCode = [int]$errorRecord.Exception.Response.StatusCode }
            }
            catch { $statusCode = $null }

            if ($null -eq $statusCode -and $errorRecord.Exception.Message -match '(?<!\d)(401|403|404|409|429|500|502|503|504)(?!\d)') { $statusCode = [int]$Matches[1] }

            $transportRetryable = $false
            try {
                if ($errorRecord.Exception -is [System.Net.WebException]) {
                    $transportRetryable = $errorRecord.Exception.Status -in @(
                        [System.Net.WebExceptionStatus]::Timeout,
                        [System.Net.WebExceptionStatus]::ConnectFailure,
                        [System.Net.WebExceptionStatus]::ConnectionClosed,
                        [System.Net.WebExceptionStatus]::NameResolutionFailure,
                        [System.Net.WebExceptionStatus]::ReceiveFailure,
                        [System.Net.WebExceptionStatus]::SendFailure
                    )
                }
            }
            catch {}
            if (-not $transportRetryable -and $null -eq $statusCode) {
                $transportRetryable = $errorRecord.Exception.Message -match '(?i)(timed out|timeout|temporarily unavailable|connection (?:was )?closed|remote name could not be resolved|name resolution)'
            }

            $retryable = ($statusCode -in @(429,500,502,503,504)) -or $transportRetryable
            if (-not $retryable -or $attempt -ge $MaxAttempts) {
                $safeDetail = Protect-WindowsDeviceLinkSensitiveText -Text ([string]$errorRecord.Exception.Message) -SensitiveValue @($AccessToken)
                if ($statusCode) { throw "Microsoft Graph GET failed with HTTP $statusCode. $safeDetail" }
                throw "Microsoft Graph GET failed. $safeDetail"
            }

            $retryAfter = $null
            if ($statusCode -eq 429) {
                try { $retryAfter = [string]$errorRecord.Exception.Response.Headers['Retry-After'] }
                catch { $retryAfter = $null }
            }

            $delaySeconds = Get-WindowsDeviceLinkGraphRetryDelay -Attempt $attempt -StatusCode $statusCode -RetryAfter $retryAfter -MaxRetryAfterSeconds $MaxRetryAfterSeconds
            $reason = if ($null -ne $statusCode) { "HTTP $statusCode" } else { 'a transient transport failure' }
            Write-Information -InformationAction Continue -MessageData ("Microsoft Graph GET encountered {0}; retrying attempt {1}/{2} after {3} second(s)." -f $reason,($attempt+1),$MaxAttempts,$delaySeconds)
            if ($delaySeconds -gt 0) { if ($SleepScript) { & $SleepScript $delaySeconds } else { Start-Sleep -Seconds $delaySeconds } }
        }
    }
}
