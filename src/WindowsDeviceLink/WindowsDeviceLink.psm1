$privatePath = Join-Path $PSScriptRoot 'Private'
$publicPath = Join-Path $PSScriptRoot 'Public'
$script:BundledWindowsManagementServicePath = Join-Path $PSScriptRoot 'Runtime\Windows.Management.Service.dll'

$nativeSource = Join-Path $privatePath 'DeviceLinkNative.cs'
if (-not ('WinPEDeviceLink.Native.DeviceLinkClient' -as [type])) {
    Add-Type -Path $nativeSource -ErrorAction Stop
}

Get-ChildItem -Path $privatePath -Filter '*.ps1' -File |
    ForEach-Object { . $_.FullName }

Get-ChildItem -Path $publicPath -Filter '*.ps1' -File |
    ForEach-Object { . $_.FullName }

Export-ModuleMember -Function @(
    'Connect-WindowsDeviceLink'
    'Export-WindowsDeviceLinkCsv'
    'Get-WindowsDeviceLink'
    'Register-WindowsDeviceLink'
    'Remove-WindowsDeviceLinkAssociation'
    'Test-WindowsDeviceLinkSupport'
)
