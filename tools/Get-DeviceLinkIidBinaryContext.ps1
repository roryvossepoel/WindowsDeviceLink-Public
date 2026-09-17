<#
.SYNOPSIS
Finds read-only binary context around DeviceLink interface IIDs.

.DESCRIPTION
Reads the system Windows.Management.Service.dll and searches for the byte representation
and textual representation of selected interface GUIDs. Around each hit it extracts
printable ASCII/UTF-16 strings and returns only strings matching a narrow DeviceLink
research vocabulary.

The tool does not activate COM/WinRT classes and does not invoke any DeviceLink method.
#>
[CmdletBinding()]
param(
    [string]$DllPath = (Join-Path $env:SystemRoot 'System32\Windows.Management.Service.dll'),
    [string[]]$InterfaceIds = @(
        '6410BEE7-60A9-5627-9EB2-FEDA7518A4EB',
        '8A3B7C2E-5D1F-4E9A-B6C8-2F0E1D3A4B5C'
    ),
    [ValidateRange(512,65536)][int]$ContextBytes = 8192
)

$ErrorActionPreference='Stop'
$resolvedDll=(Resolve-Path -LiteralPath $DllPath -ErrorAction Stop).Path
$bytes=[IO.File]::ReadAllBytes($resolvedDll)

if(-not ('WindowsDeviceLinkResearch.BinarySearch' -as [type])){
    Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;

namespace WindowsDeviceLinkResearch
{
    public static class BinarySearch
    {
        public static long[] FindAll(byte[] haystack, byte[] needle)
        {
            var found = new List<long>();
            if (haystack == null || needle == null || needle.Length == 0 || haystack.Length < needle.Length)
                return found.ToArray();

            int limit = haystack.Length - needle.Length;
            for (int i = 0; i <= limit; i++)
            {
                if (haystack[i] != needle[0]) continue;
                bool match = true;
                for (int j = 1; j < needle.Length; j++)
                {
                    if (haystack[i + j] != needle[j]) { match = false; break; }
                }
                if (match) found.Add(i);
            }
            return found.ToArray();
        }
    }
}
'@
}

function Get-ContextStrings {
    param([byte[]]$Buffer,[int]$Start,[int]$Length)

    $end=[Math]::Min($Buffer.Length,$Start+$Length)
    $startSafe=[Math]::Max(0,$Start)
    $lengthSafe=[Math]::Max(0,$end-$startSafe)
    if($lengthSafe -le 0){ return @() }

    $segment=New-Object byte[] $lengthSafe
    [Array]::Copy($Buffer,$startSafe,$segment,0,$lengthSafe)

    $items=@(
        foreach($encodingName in @('ASCII','Unicode')){
            $encoding=if($encodingName -eq 'ASCII'){[Text.Encoding]::ASCII}else{[Text.Encoding]::Unicode}
            $text=$encoding.GetString($segment)
            foreach($piece in ($text -split '[^\x20-\x7E]+')){
                if($piece.Length -lt 5){continue}
                if($piece -match '(?i)DeviceLink|Configure|Discover|Association|Attest|Apply|Acknowledge|Retrieve|Manager|Utilities|Progress|Result|Async|Preassociate|Enrollment'){
                    [pscustomobject]@{Encoding=$encodingName;Text=[string]$piece}
                }
            }
        }
    )

    @($items | Sort-Object Encoding,Text -Unique)
}

$results=@(
    foreach($idText in $InterfaceIds){
        $guid=[guid]$idText
        $binaryNeedle=$guid.ToByteArray()
        $asciiNeedle=[Text.Encoding]::ASCII.GetBytes($guid.ToString('D').ToUpperInvariant())
        $unicodeNeedle=[Text.Encoding]::Unicode.GetBytes($guid.ToString('D').ToUpperInvariant())

        $hitGroups=@(
            [pscustomobject]@{Kind='GuidBytes';Offsets=@([WindowsDeviceLinkResearch.BinarySearch]::FindAll($bytes,$binaryNeedle))},
            [pscustomobject]@{Kind='AsciiGuid';Offsets=@([WindowsDeviceLinkResearch.BinarySearch]::FindAll($bytes,$asciiNeedle))},
            [pscustomobject]@{Kind='UnicodeGuid';Offsets=@([WindowsDeviceLinkResearch.BinarySearch]::FindAll($bytes,$unicodeNeedle))}
        )

        foreach($group in $hitGroups){
            foreach($offset in $group.Offsets){
                $contextStart=[Math]::Max(0,[int]$offset-$ContextBytes)
                $contextLength=[Math]::Min($bytes.Length-$contextStart,($ContextBytes*2)+64)
                [pscustomobject]@{
                    InterfaceId=$guid.ToString('D').ToUpperInvariant()
                    MatchKind=$group.Kind
                    Offset=[int64]$offset
                    ContextStrings=@(Get-ContextStrings -Buffer $bytes -Start $contextStart -Length $contextLength)
                }
            }
        }
    }
)

[pscustomobject]@{
    PSTypeName='Windows.DeviceLink.Research.IidBinaryContext'
    DllPath=$resolvedDll
    DllVersion=(Get-Item -LiteralPath $resolvedDll).VersionInfo.FileVersion
    MatchCount=@($results).Count
    Matches=@($results)
    ReadOnly=$true
}
