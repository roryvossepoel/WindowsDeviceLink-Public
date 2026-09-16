function Get-WindowsDeviceLinkGraphRetryDelay {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateRange(1, 5)]
        [int]$Attempt,

        [AllowNull()]
        [Nullable[int]]$StatusCode,

        [AllowNull()]
        [string]$RetryAfter,

        [ValidateRange(0, 60)]
        [int]$MaxRetryAfterSeconds = 30,

        [datetimeoffset]$NowUtc = [datetimeoffset]::UtcNow
    )

    $delaySeconds = [int][math]::Min([math]::Pow(2, $Attempt - 1), $MaxRetryAfterSeconds)

    if ($StatusCode -ne 429 -or [string]::IsNullOrWhiteSpace($RetryAfter)) {
        return $delaySeconds
    }

    $retryAfterSeconds = 0
    if ([int]::TryParse($RetryAfter.Trim(), [ref]$retryAfterSeconds)) {
        return [int][math]::Min([math]::Max(0, $retryAfterSeconds), $MaxRetryAfterSeconds)
    }

    $retryAfterDate = [datetimeoffset]::MinValue
    $styles = [System.Globalization.DateTimeStyles]::AllowWhiteSpaces -bor [System.Globalization.DateTimeStyles]::AssumeUniversal -bor [System.Globalization.DateTimeStyles]::AdjustToUniversal
    if ([datetimeoffset]::TryParse($RetryAfter, [System.Globalization.CultureInfo]::InvariantCulture, $styles, [ref]$retryAfterDate)) {
        $secondsUntilRetry = [math]::Ceiling(($retryAfterDate.ToUniversalTime() - $NowUtc.ToUniversalTime()).TotalSeconds)
        return [int][math]::Min([math]::Max(0, $secondsUntilRetry), $MaxRetryAfterSeconds)
    }

    $delaySeconds
}
