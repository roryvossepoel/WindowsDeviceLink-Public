<#
.SYNOPSIS
Extracts read-only string context for DeviceLink result/status enum contract research.

.DESCRIPTION
Reads Windows.Management.Service.dll and finds UTF-16 occurrences of
ConfigureDeviceLinkResult and DeviceLinkConfigurationStatus. Around each occurrence it
extracts nearby printable UTF-16 strings so enum member names, status names, and related
WinRT type signatures can be inspected without invoking DeviceLink methods.

This tool does not activate DeviceLink classes and does not modify firmware, registry,
TPM, network, cloud, or association state.
#>
[CmdletBinding()]
param(
    [string]$DllPath = (Join-Path $env:SystemRoot 'System32\Windows.Management.Service.dll'),
    [ValidateRange(512,16384)][int]$ContextBytes = 4096
)

$ErrorActionPreference='Stop'
$resolved=(Resolve-Path -LiteralPath $DllPath -ErrorAction Stop).Path
$bytes=[IO.File]::ReadAllBytes($resolved)
$needles=@('ConfigureDeviceLinkResult','DeviceLinkConfigurationStatus')

function Find-Sequence {
    param([byte[]]$Buffer,[byte[]]$Needle)
    $positions=@()
    if(-not $Needle -or $Needle.Length -eq 0 -or $Buffer.Length -lt $Needle.Length){ return @() }
    $limit=$Buffer.Length-$Needle.Length
    for($i=0;$i -le $limit;$i++){
        if($Buffer[$i] -ne $Needle[0]){ continue }
        $ok=$true
        for($j=1;$j -lt $Needle.Length;$j++){
            if($Buffer[$i+$j] -ne $Needle[$j]){ $ok=$false; break }
        }
        if($ok){ $positions += $i }
    }
    @($positions)
}

function Get-UnicodeStrings {
    param([byte[]]$Buffer,[int]$Start,[int]$Length)
    $startSafe=[Math]::Max(0,$Start)
    $end=[Math]::Min($Buffer.Length,$startSafe+$Length)
    $items=@()
    $builder=New-Object Text.StringBuilder
    $stringStart=$null
    for($i=$startSafe;$i -lt ($end-1);$i+=2){
        $code=$Buffer[$i] -bor ($Buffer[$i+1] -shl 8)
        if($code -ge 32 -and $code -le 126){
            if($null -eq $stringStart){ $stringStart=$i }
            [void]$builder.Append([char]$code)
        } else {
            if($builder.Length -ge 3){
                $items += [pscustomobject]@{Offset=[int64]$stringStart;Text=$builder.ToString()}
            }
            [void]$builder.Clear(); $stringStart=$null
        }
    }
    if($builder.Length -ge 3){ $items += [pscustomobject]@{Offset=[int64]$stringStart;Text=$builder.ToString()} }
    @($items | Sort-Object Offset -Unique)
}

$hits=@(
    foreach($needle in $needles){
        $needleBytes=[Text.Encoding]::Unicode.GetBytes($needle)
        foreach($offset in @(Find-Sequence -Buffer $bytes -Needle $needleBytes)){
            $start=[Math]::Max(0,$offset-$ContextBytes)
            $length=[Math]::Min($bytes.Length-$start,($ContextBytes*2)+$needleBytes.Length)
            $strings=@(Get-UnicodeStrings -Buffer $bytes -Start $start -Length $length)
            [pscustomobject]@{
                Needle=$needle
                Offset=[int64]$offset
                ContextStart=[int64]$start
                ContextEnd=[int64]($start+$length)
                Strings=$strings
            }
        }
    }
)

[pscustomobject]@{
    PSTypeName='Windows.DeviceLink.Research.EnumContractInventory'
    DllPath=$resolved
    DllVersion=(Get-Item -LiteralPath $resolved).VersionInfo.FileVersion
    MatchCount=@($hits).Count
    Matches=@($hits)
    ReadOnly=$true
}
