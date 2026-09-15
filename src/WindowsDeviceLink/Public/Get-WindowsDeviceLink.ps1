function Get-WindowsDeviceLink {
    [CmdletBinding()]
    param(
        [ValidateNotNullOrEmpty()]
        [string]$WindowsManagementServicePath,

        [ValidateRange(5, 600)]
        [int]$TimeoutSeconds = 120,

        [ValidateNotNullOrEmpty()]
        [string]$OutputDirectory
    )

    if ($PSBoundParameters.ContainsKey('WindowsManagementServicePath')) {
        $support = Test-WindowsDeviceLinkSupport -WindowsManagementServicePath $WindowsManagementServicePath
    }
    else {
        $support = Test-WindowsDeviceLinkSupport
    }

    if (-not $support.Supported) {
        throw "DeviceLink isn't supported: $($support.Reason)"
    }

    if ($support.ActivationMode -eq 'RegisteredWinRT') {
        $payload = [WinPEDeviceLink.Native.DeviceLinkClient]::GetDeviceLinkRegistered($TimeoutSeconds)
    }
    else {
        $payload = [WinPEDeviceLink.Native.DeviceLinkClient]::GetDeviceLink($support.DllPath, $TimeoutSeconds)
    }

    $decoded = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($payload)) | ConvertFrom-Json

    $deviceLink = [pscustomobject]@{
        PSTypeName             = 'Windows.DeviceLink.Information'
        Environment            = $support.Environment
        SerialNumber           = $decoded.DeviceInfo.SerialNumber
        Manufacturer           = $decoded.DeviceInfo.Manufacturer
        Model                  = $decoded.DeviceInfo.ModelName
        SmbiosUuid             = $decoded.DeviceInfo.SmbiosUuid
        LinkId                 = $decoded.DeviceInfo.LinkId
        PayloadCreationTimeUtc = $decoded.DeviceLinkCreationTimeUtc
        DeviceLink             = $payload
        DllSource              = $support.DllSource
        ActivationMode         = $support.ActivationMode
        DllPath                = $support.DllPath
        DllVersion             = $support.DllVersion
    }

    if ($PSBoundParameters.ContainsKey('OutputDirectory')) {
        $exportedFile = $deviceLink | Export-WindowsDeviceLinkCsv -DestinationPath $OutputDirectory
        Write-Information -InformationAction Continue -MessageData "DeviceLink CSV exported successfully: $($exportedFile.FullName)"
        return $exportedFile
    }

    $deviceLink
}
