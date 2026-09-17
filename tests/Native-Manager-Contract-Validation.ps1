[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$ModulePath
)

$ErrorActionPreference='Stop'

Import-Module $ModulePath -Force -ErrorAction Stop

$type='WinPEDeviceLink.Native.DeviceLinkManagerClient' -as [type]
if(-not $type){ throw 'FAIL: DeviceLinkManagerClient type was not loaded by the module.' }

$required=@('DiscoverRegistered','ConfigureRegistered')
$publicStatic=@($type.GetMethods([Reflection.BindingFlags]'Public,Static') | Select-Object -ExpandProperty Name -Unique)
foreach($name in $required){
    if($name -notin $publicStatic){ throw "FAIL: DeviceLinkManagerClient is missing public static method '$name'." }
}

$sourcePath=Join-Path (Split-Path -Parent $ModulePath) 'Private\DeviceLinkManagerNative.cs'
if(-not (Test-Path -LiteralPath $sourcePath)){ throw 'FAIL: DeviceLinkManagerNative.cs is missing from the staged module.' }
$source=[IO.File]::ReadAllText($sourcePath)

$requiredContract=@(
    '1F79101B-A792-5008-A82A-A4B232229026',
    'B93C372F-472F-4BEA-B90B-9FAA9BDC178F',
    'RequestDiscoveryUrlAsync',
    'GetConfigureDeviceLinkResult',
    'ConfigureDeviceLinkAsync',
    'discoveryResult != 1 && discoveryResult != 2',
    'ConfigureDeviceLinkAsync(discoveryUrl, tenantId, IntPtr.Zero',
    'GetIntResult(configureOperation, 10)'
)
foreach($needle in $requiredContract){
    if($source.IndexOf($needle,[StringComparison]::Ordinal) -lt 0){
        throw "FAIL: DeviceLinkManager native wrapper is missing expected contract text '$needle'."
    }
}

$forbidden=@(
    'for(',
    'while(true)',
    'Reset-WindowsDeviceLinkFirmwareState',
    'Remove-WindowsDeviceLinkAssociation'
)
# Only enforce destructive-operation names; normal timeout polling loops are expected in native code.
foreach($needle in @('Reset-WindowsDeviceLinkFirmwareState','Remove-WindowsDeviceLinkAssociation')){
    if($source.IndexOf($needle,[StringComparison]::OrdinalIgnoreCase) -ge 0){
        throw "FAIL: DeviceLinkManager native wrapper unexpectedly references destructive operation '$needle'."
    }
}

Write-Host 'PASS: DeviceLinkManager native wrapper loads and exposes the validated Discover/Configure contract without executing it.'
