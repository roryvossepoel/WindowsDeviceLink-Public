<#
.SYNOPSIS
Enumerates local MDM Bridge classes related to DevicePreparation / Device Association.

.DESCRIPTION
Queries root\cimv2\mdm\dmmap with Get-CimClass and returns only class/property/method
metadata for classes whose names or qualifiers suggest DevicePreparation, DeviceAssociation,
TenantAssociation, or DeviceLink.

This is a metadata-only research probe. It does not instantiate classes or invoke methods.
#>
[CmdletBinding()]
param()

$ErrorActionPreference='Stop'
$namespace='root\cimv2\mdm\dmmap'
$patterns=@('DevicePreparation','DeviceAssociation','TenantAssociation','DeviceLink')

$classes=@(Get-CimClass -Namespace $namespace -ErrorAction Stop)
$matches=@()

foreach($class in $classes){
    $qualifierText = @($class.CimClassQualifiers | ForEach-Object { "$($_.Name)=$($_.Value)" }) -join '; '
    $haystack = "$($class.CimClassName) $qualifierText"
    $matched = $patterns | Where-Object { $haystack -match [regex]::Escape($_) } | Select-Object -First 1
    if(-not $matched){ continue }

    $properties=@($class.CimClassProperties | ForEach-Object {
        [pscustomobject]@{
            Name=[string]$_.Name
            CimType=[string]$_.CimType
            Flags=[string]$_.Flags
        }
    })

    $methods=@($class.CimClassMethods | ForEach-Object {
        [pscustomobject]@{
            Name=[string]$_.Name
            ReturnType=[string]$_.ReturnType
            Parameters=@($_.Parameters | ForEach-Object {
                [pscustomobject]@{Name=[string]$_.Name;CimType=[string]$_.CimType;Flags=[string]$_.Flags}
            })
        }
    })

    $matches += [pscustomobject]@{
        CimClassName=[string]$class.CimClassName
        MatchedPattern=[string]$matched
        Qualifiers=$qualifierText
        Properties=@($properties)
        Methods=@($methods)
    }
}

[pscustomobject]@{
    PSTypeName='Windows.DeviceLink.Research.CspInventory'
    Namespace=$namespace
    MatchCount=@($matches).Count
    Classes=@($matches)
    ReadOnly=$true
}
