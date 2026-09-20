function Resolve-WindowsDeviceLinkAccessTokenTenantId {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$AccessToken
    )

    try {
        $segments = $AccessToken.Split('.')
        if ($segments.Count -lt 2) { return $null }

        $payload = $segments[1].Replace('-','+').Replace('_','/')
        switch ($payload.Length % 4) {
            2 { $payload += '==' }
            3 { $payload += '=' }
        }

        $claims = [System.Text.Encoding]::UTF8.GetString(
            [Convert]::FromBase64String($payload)
        ) | ConvertFrom-Json -ErrorAction Stop

        if ($claims.tid) { return [string]$claims.tid }
    }
    catch {
        # Tenant extraction is metadata-only and best-effort.
    }

    return $null
}
