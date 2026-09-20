[CmdletBinding()]
param(
    [ValidateNotNullOrEmpty()]
    [string]$ModulePath
)

$ErrorActionPreference='Stop'

if(-not $ModulePath){
    $ModulePath=Join-Path $PSScriptRoot '..\src\WindowsDeviceLink\WindowsDeviceLink.psd1'
}
$ModulePath=(Resolve-Path -LiteralPath $ModulePath).Path

Import-Module $ModulePath -Force -ErrorAction Stop

$type='WinPEDeviceLink.Native.DeviceLinkManagerClient' -as [type]
if(-not $type){ throw 'FAIL: DeviceLinkManagerClient type was not loaded by the module.' }

$required=@('DiscoverRegistered','ConfigureRegistered')
$publicStatic=@($type.GetMethods([Reflection.BindingFlags]'Public,Static') | Select-Object -ExpandProperty Name -Unique)
foreach($name in $required){
    if($name -notin $publicStatic){ throw "FAIL: DeviceLinkManagerClient is missing public static method '$name'." }
}

$configureOverloads=@($type.GetMethods([Reflection.BindingFlags]'Public,Static') | Where-Object Name -eq 'ConfigureRegistered')
$callbackOverload=$configureOverloads | Where-Object {
    $parameters=$_.GetParameters()
    $parameters.Count -eq 3 -and
    $parameters[0].ParameterType -eq [string] -and
    $parameters[1].ParameterType -eq [int] -and
    $parameters[2].ParameterType -eq [Action[string]]
} | Select-Object -First 1
if(-not $callbackOverload){ throw 'FAIL: ConfigureRegistered is missing the progress-callback overload (string, int, Action[string]).' }

$resultType='WinPEDeviceLink.Native.DeviceLinkConfigureResult' -as [type]
if(-not $resultType){ throw 'FAIL: DeviceLinkConfigureResult type was not loaded by the module.' }
foreach($propertyName in @('DiscoveryDurationSeconds','ConfigureDurationSeconds','NativeDurationSeconds')){
    if(-not $resultType.GetProperty($propertyName)){
        throw "FAIL: DeviceLinkConfigureResult is missing timing property '$propertyName'."
    }
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
    'GetIntResult(configureOperation, 10)',
    'HeartbeatSeconds = 15',
    'Action<string> progressCallback',
    'SafeProgress(progressCallback',
    'Progress reporting is observational only and must never affect DeviceLink state changes.'
)
foreach($needle in $requiredContract){
    if($source.IndexOf($needle,[StringComparison]::Ordinal) -lt 0){
        throw "FAIL: DeviceLinkManager native wrapper is missing expected contract text '$needle'."
    }
}

# Only enforce destructive-operation names; normal timeout polling loops are expected in native code.
foreach($needle in @('Reset-WindowsDeviceLinkFirmwareState','Remove-WindowsDeviceLinkAssociation')){
    if($source.IndexOf($needle,[StringComparison]::OrdinalIgnoreCase) -ge 0){
        throw "FAIL: DeviceLinkManager native wrapper unexpectedly references destructive operation '$needle'."
    }
}

Write-Host 'PASS: DeviceLinkManager native wrapper loads, exposes the validated Discover/Configure contract, and includes non-invasive progress/timing observability without executing it.'
