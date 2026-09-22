function Get-WindowsDeviceLinkBackendStatus {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateNotNull()][uri]$BackendUri,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$BackendApiKey,
        [ValidateNotNullOrEmpty()][string]$WindowsManagementServicePath,
        [ValidateRange(5,600)][int]$TimeoutSeconds = 120,
        [scriptblock]$RequestScript
    )

    $localParameters = @{ TimeoutSeconds = $TimeoutSeconds }
    if ($PSBoundParameters.ContainsKey('WindowsManagementServicePath')) {
        $localParameters.WindowsManagementServicePath = $WindowsManagementServicePath
    }
    $local = Get-WindowsDeviceLinkStatus @localParameters

    $values = [ordered]@{}
    foreach ($property in $local.PSObject.Properties) {
        $values[$property.Name] = $property.Value
    }

    $values.CloudChecked = $true
    $values.AssociationPresent = $null
    $values.AssociationState = 'Unknown'
    $values.AssociationId = $null
    $values.TenantId = $null
    $values.ManagedDeviceId = $null
    $values.ManagedDeviceName = $null
    $values.PreassociationDateTime = $null
    $values.AssociationDateTime = $null
    $values.EnrolledDateTime = $null
    $values.LastContactedDateTime = $null
    $values.DevicePreparationPolicyId = $null
    $values.AssociationError = $null

    if ([string]::IsNullOrWhiteSpace([string]$local.SerialNumber)) {
        $values.AssociationError = 'The local serial number is unavailable, so the Function lookup could not be performed.'
    }
    else {
        try {
            $lookupParameters = @{
                BackendUri = $BackendUri
                BackendApiKey = $BackendApiKey
                SerialNumber = [string]$local.SerialNumber
            }
            if ($PSBoundParameters.ContainsKey('RequestScript')) { $lookupParameters.RequestScript = $RequestScript }
            $lookup = Invoke-WindowsDeviceLinkBackendLookup @lookupParameters

            $failedTenantCount = if ($lookup.PSObject.Properties.Name -contains 'failedTenantCount') { [int]$lookup.failedTenantCount } else { 0 }
            $matches = @($lookup.matches)

            if ($failedTenantCount -gt 0) {
                $values.AssociationError = "Function lookup was incomplete because $failedTenantCount tenant lookup(s) failed."
            }
            elseif ($matches.Count -gt 1) {
                $values.AssociationError = "Function lookup returned multiple Device Association records for serial number '$($local.SerialNumber)'."
            }
            elseif ($matches.Count -eq 1) {
                $match = $matches[0]
                $values.AssociationPresent = $true
                $values.AssociationState = [string]$match.associationState
                $values.AssociationId = [string]$match.associationId
                $values.TenantId = [string]$match.tenantId
                $values.ManagedDeviceId = [string]$match.managedDeviceId
                $values.PreassociationDateTime = $match.preassociationDateTime
            }
            else {
                $values.AssociationPresent = $false
                $values.AssociationState = 'NotAssociated'
            }
        }
        catch {
            $values.AssociationError = $_.Exception.Message
        }
    }

    $status = [pscustomobject]$values
    $status.PSObject.TypeNames.Insert(0,'Windows.DeviceLink.Status')
    $status
}