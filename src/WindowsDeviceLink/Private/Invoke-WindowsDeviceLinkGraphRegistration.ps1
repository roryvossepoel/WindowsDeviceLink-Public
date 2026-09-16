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
        [string]$TenantId,

        [scriptblock]$RequestScript
    )

    $uri = 'https://graph.microsoft.com/beta/deviceManagement/tenantAssociatedDevices/importTenantAssociatedDevice'
    $body = @{ deviceLink = $InputObject.DeviceLink } | ConvertTo-Json -Compress

    try {
        if ($RequestScript) {
            $response = & $RequestScript $uri $body $AccessToken
        }
        else {
            $response = Invoke-RestMethod `
                -Method POST `
                -Uri $uri `
                -Headers @{ Authorization = "Bearer $AccessToken" } `
                -ContentType 'application/json' `
                -Body $body `
                -ErrorAction Stop
        }
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

    $result = ConvertTo-WindowsDeviceLinkAssociationResult `
        -Record $response `
        -TenantId $TenantId `
        -ResultType Registration `
        -ExpectedSerialNumber ([string]$InputObject.SerialNumber)

    $successMessage = "DeviceLink registration succeeded. Serial number: {0}; Association state: {1}; Association ID: {2}" -f $result.SerialNumber, $result.AssociationState, $result.Id
    Write-Information -InformationAction Continue -MessageData $successMessage
    $result
}
