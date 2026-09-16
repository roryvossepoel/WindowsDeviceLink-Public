function Invoke-WindowsDeviceLinkGraphGet {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$Uri,
        [AllowNull()][string]$AccessToken,
        [switch]$SdkMode,
        [ValidateRange(1, 5)][int]$MaxAttempts = 3,
        [ValidateRange(0, 60)][int]$MaxRetryAfterSeconds = 30
    )

    $attempt = 0
    while ($true) {
        $attempt++
        try {
            if ($SdkMode) {
                return Invoke-MgGraphRequest -Method GET -Uri $Uri -ErrorAction Stop
            }

            if ([string]::IsNullOrWhiteSpace($AccessToken)) {
                throw 'A native Graph GET requires an access token.'
            }

            return Invoke-RestMethod -Method GET -Uri $Uri -Headers @{ Authorization = "Bearer $AccessToken" } -ErrorAction Stop
        }
        catch {
            $errorRecord = $_
            $statusCode = $null
            try {
                if ($errorRecord.Exception.Response -and $errorRecord.Exception.Response.StatusCode) {
                    $statusCode = [int]$errorRecord.Exception.Response.StatusCode
                }
            }
            catch { $statusCode = $null }

            if ($null -eq $statusCode -and $errorRecord.Exception.Message -match '(?<!\d)(429|502|503|504)(?!\d)') {
                $statusCode = [int]$Matches[1]
            }

            $retryable = $statusCode -in @(429, 502, 503, 504)
            if (-not $retryable -or $attempt -ge $MaxAttempts) {
                throw $errorRecord
            }

            $delaySeconds = [math]::Min([math]::Pow(2, $attempt - 1), $MaxRetryAfterSeconds)
            if ($statusCode -eq 429) {
                try {
                    $retryAfter = $errorRecord.Exception.Response.Headers['Retry-After']
                    $parsedRetryAfter = 0
                    if ($retryAfter -and [int]::TryParse([string]$retryAfter, [ref]$parsedRetryAfter)) {
                        $delaySeconds = [math]::Min($parsedRetryAfter, $MaxRetryAfterSeconds)
                    }
                }
                catch {}
            }

            Write-Information -InformationAction Continue -MessageData (
                "Microsoft Graph GET returned HTTP {0}; retrying attempt {1}/{2} after {3} second(s)." -f $statusCode, ($attempt + 1), $MaxAttempts, $delaySeconds
            )
            if ($delaySeconds -gt 0) { Start-Sleep -Seconds $delaySeconds }
        }
    }
}
