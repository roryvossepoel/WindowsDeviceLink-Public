function Get-WindowsDeviceLinkFirmwareVariableBytes {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('DeviceLinkId','DeviceLinkJwtCompressed','DeviceLinkJwtLastWrite','DeviceLinkCreationTimeUtc')]
        [string]$Name
    )

    Initialize-WindowsDeviceLinkFirmware

    $namespace = '{B3DE75DA-819C-4FD5-9F01-C3D49E8CBBD7}'
    $buffer = New-Object byte[] 65536
    $size = [WindowsDeviceLink.FirmwareNative]::GetFirmwareEnvironmentVariable(
        $Name,
        $namespace,
        $buffer,
        $buffer.Length
    )

    if ($size -eq 0) {
        $lastError = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
        return [pscustomobject]@{
            Present   = $false
            Size      = 0
            Bytes     = $null
            LastError = $lastError
        }
    }

    $bytes = New-Object byte[] ([int]$size)
    [Array]::Copy($buffer, 0, $bytes, 0, [int]$size)

    [pscustomobject]@{
        Present   = $true
        Size      = [int]$size
        Bytes     = $bytes
        LastError = $null
    }
}
