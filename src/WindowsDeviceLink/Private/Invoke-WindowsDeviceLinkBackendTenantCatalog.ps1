function Invoke-WindowsDeviceLinkBackendTenantCatalog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateNotNull()][uri]$BackendUri,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$BackendApiKey,
        [ValidateRange(5,600)][int]$TimeoutSeconds = 120,
        [scriptblock]$RequestScript
    )

    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    $endpoint = Resolve-WindowsDeviceLinkBackendEndpoint -BackendUri $BackendUri -Route tenants
    $headers = @{ 'X-WindowsDeviceLink-Key' = $BackendApiKey }
    try {
        $response = if ($RequestScript) { & $RequestScript $endpoint $headers $TimeoutSeconds } else {
            Invoke-RestMethod -Method Get -Uri $endpoint -Headers $headers -TimeoutSec $TimeoutSeconds -ErrorAction Stop
        }
        if (-not $response -or $response.success -ne $true) { throw 'The Function tenant catalog did not succeed.' }
        if ([string]$response.apiVersion -ne '1.0') {
            throw "The Function backend API version '$($response.apiVersion)' is not supported; version 1.0 is required."
        }
        $requiredCapabilities = @('TenantCatalog','MultitenantLookup','Reconcile','Offboarding')
        $capabilities = @($response.capabilities)
        $missingCapabilities = @($requiredCapabilities | Where-Object { $_ -notin $capabilities })
        if ($missingCapabilities.Count -gt 0) {
            throw "The Function backend is missing required capabilities: $($missingCapabilities -join ', ')."
        }
        $minimumVersion = $null
        if (-not [version]::TryParse([string]$response.minimumModuleVersion,[ref]$minimumVersion)) {
            throw 'The Function backend returned an invalid minimumModuleVersion.'
        }
        $loadedModule = Get-Module WindowsDeviceLink | Select-Object -First 1
        if (-not $loadedModule -or $loadedModule.Version -lt $minimumVersion) {
            throw "The Function backend requires WindowsDeviceLink $minimumVersion or newer."
        }
        $tenants = @($response.tenants)
        if ($tenants.Count -eq 0 -or [int]$response.tenantCount -ne $tenants.Count) { throw 'The Function tenant catalog is empty or inconsistent.' }
        $seenIds = @{}
        $seenNames = @{}
        foreach ($tenant in $tenants) {
            $id = [guid]::Empty
            if (-not [guid]::TryParse([string]$tenant.tenantId,[ref]$id) -or [string]::IsNullOrWhiteSpace([string]$tenant.name)) {
                throw 'The Function tenant catalog contains an invalid tenant entry.'
            }
            $key = $id.ToString().ToLowerInvariant()
            if ($seenIds.ContainsKey($key)) { throw 'The Function tenant catalog contains a duplicate tenant ID.' }
            $seenIds[$key] = $true
            $nameKey = ([string]$tenant.name).Trim().ToLowerInvariant()
            if ($seenNames.ContainsKey($nameKey)) { throw 'The Function tenant catalog contains duplicate friendly names.' }
            $seenNames[$nameKey] = $true
        }
        $response
    }
    catch {
        $detail = Protect-WindowsDeviceLinkSensitiveText -Text ([string]$_.Exception.Message) -SensitiveValue @($BackendApiKey)
        throw ('WindowsDeviceLink Function tenant catalog failed. ' + $detail)
    }
    finally { $headers.Remove('X-WindowsDeviceLink-Key') | Out-Null }
}
