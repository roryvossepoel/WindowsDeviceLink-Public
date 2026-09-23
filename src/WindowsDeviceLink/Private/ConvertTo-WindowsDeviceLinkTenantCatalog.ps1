function ConvertTo-WindowsDeviceLinkTenantCatalog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateNotNull()][object]$InputObject,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$Source
    )

    if ($InputObject -is [System.Array]) {
        throw "The tenant catalog from '$Source' must be a JSON object that maps friendly names to tenant GUIDs."
    }

    $entries = @()
    $seenNames = @{}
    $seenIds = @{}

    if ($InputObject -is [System.Collections.IDictionary]) {
        $pairs = foreach ($key in $InputObject.Keys) {
            [pscustomobject]@{ Name=[string]$key; Value=$InputObject[$key] }
        }
    }
    else {
        $pairs = foreach ($property in @($InputObject.PSObject.Properties)) {
            [pscustomobject]@{ Name=[string]$property.Name; Value=$property.Value }
        }
    }

    foreach ($pair in @($pairs)) {
        $name = [string]$pair.Name
        $value = [string]$pair.Value
        $parsed = [guid]::Empty
        if ([string]::IsNullOrWhiteSpace($name) -or
            [string]::IsNullOrWhiteSpace($value) -or
            -not [guid]::TryParse($value.Trim(),[ref]$parsed)) {
            throw "Invalid tenant entry '$name' in '$Source'. Each value must be a tenant GUID."
        }

        $normalizedName = $name.Trim()
        $normalizedId = $parsed.ToString().ToLowerInvariant()
        $nameKey = $normalizedName.ToLowerInvariant()
        if ($seenNames.ContainsKey($nameKey)) {
            throw "Tenant name '$normalizedName' occurs more than once in '$Source'."
        }
        if ($seenIds.ContainsKey($normalizedId)) {
            throw "Tenant ID '$normalizedId' occurs more than once in '$Source'."
        }
        $seenNames[$nameKey] = $true
        $seenIds[$normalizedId] = $true

        $entry = [pscustomobject]@{
            Name=$normalizedName
            TenantId=$normalizedId
            Source=$Source
            OperationMode='Direct'
            Enabled=$true
            Capabilities=@('Lookup','Register')
        }
        $entry.PSObject.TypeNames.Insert(0,'Windows.DeviceLink.TenantCatalogEntry')
        $entries += $entry
    }

    if ($entries.Count -eq 0) { throw "The tenant catalog from '$Source' is empty." }
    @($entries | Sort-Object Name)
}
