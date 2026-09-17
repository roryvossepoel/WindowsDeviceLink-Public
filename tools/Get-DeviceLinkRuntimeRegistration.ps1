<#
.SYNOPSIS
Collects read-only registration and binary string evidence for the DeviceLink runtime.

.DESCRIPTION
Reads likely WinRT activation registration locations for
ModernDeployment.Autopilot.Core.DeviceLinkUtilities and scans the Windows system copy
of Windows.Management.Service.dll for printable ASCII/UTF-16 strings matching a small
DeviceLink research vocabulary.

No COM methods are invoked and no registry, firmware, cloud, TPM, or DeviceLink state
is modified.
#>
[CmdletBinding()]
param(
    [string]$DllPath = (Join-Path $env:SystemRoot 'System32\Windows.Management.Service.dll')
)

$ErrorActionPreference = 'Stop'
$className = 'ModernDeployment.Autopilot.Core.DeviceLinkUtilities'

$registrations = @()
$registryCandidates = @(
    "HKLM:\SOFTWARE\Microsoft\WindowsRuntime\ActivatableClassId\$className",
    "HKLM:\SOFTWARE\Classes\ActivatableClasses\ActivatableClassId\$className",
    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\WindowsRuntime\ActivatableClassId\$className"
)

foreach ($path in $registryCandidates) {
    if (-not (Test-Path -LiteralPath $path)) { continue }
    try {
        $item = Get-ItemProperty -LiteralPath $path -ErrorAction Stop
        $safeProperties = [ordered]@{}
        foreach ($property in $item.PSObject.Properties) {
            if ($property.Name -like 'PS*') { continue }
            $safeProperties[$property.Name] = $property.Value
        }
        $registrations += [pscustomobject]@{
            Path       = $path
            Properties = [pscustomobject]$safeProperties
            Error      = $null
        }
    }
    catch {
        $registrations += [pscustomobject]@{
            Path       = $path
            Properties = $null
            Error      = $_.Exception.Message
        }
    }
}

$resolvedDll = (Resolve-Path -LiteralPath $DllPath -ErrorAction Stop).Path
$bytes = [IO.File]::ReadAllBytes($resolvedDll)

function Get-PrintableStrings {
    param(
        [byte[]]$Bytes,
        [ValidateSet('Ascii','Unicode')][string]$Encoding,
        [int]$MinimumLength = 5
    )

    $results = @()
    if ($Encoding -eq 'Ascii') {
        $builder = New-Object Text.StringBuilder
        foreach ($b in $Bytes) {
            if ($b -ge 32 -and $b -le 126) {
                [void]$builder.Append([char]$b)
            }
            else {
                if ($builder.Length -ge $MinimumLength) { $results += $builder.ToString() }
                [void]$builder.Clear()
            }
        }
        if ($builder.Length -ge $MinimumLength) { $results += $builder.ToString() }
    }
    else {
        $builder = New-Object Text.StringBuilder
        for ($i=0; $i -lt ($Bytes.Length-1); $i+=2) {
            $code = $Bytes[$i] -bor ($Bytes[$i+1] -shl 8)
            if ($code -ge 32 -and $code -le 126) {
                [void]$builder.Append([char]$code)
            }
            else {
                if ($builder.Length -ge $MinimumLength) { $results += $builder.ToString() }
                [void]$builder.Clear()
            }
        }
        if ($builder.Length -ge $MinimumLength) { $results += $builder.ToString() }
    }
    @($results)
}

$patterns = @(
    'DeviceLink',
    'preassociation',
    'association',
    'discover',
    'attest',
    'ack',
    'ztd',
    'autopilot',
    'tenant',
    'enrollment'
)

$foundItems = @()
foreach ($encoding in @('Ascii','Unicode')) {
    foreach ($text in @(Get-PrintableStrings -Bytes $bytes -Encoding $encoding)) {
        $matchedPattern = $patterns | Where-Object { $text -match [regex]::Escape($_) } | Select-Object -First 1
        if (-not $matchedPattern) { continue }
        $foundItems += [pscustomobject]@{
            Encoding = $encoding
            Pattern  = $matchedPattern
            Text     = [string]$text
        }
    }
}

$foundItems = @($foundItems | Sort-Object Encoding,Text -Unique)

[pscustomobject]@{
    PSTypeName       = 'Windows.DeviceLink.Research.RuntimeRegistration'
    RuntimeClassName = $className
    DllPath          = $resolvedDll
    DllVersion       = (Get-Item -LiteralPath $resolvedDll).VersionInfo.FileVersion
    Registrations    = @($registrations)
    StringMatches    = @($foundItems)
    ReadOnly         = $true
}
