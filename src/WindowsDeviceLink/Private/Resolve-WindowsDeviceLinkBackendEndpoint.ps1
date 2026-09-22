function Resolve-WindowsDeviceLinkBackendEndpoint {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateNotNull()][uri]$BackendUri,
        [Parameter(Mandatory)][ValidateSet('lookup','preassociate','reconcile')][string]$Route
    )

    if (-not $BackendUri.IsAbsoluteUri -or $BackendUri.Scheme -ne 'https') {
        throw '-BackendUri must be an absolute HTTPS URI.'
    }
    if (-not [string]::IsNullOrWhiteSpace($BackendUri.Query) -or -not [string]::IsNullOrWhiteSpace($BackendUri.Fragment)) {
        throw '-BackendUri must not contain a query string or fragment.'
    }

    $base = $BackendUri.AbsoluteUri.TrimEnd('/')
    if ($base -notmatch '(?i)/api/devicelink$') {
        throw "-BackendUri must point to the Function API base path ending in '/api/devicelink'."
    }

    [uri]("$base/$Route")
}