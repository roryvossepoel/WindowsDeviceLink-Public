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

    $normalizeDateTime = {
        param([AllowNull()]$Value)
        if ($null -eq $Value) { return $null }

        $text = [string]$Value
        if ([string]::IsNullOrWhiteSpace($text)) { return $null }

        $parsed = [datetimeoffset]::MinValue
        $styles = [System.Globalization.DateTimeStyles]::AllowWhiteSpaces -bor
                  [System.Globalization.DateTimeStyles]::AssumeUniversal -bor
                  [System.Globalization.DateTimeStyles]::AdjustToUniversal
        if ([datetimeoffset]::TryParse($text, [System.Globalization.CultureInfo]::InvariantCulture, $styles, [ref]$parsed) -and $parsed.Year -eq 1) {
            return $null
        }

        $Value
    }

    $preassociationDateTime = & $normalizeDateTime $Record.preassociationDateTime
    $associationDateTime = & $normalizeDateTime $Record.associationDateTime
    $enrolledDateTime = & $normalizeDateTime $Record.enrolledDateTime
    $lastContactedDateTime = & $normalizeDateTime $Record.lastContactedDateTime
    $devicePreparationPolicyAssignedDateTime = & $normalizeDateTime $Record.devicePreparationPolicyAssignedDateTime

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
        PreassociationDateTime = $preassociationDateTime
        AssociationDateTime = $associationDateTime
        EnrolledDateTime = $enrolledDateTime
        LastContactedDateTime = $lastContactedDateTime
        PreassociatedByUserPrincipalName = $Record.preassociatedByUserPrincipalName
        AssignedToUserPrincipalName = $Record.assignedToUserPrincipalName
        DevicePreparationPolicyId = $devicePreparationPolicyId
        DevicePreparationPolicyAssignedDateTime = $devicePreparationPolicyAssignedDateTime
    }
}
