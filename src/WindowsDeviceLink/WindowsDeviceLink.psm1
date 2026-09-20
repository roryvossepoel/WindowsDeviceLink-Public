$privatePath = Join-Path $PSScriptRoot 'Private'
$publicPath = Join-Path $PSScriptRoot 'Public'
$script:BundledWindowsManagementServicePath = Join-Path $PSScriptRoot 'Runtime\Windows.Management.Service.dll'

$nativeSource = Join-Path $privatePath 'DeviceLinkNative.cs'
if (-not ('WinPEDeviceLink.Native.DeviceLinkClient' -as [type])) {
    Add-Type -Path $nativeSource -ErrorAction Stop
}

$managerNativeSource = Join-Path $privatePath 'DeviceLinkManagerNative.cs'
if (-not ('WinPEDeviceLink.Native.DeviceLinkManagerClient' -as [type])) {
    Add-Type -Path $managerNativeSource -ErrorAction Stop
}

Get-ChildItem -Path $privatePath -Filter '*.ps1' -File |
    ForEach-Object { . $_.FullName }

Get-ChildItem -Path $publicPath -Filter '*.ps1' -File |
    ForEach-Object { . $_.FullName }

Export-ModuleMember -Function @(
    'Complete-WindowsDeviceLinkAssociation'
    'Connect-WindowsDeviceLink'
    'Export-WindowsDeviceLinkCsv'
    'Get-WindowsDeviceLink'
    'Get-WindowsDeviceLinkAssociation'
    'Get-WindowsDeviceLinkFirmwareState'
    'Get-WindowsDeviceLinkLocalAssociation'
    'Get-WindowsDeviceLinkRepairPlan'
    'Get-WindowsDeviceLinkStatus'
    'Initialize-WindowsDeviceLink'
    'Register-WindowsDeviceLink'
    'Remove-WindowsDeviceLinkAssociation'
    'Reset-WindowsDeviceLinkFirmwareState'
    'Test-WindowsDeviceLinkAssociationJwt'
    'Test-WindowsDeviceLinkDiscovery'
    'Test-WindowsDeviceLinkHealth'
    'Test-WindowsDeviceLinkPreflight'
    'Test-WindowsDeviceLinkRuntime'
    'Test-WindowsDeviceLinkSupport'
)
