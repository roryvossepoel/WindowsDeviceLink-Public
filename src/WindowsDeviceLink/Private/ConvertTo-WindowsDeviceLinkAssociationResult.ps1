function ConvertTo-WindowsDeviceLinkAssociationResult {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowNull()]
        [psobject]$Record,

        [AllowNull()]
        [string]$TenantId,

        [ValidateSet('Association','Registration')]
        [string]$ResultType = 'Association',

        [AllowNull()]
        [string]$ExpectedAssociationId,

        [AllowNull()]
        [string]$ExpectedSerialNumber
    )

    if ($null -eq $Record) {
        throw 'Microsoft Graph returned an empty Device Association response; result is indeterminate.'
    }

    $id = [string]$Record.id
    if ([string]::IsNullOrWhiteSpace($id) -or $id -eq [guid]::Empty.ToString()) {
        throw 'Microsoft Graph returned a malformed Device Association record: association ID is missing or empty.'
    }
    if (-not [string]::IsNullOrWhiteSpace($ExpectedAssociationId) -and $id -ne [string]$ExpectedAssociationId) {
        throw "Microsoft Graph returned a mismatched Device Association record. Requested ID '$ExpectedAssociationId', received '$id'."
    }

    $associationState = [string]$Record.associationState
    if ([string]::IsNullOrWhiteSpace($associationState)) {
        throw "Microsoft Graph returned a malformed Device Association record '$id': associationState is missing or empty."
    }

    $serialNumber = [string]$Record.serialNumber
    if (-not [string]::IsNullOrWhiteSpace($ExpectedSerialNumber) -and $serialNumber -ne [string]$ExpectedSerialNumber) {
        throw "Microsoft Graph returned a mismatched Device Association record. Expected serial number '$ExpectedSerialNumber', received '$serialNumber'."
    }

    $managedDeviceId = [string]$Record.managedDeviceId
    if ([string]::IsNullOrWhiteSpace($managedDeviceId) -or $managedDeviceId -eq [guid]::Empty.ToString()) { $managedDeviceId = $null }

    $devicePreparationPolicyId = [string]$Record.devicePreparationPolicyId
    if ([string]::IsNullOrWhiteSpace($devicePreparationPolicyId) -or $devicePreparationPolicyId -eq [guid]::Empty.ToString()) { $devicePreparationPolicyId = $null }

    $typeName = if ($ResultType -eq 'Registration') { 'Windows.DeviceLink.Registration' } else { 'Windows.DeviceLink.Association' }

    [pscustomobject]@{
        PSTypeName = $typeName
        Id = $id
        TenantId = $TenantId
        ManagedDeviceId = $managedDeviceId
        ManagedDeviceName = $Record.managedDeviceName
        SerialNumber = $serialNumber
        SmbiosUuid = $Record.smbiosUuid
        Manufacturer = $Record.manufacturerName
        Model = $Record.modelName
        AssociationState = $associationState
        PreassociationDateTime = $Record.preassociationDateTime
        AssociationDateTime = $Record.associationDateTime
        EnrolledDateTime = $Record.enrolledDateTime
        LastContactedDateTime = $Record.lastContactedDateTime
        PreassociatedByUserPrincipalName = $Record.preassociatedByUserPrincipalName
        AssignedToUserPrincipalName = $Record.assignedToUserPrincipalName
        DevicePreparationPolicyId = $devicePreparationPolicyId
        DevicePreparationPolicyAssignedDateTime = $Record.devicePreparationPolicyAssignedDateTime
    }
}
