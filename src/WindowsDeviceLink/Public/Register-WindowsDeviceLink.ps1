function Register-WindowsDeviceLink {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [PSTypeName('Windows.DeviceLink.Information')]
        [psobject]$InputObject
    )

    process {
        if (-not (Get-Command Invoke-MgGraphRequest -ErrorAction SilentlyContinue)) {
            throw 'Microsoft.Graph.Authentication is required. Run Connect-WindowsDeviceLink first.'
        }

        $context = Get-MgContext
        if (-not $context) {
            throw 'No Microsoft Graph session exists. Run Connect-WindowsDeviceLink first.'
        }

        $uri = 'https://graph.microsoft.com/beta/deviceManagement/tenantAssociatedDevices/importTenantAssociatedDevice'
        $body = @{ deviceLink = $InputObject.DeviceLink } | ConvertTo-Json -Compress

        if ($PSCmdlet.ShouldProcess($InputObject.SerialNumber, "Create the Intune DeviceLink pre-association in tenant $($context.TenantId)")) {
            try {
                $response = Invoke-MgGraphRequest -Method POST -Uri $uri -Body $body -ContentType 'application/json' -OutputType PSObject -ErrorAction Stop
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
                TenantId                = $context.TenantId
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
    }
}
