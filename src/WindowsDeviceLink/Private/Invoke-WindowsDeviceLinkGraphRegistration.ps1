function Invoke-WindowsDeviceLinkGraphRegistration {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [PSTypeName('Windows.DeviceLink.Information')]
        [psobject]$InputObject,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$AccessToken,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$TenantId
    )

    $uri = 'https://graph.microsoft.com/beta/deviceManagement/tenantAssociatedDevices/importTenantAssociatedDevice'
    $body = @{ deviceLink = $InputObject.DeviceLink } | ConvertTo-Json -Compress

    try {
        $response = Invoke-RestMethod `
            -Method POST `
            -Uri $uri `
            -Headers @{ Authorization = "Bearer $AccessToken" } `
            -ContentType 'application/json' `
            -Body $body `
            -ErrorAction Stop
    }
    catch {
        $statusCode = $null
        try {
            if ($_.Exception.Response -and $_.Exception.Response.StatusCode) {
                $statusCode = [int]$_.Exception.Response.StatusCode
            }
        }
        catch { $statusCode = $null }

        if ($statusCode -eq 409 -or $_.Exception.Message -match '409\s+Conflict') {
            throw "A DeviceLink pre-association already exists or conflicts with this device (HTTP 409). Serial number: $($InputObject.SerialNumber). Remove the existing association in Intune before registering the device again."
        }
        throw
    }

    $result = [pscustomobject]@{
        PSTypeName              = 'Windows.DeviceLink.Registration'
        Id                      = $response.id
        TenantId                = $TenantId
        ManagedDeviceId         = $response.managedDeviceId
        ManagedDeviceName       = $response.managedDeviceName
        SerialNumber            = $response.serialNumber
        SmbiosUuid              = $response.smbiosUuid
        Manufacturer            = $response.manufacturerName
        Model                   = $response.modelName
        AssociationState        = $response.associationState
        PreassociationDateTime  = $response.preassociationDateTime
        AssociationDateTime     = $response.associationDateTime
        EnrolledDateTime        = $response.enrolledDateTime
        LastContactedDateTime   = $response.lastContactedDateTime
        PreassociatedByUserPrincipalName = $response.preassociatedByUserPrincipalName
        AssignedToUserPrincipalName = $response.assignedToUserPrincipalName
        DevicePreparationPolicyId = $response.devicePreparationPolicyId
        DevicePreparationPolicyAssignedDateTime = $response.devicePreparationPolicyAssignedDateTime
    }

    $successMessage = "DeviceLink registration succeeded. Serial number: {0}; Association state: {1}; Association ID: {2}" -f $result.SerialNumber, $result.AssociationState, $result.Id
    Write-Information -InformationAction Continue -MessageData $successMessage
    $result
}
