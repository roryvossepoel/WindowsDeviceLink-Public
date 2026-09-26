function Resolve-WindowsDeviceLinkTokenAccountName {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Token
    )

    try {
        $segments = $Token.Split('.')
        if ($segments.Count -lt 2) { return $null }

        $payload = $segments[1].Replace('-','+').Replace('_','/')
        switch ($payload.Length % 4) {
            2 { $payload += '==' }
            3 { $payload += '=' }
        }

        $claims = [System.Text.Encoding]::UTF8.GetString(
            [Convert]::FromBase64String($payload)
        ) | ConvertFrom-Json -ErrorAction Stop

        foreach ($claimName in @('preferred_username','upn','unique_name')) {
            $claimValue = [string]$claims.$claimName
            if (-not [string]::IsNullOrWhiteSpace($claimValue)) { return $claimValue }
        }
    }
    catch {
        # Account extraction is metadata-only and best-effort.
    }

    return $null
}
