<#
.SYNOPSIS
Searches local Windows metadata files for DeviceLinkManager contract evidence.

.DESCRIPTION
Performs a read-only scan of likely Windows Runtime metadata locations for UTF-16/ASCII
occurrences of DeviceLinkManager-related type names, result/progress type names, and the
known DeviceLinkManager interface IID. It does not activate DeviceLink methods or modify
any local/cloud state.
#>
[CmdletBinding()]
param(
    [string[]]$Roots = @(
        (Join-Path $env:SystemRoot 'System32\WinMetadata'),
        (Join-Path $env:SystemRoot 'System32')
    ),
    [ValidateRange(1,20)][int]$MaxResultsPerNeedle = 20
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

$extensions = @('.winmd','.dll','.exe')

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

$files = @(
    foreach($root in $Roots){
        if(-not (Test-Path -LiteralPath $root)){ continue }
        Get-ChildItem -LiteralPath $root -File -Recurse -ErrorAction SilentlyContinue |
            Where-Object { $extensions -contains $_.Extension.ToLowerInvariant() }
    }
) | Sort-Object FullName -Unique

$results = @(
    foreach($file in $files){
        $bytes=$null
        try { $bytes=[IO.File]::ReadAllBytes($file.FullName) } catch { continue }

        foreach($needle in $needles){
            $ascii=[Text.Encoding]::ASCII.GetBytes($needle)
            $unicode=[Text.Encoding]::Unicode.GetBytes($needle)
            $guidBytes=$null
            if($needle -match '^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$'){
                $guidBytes=([guid]$needle).ToByteArray()
            }

            $kinds=@()
            if(Test-ByteSequence -Buffer $bytes -Needle $unicode){ $kinds += 'UnicodeText' }
            if(Test-ByteSequence -Buffer $bytes -Needle $ascii){ $kinds += 'AsciiText' }
            if($guidBytes -and (Test-ByteSequence -Buffer $bytes -Needle $guidBytes)){ $kinds += 'GuidBytes' }

            if($kinds.Count -gt 0){
                [pscustomobject]@{
                    File=$file.FullName
                    Extension=$file.Extension
                    Needle=$needle
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
        $matchesForNeedle=@($results | Where-Object Needle -eq $needle | Select-Object -First $MaxResultsPerNeedle)
        [pscustomobject]@{
            Needle=$needle
            MatchCount=@($matchesForNeedle).Count
            Matches=$matchesForNeedle
        }
    }
)

[pscustomobject]@{
    PSTypeName='Windows.DeviceLink.Research.WinRtMetadataInventory'
    Roots=@($Roots)
    FileCount=@($files).Count
    NeedleCount=@($needles).Count
    Results=$grouped
    ReadOnly=$true
}
