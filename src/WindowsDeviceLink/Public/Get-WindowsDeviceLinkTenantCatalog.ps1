function Get-WindowsDeviceLinkTenantCatalog {
    <#
    .SYNOPSIS
    Reads a backend-independent friendly-name-to-tenant-ID catalog.
    .DESCRIPTION
    Reads tenant choices from a local JSON file, trusted HTTPS endpoint, or hashtable.
    The catalog contains no credentials and performs no Graph or Function App calls.
    Use -Name or -TenantId to resolve one explicit tenant for direct Graph cmdlets.
    .EXAMPLE
    Get-WindowsDeviceLinkTenantCatalog -Path 'E:\Config\tenants.json'
    .EXAMPLE
    $tenant = Get-WindowsDeviceLinkTenantCatalog -Path 'E:\Config\tenants.json' -Name 'Contoso'
    Get-WindowsDeviceLink | Register-WindowsDeviceLink -Method DeviceCode -TenantId $tenant.TenantId
    #>
    [CmdletBinding(DefaultParameterSetName='Path')]
    param(
        [Parameter(Mandatory,ParameterSetName='Path')][ValidateNotNullOrEmpty()][string]$Path,
        [Parameter(Mandatory,ParameterSetName='Uri')][ValidateNotNull()][uri]$Uri,
        [Parameter(Mandatory,ParameterSetName='Map')][ValidateNotNull()][hashtable]$TenantMap,
        [ValidateNotNullOrEmpty()][string]$Name,
        [guid]$TenantId
    )

    if ($PSBoundParameters.ContainsKey('Name') -and $PSBoundParameters.ContainsKey('TenantId')) {
        throw '-Name and -TenantId cannot be combined.'
    }

    switch ($PSCmdlet.ParameterSetName) {
        'Path' {
            if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "Tenant catalog '$Path' was not found." }
            try {
                $resolvedPath = (Resolve-Path -LiteralPath $Path -ErrorAction Stop).Path
                $input = Get-Content -LiteralPath $resolvedPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
            }
            catch { throw "Unable to load tenant catalog '$Path': $($_.Exception.Message)" }
            $source = $resolvedPath
        }
        'Uri' {
            if (-not $Uri.IsAbsoluteUri -or $Uri.Scheme -ne 'https') { throw '-Uri must be an absolute HTTPS URI.' }
            try { $input = Invoke-RestMethod -Method Get -Uri $Uri.AbsoluteUri -TimeoutSec 15 -ErrorAction Stop }
            catch { throw "Unable to load tenant catalog '$($Uri.AbsoluteUri)': $($_.Exception.Message)" }
            $source = $Uri.AbsoluteUri
        }
        'Map' {
            $input = $TenantMap
            $source = 'TenantMap'
        }
    }

    $entries = @(ConvertTo-WindowsDeviceLinkTenantCatalog -InputObject $input -Source $source)
    if ($PSBoundParameters.ContainsKey('Name')) {
        $entries = @($entries | Where-Object { $_.Name -ieq $Name.Trim() })
    }
    elseif ($PSBoundParameters.ContainsKey('TenantId')) {
        $id = $TenantId.ToString().ToLowerInvariant()
        $entries = @($entries | Where-Object { $_.TenantId -eq $id })
    }

    if (($PSBoundParameters.ContainsKey('Name') -or $PSBoundParameters.ContainsKey('TenantId')) -and $entries.Count -ne 1) {
        $selector = if ($PSBoundParameters.ContainsKey('Name')) { "name '$Name'" } else { "tenant ID '$TenantId'" }
        throw "The tenant catalog resolved $selector to $($entries.Count) entries; exactly one is required."
    }
    $entries
}
