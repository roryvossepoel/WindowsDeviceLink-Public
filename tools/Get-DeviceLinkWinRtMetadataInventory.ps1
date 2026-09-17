<#
.SYNOPSIS
Searches a targeted set of local Windows metadata/binaries for DeviceLinkManager contract evidence.

.DESCRIPTION
Performs a read-only targeted scan for DeviceLinkManager-related type names, result/progress
type names, and the known DeviceLinkManager interface IID. The default scan intentionally avoids
recursing through all of System32: it inspects Windows.Management.Service.dll plus the small
System32\WinMetadata tree and a few explicitly named management/enrollment binaries when present.

Each file is read once and searched for all needles in-memory. No DeviceLink methods are activated
or invoked and no local/cloud state is modified.
#>
[CmdletBinding()]
param(
    [string[]]$AdditionalFiles = @(),
    [ValidateRange(1,50)][int]$MaxResultsPerNeedle = 20
)

$ErrorActionPreference='Stop'

$needles = @(
    'ModernDeployment.Autopilot.Core.DeviceLinkManager',
    'DeviceLinkManager',
    'ConfigureDeviceLink',
    'ConfigureDeviceLinkResult',
    'DeviceLinkConfigurationProgress',
    'DeviceLinkProgress',
    'AcquireApplyAckDeviceLink',
    '1F79101B-A792-5008-A82A-A4B232229026'
)

function Test-ByteSequence {
    param([byte[]]$Buffer,[byte[]]$Needle)
    if(-not $Needle -or $Needle.Length -eq 0 -or $Buffer.Length -lt $Needle.Length){ return $false }
    $limit=$Buffer.Length-$Needle.Length
    for($i=0;$i -le $limit;$i++){
        if($Buffer[$i] -ne $Needle[0]){ continue }
        $ok=$true
        for($j=1;$j -lt $Needle.Length;$j++){
            if($Buffer[$i+$j] -ne $Needle[$j]){ $ok=$false; break }
        }
        if($ok){ return $true }
    }
    return $false
}

$candidatePaths = @(
    (Join-Path $env:SystemRoot 'System32\Windows.Management.Service.dll'),
    (Join-Path $env:SystemRoot 'System32\mdmregistration.dll'),
    (Join-Path $env:SystemRoot 'System32\omadmclient.exe'),
    (Join-Path $env:SystemRoot 'System32\deviceenroller.exe')
) + @($AdditionalFiles)

$winMetadataRoot = Join-Path $env:SystemRoot 'System32\WinMetadata'
$files = @(
    foreach($path in $candidatePaths){
        if(Test-Path -LiteralPath $path -PathType Leaf){ Get-Item -LiteralPath $path }
    }
    if(Test-Path -LiteralPath $winMetadataRoot){
        Get-ChildItem -LiteralPath $winMetadataRoot -File -Recurse -Filter '*.winmd' -ErrorAction SilentlyContinue
    }
) | Sort-Object FullName -Unique

$needlePatterns = @(
    foreach($needle in $needles){
        $guidBytes=$null
        if($needle -match '^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$'){
            $guidBytes=([guid]$needle).ToByteArray()
        }
        [pscustomobject]@{
            Needle=$needle
            Ascii=[Text.Encoding]::ASCII.GetBytes($needle)
            Unicode=[Text.Encoding]::Unicode.GetBytes($needle)
            GuidBytes=$guidBytes
        }
    }
)

$results = @(
    foreach($file in $files){
        $bytes=$null
        try { $bytes=[IO.File]::ReadAllBytes($file.FullName) } catch { continue }

        foreach($pattern in $needlePatterns){
            $kinds=@(
                if(Test-ByteSequence -Buffer $bytes -Needle $pattern.Unicode){ 'UnicodeText' }
                if(Test-ByteSequence -Buffer $bytes -Needle $pattern.Ascii){ 'AsciiText' }
                if($pattern.GuidBytes -and (Test-ByteSequence -Buffer $bytes -Needle $pattern.GuidBytes)){ 'GuidBytes' }
            )

            if($kinds.Count -gt 0){
                [pscustomobject]@{
                    File=$file.FullName
                    Extension=$file.Extension
                    Needle=$pattern.Needle
                    MatchKinds=@($kinds)
                    Length=$file.Length
                    Version=if($file.Extension -in @('.dll','.exe')){$file.VersionInfo.FileVersion}else{$null}
                }
            }
        }
    }
)

$grouped=@(
    foreach($needle in $needles){
        $items=@($results | Where-Object Needle -eq $needle | Select-Object -First $MaxResultsPerNeedle)
        [pscustomobject]@{
            Needle=$needle
            MatchCount=@($items).Count
            Matches=$items
        }
    }
)

[pscustomobject]@{
    PSTypeName='Windows.DeviceLink.Research.WinRtMetadataInventory'
    Mode='Targeted'
    FileCount=@($files).Count
    Files=@($files | ForEach-Object FullName)
    NeedleCount=@($needles).Count
    Results=$grouped
    ReadOnly=$true
}
