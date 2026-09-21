function Get-WindowsDeviceLinkStatus {
    <#
    .SYNOPSIS
    Returns a combined local DeviceLink diagnostic status with optional Intune Device Association state.

    .DESCRIPTION
    Combines runtime support, local DeviceLink identity metadata, and safe local firmware-state metadata in one object.
    By default the cmdlet performs no Microsoft Graph authentication or tenant lookup.

    Use -Online with an explicit authentication method to add the tenant-side Intune Device Association state.
    An online lookup that successfully finds no association is reported as AssociationPresent = False and AssociationState = NotAssociated;
    this is a normal status result, not an error. A failed or indeterminate lookup is reported as AssociationPresent = $null,
    AssociationState = Unknown, with AssociationError populated; it must not be interpreted as confirmed absence.

    PayloadCreationTimeUtc is the timestamp contained in the newly generated DeviceLink payload. Live validation showed
    that this value changes between payload generations while LinkId remains stable; it must not be interpreted as the
    persistent local identity creation time.

    FirmwareCreationTimeUtc is decoded from the local DeviceLinkCreationTimeUtc UEFI variable. Live validation showed
    this firmware timestamp remained stable across repeated DeviceLink payload generations. The exact Windows lifecycle
    event represented by this persistent timestamp is not claimed beyond the firmware variable's own name.
    #>
    [CmdletBinding()]
    param(
        [ValidateNotNullOrEmpty()][string]$WindowsManagementServicePath,
        [ValidateRange(5, 600)][int]$TimeoutSeconds = 120,
        [switch]$Online,
        [ValidateSet('DeviceCode','Interactive','ClientSecret','AccessToken','Certificate','CertificateThumbprint','CertificateSubjectName','EnvironmentVariable','ManagedIdentity')][string]$Method,
        [ValidateNotNullOrEmpty()][string]$TenantId,
        [ValidateNotNullOrEmpty()][string]$ClientId,
        [securestring]$AccessToken,
        [System.Security.Cryptography.X509Certificates.X509Certificate2]$Certificate,
        [ValidateNotNullOrEmpty()][string]$CertificateThumbprint,
        [ValidateNotNullOrEmpty()][string]$CertificateSubjectName,
        [bool]$SendCertificateChain = $false,
        [securestring]$ClientSecret,
        [ValidateNotNullOrEmpty()][string]$Environment = 'Global',
        [ValidateRange(1, 600)][double]$ClientTimeout = 100
    )

    $onlineParameters = @('Method','TenantId','ClientId','AccessToken','Certificate','CertificateThumbprint','CertificateSubjectName','SendCertificateChain','ClientSecret','Environment','ClientTimeout')
    if (-not $Online) {
        $usedOnlineOnly = $onlineParameters | Where-Object { $PSBoundParameters.ContainsKey($_) -and $_ -notin @('Environment','ClientTimeout','SendCertificateChain') }
        if ($usedOnlineOnly) { throw "Online parameters require -Online. Parameters supplied: $($usedOnlineOnly -join ', ')." }
    }
    elseif (-not $PSBoundParameters.ContainsKey('Method')) { throw '-Method is required with -Online.' }

    $supportParameters = @{}
    if ($PSBoundParameters.ContainsKey('WindowsManagementServicePath')) { $supportParameters.WindowsManagementServicePath = $WindowsManagementServicePath }
    $support = Test-WindowsDeviceLinkSupport @supportParameters

    $deviceLink = $null
    $identityError = $null
    if ($support.Supported) {
        try {
            $identityParameters = @{ TimeoutSeconds = $TimeoutSeconds }
            if ($PSBoundParameters.ContainsKey('WindowsManagementServicePath')) { $identityParameters.WindowsManagementServicePath = $WindowsManagementServicePath }
            $deviceLink = Get-WindowsDeviceLink @identityParameters
        }
        catch { $identityError = $_.Exception.Message }
    }

    $firmwareState = @()
    $firmwareError = $null
    try { $firmwareState = @(Get-WindowsDeviceLinkFirmwareState -ErrorAction Stop) }
    catch { $firmwareError = $_.Exception.Message }

    $firmwarePresent = @($firmwareState | Where-Object { $_.Present })
    $firmwarePresentNames = @($firmwarePresent | ForEach-Object { $_.Name })
    $firmwareExpectedCount = 4
    $firmwarePresentCount = $firmwarePresent.Count
    $firmwareStateComplete = $firmwarePresentCount -eq $firmwareExpectedCount
    $firmwareCreationState = $firmwareState | Where-Object { $_.Name -eq 'DeviceLinkCreationTimeUtc' } | Select-Object -First 1
    $firmwareCreationTimeUtc = if ($firmwareCreationState) { $firmwareCreationState.ParsedUtc } else { $null }

    $association = $null
    $associationError = $null
    $cloudChecked = $false

    $lookupSerialNumber = if ($deviceLink -and -not [string]::IsNullOrWhiteSpace([string]$deviceLink.SerialNumber)) {
        ([string]$deviceLink.SerialNumber).Trim()
    }
    else {
        $null
    }

    if ([string]::IsNullOrWhiteSpace($lookupSerialNumber)) {
        try {
            $bios = Get-CimInstance -ClassName Win32_BIOS -ErrorAction Stop
            $lookupSerialNumber = [string]$bios.SerialNumber
        }
        catch {
            if (Get-Command Get-WmiObject -ErrorAction SilentlyContinue) {
                try {
                    $lookupSerialNumber = [string](Get-WmiObject -Class Win32_BIOS -ErrorAction Stop).SerialNumber
                }
                catch {}
            }
        }

        if (-not [string]::IsNullOrWhiteSpace($lookupSerialNumber)) {
            $lookupSerialNumber = $lookupSerialNumber.Trim()
        }
    }

    if ($Online) {
        $cloudChecked = $true
        if ([string]::IsNullOrWhiteSpace($lookupSerialNumber)) {
            $associationError = 'The local serial number is unavailable, so the Device Association lookup could not be performed.'
        }
        else {
            try {
                $associationParameters = @{ SerialNumber=$lookupSerialNumber; Method=$Method; Environment=$Environment; ClientTimeout=$ClientTimeout }
                foreach ($name in @('TenantId','ClientId','AccessToken','Certificate','CertificateThumbprint','CertificateSubjectName','SendCertificateChain','ClientSecret')) {
                    if ($PSBoundParameters.ContainsKey($name)) { $associationParameters[$name] = $PSBoundParameters[$name] }
                }
                $associationResults = @(Get-WindowsDeviceLinkAssociation @associationParameters -ErrorAction Stop)
                if ($associationResults.Count -gt 1) { $associationError = "Multiple Device Association records were returned for serial number '$lookupSerialNumber'." }
                elseif ($associationResults.Count -eq 1) { $association = $associationResults[0] }
            }
            catch { $associationError = $_.Exception.Message }
        }
    }

    $cloudState = Resolve-WindowsDeviceLinkCloudState -CloudChecked $cloudChecked -Association $association -AssociationError $associationError
    $associationPresent = $cloudState.AssociationPresent
    $associationState = $cloudState.AssociationState

    [pscustomobject]@{
        PSTypeName='Windows.DeviceLink.Status'; Environment=$support.Environment; Architecture=$support.Architecture; Supported=[bool]$support.Supported
        SupportReason=$support.Reason; DllSource=$support.DllSource; ActivationMode=$support.ActivationMode; DllPath=$support.DllPath; DllVersion=$support.DllVersion
        DeviceLinkPresent=$null -ne $deviceLink; SerialNumber=$lookupSerialNumber; Manufacturer=if($deviceLink){$deviceLink.Manufacturer}else{$null}
        Model=if($deviceLink){$deviceLink.Model}else{$null}; SmbiosUuid=if($deviceLink){$deviceLink.SmbiosUuid}else{$null}; LinkId=if($deviceLink){$deviceLink.LinkId}else{$null}
        PayloadCreationTimeUtc=if($deviceLink){$deviceLink.PayloadCreationTimeUtc}else{$null}; FirmwareCreationTimeUtc=$firmwareCreationTimeUtc; IdentityError=$identityError
        FirmwareChecked=$null -eq $firmwareError; FirmwareStateComplete=if($firmwareError){$null}else{$firmwareStateComplete}; FirmwareVariablesPresent=if($firmwareError){$null}else{"$firmwarePresentCount/$firmwareExpectedCount"}
        FirmwarePresentNames=$firmwarePresentNames; FirmwareError=$firmwareError; CloudChecked=$cloudChecked; AssociationPresent=$associationPresent; AssociationState=$associationState
        AssociationId=if($association){$association.Id}else{$null}; TenantId=if($association){$association.TenantId}elseif($Online -and $TenantId){$TenantId}else{$null}
        ManagedDeviceId=if($association){$association.ManagedDeviceId}else{$null}; ManagedDeviceName=if($association){$association.ManagedDeviceName}else{$null}
        PreassociationDateTime=if($association){$association.PreassociationDateTime}else{$null}; AssociationDateTime=if($association){$association.AssociationDateTime}else{$null}
        EnrolledDateTime=if($association){$association.EnrolledDateTime}else{$null}; LastContactedDateTime=if($association){$association.LastContactedDateTime}else{$null}
        DevicePreparationPolicyId=if($association){$association.DevicePreparationPolicyId}else{$null}; AssociationError=$associationError
    }
}
