<#
.SYNOPSIS
Extracts read-only string context around DeviceLink contract markers in Windows.Management.Service.dll.

.DESCRIPTION
Searches the system Windows.Management.Service.dll for selected Unicode contract markers and
returns nearby printable Unicode/ASCII strings with offsets. This is intended to correlate
DeviceLinkManager, ConfigureDeviceLink, ConfigureDeviceLinkResult, async generic types and
progress/result metadata without invoking any WinRT method.
#>
[CmdletBinding()]
param(
    [string]$DllPath = (Join-Path $env:SystemRoot 'System32\Windows.Management.Service.dll'),
    [string[]]$Needles = @(
        'ModernDeployment.Autopilot.Core.DeviceLinkManager',
        'ConfigureDeviceLink',
        'ConfigureDeviceLinkResult',
        'AcquireApplyAckDeviceLink',
        'Windows.Foundation.IAsyncOperationWithProgress'
    ),
    [ValidateRange(512,32768)][int]$ContextBytes = 4096
)

$ErrorActionPreference='Stop'
$resolved=(Resolve-Path -LiteralPath $DllPath -ErrorAction Stop).Path
$bytes=[IO.File]::ReadAllBytes($resolved)

function Find-ByteSequence {
    param([byte[]]$Buffer,[byte[]]$Needle)
    $hits=@()
    if(-not $Needle -or $Needle.Length -eq 0 -or $Buffer.Length -lt $Needle.Length){ return $hits }
    $limit=$Buffer.Length-$Needle.Length
    for($i=0;$i -le $limit;$i++){
        if($Buffer[$i] -ne $Needle[0]){ continue }
        $ok=$true
        for($j=1;$j -lt $Needle.Length;$j++){
            if($Buffer[$i+$j] -ne $Needle[$j]){ $ok=$false; break }
        }
        if($ok){ $hits += [int64]$i }
    }
    return @($hits)
}

function Get-PrintableStrings {
    param([byte[]]$Buffer,[int]$Start,[int]$Length)
    $startSafe=[Math]::Max(0,$Start)
    $end=[Math]::Min($Buffer.Length,$startSafe+$Length)
    $lengthSafe=[Math]::Max(0,$end-$startSafe)
    if($lengthSafe -le 0){ return @() }

    $segment=New-Object byte[] $lengthSafe
    [Array]::Copy($Buffer,$startSafe,$segment,0,$lengthSafe)

    $items=@()
    foreach($kind in @('Unicode','ASCII')){
        $enc=if($kind -eq 'Unicode'){[Text.Encoding]::Unicode}else{[Text.Encoding]::ASCII}
        $text=$enc.GetString($segment)
        foreach($piece in ($text -split '[^\x20-\x7E]+')){
            if($piece.Length -lt 4){ continue }
            if($piece -match '(?i)DeviceLink|Configure|Progress|Result|Async|Manager|Attest|Discover|Apply|Ack|Acquire|Retrieve|Association'){
                $items += [pscustomobject]@{Encoding=$kind;Text=[string]$piece}
            }
        }
    }
    @($items | Sort-Object Encoding,Text -Unique)
}

$results=@(
    foreach($needle in $Needles){
        $u=[Text.Encoding]::Unicode.GetBytes($needle)
        $a=[Text.Encoding]::ASCII.GetBytes($needle)
        foreach($entry in @(
            [pscustomobject]@{Kind='Unicode';Bytes=$u},
            [pscustomobject]@{Kind='ASCII';Bytes=$a}
        )){
            foreach($offset in @(Find-ByteSequence -Buffer $bytes -Needle $entry.Bytes)){
                $start=[Math]::Max(0,[int]$offset-$ContextBytes)
                $length=[Math]::Min($bytes.Length-$start,($ContextBytes*2)+$entry.Bytes.Length)
                [pscustomobject]@{
                    Needle=$needle
                    MatchKind=$entry.Kind
                    Offset=[int64]$offset
                    ContextStrings=@(Get-PrintableStrings -Buffer $bytes -Start $start -Length $length)
                }
            }
        }
    }
)

[pscustomobject]@{
    PSTypeName='Windows.DeviceLink.Research.ContractStringContext'
    DllPath=$resolved
    DllVersion=(Get-Item -LiteralPath $resolved).VersionInfo.FileVersion
    MatchCount=@($results).Count
    Matches=@($results)
    ReadOnly=$true
}
