function Get-WindowsDeviceLinkBackendTenant {
    <#
    .SYNOPSIS
    Returns the tenants that the WindowsDeviceLink Function backend allows.
    .DESCRIPTION
    Reads the authenticated tenant catalog from the Function backend. It performs no
    Microsoft Graph request and no state-changing operation. Tenant IDs remain the
    authoritative automation identifiers; names are display labels.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateNotNull()][uri]$BackendUri,
        [Parameter(Mandatory)][ValidateNotNull()][securestring]$BackendApiKey
    )

    $credential = New-Object System.Management.Automation.PSCredential('api-key',$BackendApiKey)
    $plainKey = $null
    try {
        $plainKey = $credential.GetNetworkCredential().Password
        $catalog = Invoke-WindowsDeviceLinkBackendTenantCatalog -BackendUri $BackendUri -BackendApiKey $plainKey
        foreach ($tenant in @($catalog.tenants)) {
            [pscustomobject]@{
                PSTypeName = 'Windows.DeviceLink.BackendTenant'
                Name = [string]$tenant.name
                TenantId = ([guid][string]$tenant.tenantId).ToString().ToLowerInvariant()
                Source = $BackendUri.AbsoluteUri
                OperationMode = 'Backend'
                Enabled = $true
                Capabilities = @($catalog.capabilities)
            }
        }
    }
    finally { $plainKey = $null; $credential = $null }
}
