function Protect-WindowsDeviceLinkObject {
    [CmdletBinding()]
    param(
        [AllowNull()]$InputObject,
        [AllowNull()][string[]]$SensitiveValue,
        [ValidateRange(0,16)][int]$Depth = 0,
        [ValidateRange(1,16)][int]$MaxDepth = 8
    )

    if ($null -eq $InputObject) { return $null }
    if ($Depth -ge $MaxDepth) { return '[TRUNCATED]' }

    if ($InputObject -is [string]) {
        return Protect-WindowsDeviceLinkSensitiveText -Text ([string]$InputObject) -SensitiveValue $SensitiveValue
    }

    if ($InputObject -is [System.Collections.IDictionary]) {
        $copy = [ordered]@{}
        foreach ($key in $InputObject.Keys) {
            $copy[$key] = Protect-WindowsDeviceLinkObject -InputObject $InputObject[$key] -SensitiveValue $SensitiveValue -Depth ($Depth + 1) -MaxDepth $MaxDepth
        }
        return [pscustomobject]$copy
    }

    if ($InputObject -is [System.Collections.IEnumerable] -and $InputObject -isnot [string]) {
        $items = @()
        foreach ($item in $InputObject) {
            $items += ,(Protect-WindowsDeviceLinkObject -InputObject $item -SensitiveValue $SensitiveValue -Depth ($Depth + 1) -MaxDepth $MaxDepth)
        }
        return $items
    }

    $properties = @($InputObject.PSObject.Properties | Where-Object { $_.MemberType -in @('NoteProperty','Property','AliasProperty') })
    if ($properties.Count -gt 0 -and $InputObject -isnot [ValueType]) {
        $copy = [ordered]@{}
        foreach ($property in $properties) {
            try {
                $copy[$property.Name] = Protect-WindowsDeviceLinkObject -InputObject $property.Value -SensitiveValue $SensitiveValue -Depth ($Depth + 1) -MaxDepth $MaxDepth
            }
            catch {
                $copy[$property.Name] = '[UNAVAILABLE]'
            }
        }
        return [pscustomobject]$copy
    }

    $InputObject
}
