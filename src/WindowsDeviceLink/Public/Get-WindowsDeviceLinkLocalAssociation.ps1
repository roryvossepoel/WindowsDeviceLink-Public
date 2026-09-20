function Get-WindowsDeviceLinkLocalAssociation {
    <#
    .SYNOPSIS
    Reads and correlates local DeviceLink tenant-association metadata.

    .DESCRIPTION
    Performs a read-only correlation of the current DeviceLinkId with two known local
    tenant-identification sources:

    - HKLM:\SOFTWARE\Microsoft\Provisioning\AutopilotSettings\<LinkId>_TenantIdHint
    - the tenantId claim in DeviceLinkJwtCompressed, when the Association JWT is present

    Historical registry hints are counted but never selected. Only registry values whose
    prefix exactly matches the current UEFI DeviceLinkId are considered.

    When both local sources are present and agree, TrustLevel is CorrelatedLocalSources.
    When they disagree, the cmdlet fails closed by returning no TenantId and setting
    ConflictDetected to True.

    The raw Association JWT, signature, DeviceLinkId firmware bytes, TPM material, and
    unrelated JWT claim values are never returned. No Microsoft Graph or other cloud
    request is performed.

    Association JWT signature validation is not currently performed because a supported
    signing-key discovery mechanism for the observed DeviceTag token has not been established.

    .OUTPUTS
    PSCustomObject with local DeviceLink association and tenant-correlation metadata.

    .EXAMPLE
    Get-WindowsDeviceLinkLocalAssociation | Format-List *

    Reads local DeviceLink association metadata without cloud authentication.

    .NOTES
    This command reports local evidence only. It does not prove that a tenant-side Device
    Association record currently exists.
    #>
    [CmdletBinding()]
    param()

    $firmware = @(Get-WindowsDeviceLinkFirmwareState)
    $presentCount = @($firmware | Where-Object Present).Count
    $firmwareState = ('{0}/4' -f $presentCount)

    $localState = switch ($presentCount) {
        0 { 'NoFirmwareState' }
        2 { 'BaseIdentity' }
        4 { 'CompleteAssociationFirmwareState' }
        default { 'IncompleteFirmwareState' }
    }

    $registryPath = 'HKLM:\SOFTWARE\Microsoft\Provisioning\AutopilotSettings'
    $historicalHintCount = 0
    if (Test-Path -LiteralPath $registryPath) {
        try {
            $registryBaseline = Get-ItemProperty -LiteralPath $registryPath -ErrorAction Stop
            $historicalHintCount = @(
                $registryBaseline.PSObject.Properties |
                    Where-Object { $_.Name -match '(?i)_TenantIdHint
        return [pscustomobject]@{
            PSTypeName='Windows.DeviceLink.LocalAssociation'; LocalAssociationState=$localState; FirmwareState=$firmwareState;
            LinkId=$null; TenantId=$null; DiscoveryUrl=$null; RegistryHintPresent=$false; RegistryTenantIdHint=$null;
            RegistryDiscoveryUrl=$null; HistoricalTenantHintCount=$historicalHintCount; JwtPresent=$false; JwtParseState='Absent';
            JwtEncoding=$null; JwtTenantId=$null; JwtTenantClaim=$null; JwtDiscoveryUrl=$null; TenantSourcesMatch=$null;
            Source='Unavailable'; TrustLevel='Unavailable'; SignatureValidation='NotPerformed'; ConflictDetected=$false;
            CloudChecked=$false; Conclusion='The current DeviceLinkId is unavailable, so local tenant correlation cannot be performed.'
        }
    }

    try {
        $linkId = ConvertFrom-WindowsDeviceLinkIdBytes -Bytes $linkRaw.Bytes
        if (-not $linkId) { throw 'The current DeviceLinkId firmware value could not be safely decoded as a GUID.' }

        $registryTenant = $null
        $registryDiscoveryUrl = $null
        $registryHintPresent = $false

        if (Test-Path -LiteralPath $registryPath) {
            $registry = Get-ItemProperty -LiteralPath $registryPath -ErrorAction Stop
            $tenantPropertyName = "$($linkId)_TenantIdHint"
            $discoveryPropertyName = "$($linkId)_DiscoveryUrl"

            $historicalHintCount = @($registry.PSObject.Properties | Where-Object { $_.Name -match '(?i)_TenantIdHint$' }).Count

            if ($registry.PSObject.Properties.Name -contains $tenantPropertyName) {
                $value = [string]$registry.$tenantPropertyName
                if (-not [string]::IsNullOrWhiteSpace($value)) {
                    $registryTenant = $value.Trim().Trim('{','}')
                    $registryHintPresent = $true
                }
            }

            if ($registry.PSObject.Properties.Name -contains $discoveryPropertyName) {
                $value = [string]$registry.$discoveryPropertyName
                if (-not [string]::IsNullOrWhiteSpace($value)) { $registryDiscoveryUrl = $value }
            }
        }

        $jwt = Get-WindowsDeviceLinkLocalAssociationJwtMetadata
        $correlation = Resolve-WindowsDeviceLinkLocalTenantCorrelation -RegistryTenantId $registryTenant -JwtTenantId $jwt.TenantId

        $discoveryUrl = if (-not [string]::IsNullOrWhiteSpace($jwt.DiscoveryUrl)) { $jwt.DiscoveryUrl } else { $registryDiscoveryUrl }

        [pscustomobject]@{
            PSTypeName='Windows.DeviceLink.LocalAssociation'
            LocalAssociationState=$localState
            FirmwareState=$firmwareState
            LinkId=$linkId
            TenantId=$correlation.TenantId
            DiscoveryUrl=$discoveryUrl
            RegistryHintPresent=$registryHintPresent
            RegistryTenantIdHint=$registryTenant
            RegistryDiscoveryUrl=$registryDiscoveryUrl
            HistoricalTenantHintCount=$historicalHintCount
            JwtPresent=[bool]$jwt.Present
            JwtParseState=$jwt.ParseState
            JwtEncoding=$jwt.Encoding
            JwtTenantId=$jwt.TenantId
            JwtTenantClaim=$jwt.TenantClaim
            JwtDiscoveryUrl=$jwt.DiscoveryUrl
            TenantSourcesMatch=$correlation.SourcesMatch
            Source=$correlation.Source
            TrustLevel=$correlation.TrustLevel
            SignatureValidation=$jwt.SignatureValidation
            ConflictDetected=$correlation.Conflict
            CloudChecked=$false
            Conclusion=$correlation.Conclusion
        }
    }
    finally {
        if ($linkRaw -and $linkRaw.Bytes) { [Array]::Clear($linkRaw.Bytes,0,$linkRaw.Bytes.Length) }
        $linkRaw = $null
    }
}
 }
            ).Count
        }
        catch {}
    }

    $linkRaw = Get-WindowsDeviceLinkFirmwareVariableBytes -Name DeviceLinkId
    if (-not $linkRaw.Present -or -not $linkRaw.Bytes) {
        return [pscustomobject]@{
            PSTypeName='Windows.DeviceLink.LocalAssociation'; LocalAssociationState=$localState; FirmwareState=$firmwareState;
            LinkId=$null; TenantId=$null; DiscoveryUrl=$null; RegistryHintPresent=$false; RegistryTenantIdHint=$null;
            RegistryDiscoveryUrl=$null; HistoricalTenantHintCount=0; JwtPresent=$false; JwtParseState='Absent';
            JwtEncoding=$null; JwtTenantId=$null; JwtTenantClaim=$null; JwtDiscoveryUrl=$null; TenantSourcesMatch=$null;
            Source='Unavailable'; TrustLevel='Unavailable'; SignatureValidation='NotPerformed'; ConflictDetected=$false;
            CloudChecked=$false; Conclusion='The current DeviceLinkId is unavailable, so local tenant correlation cannot be performed.'
        }
    }

    try {
        $linkId = ConvertFrom-WindowsDeviceLinkIdBytes -Bytes $linkRaw.Bytes
        if (-not $linkId) { throw 'The current DeviceLinkId firmware value could not be safely decoded as a GUID.' }

        $registryPath = 'HKLM:\SOFTWARE\Microsoft\Provisioning\AutopilotSettings'
        $registryTenant = $null
        $registryDiscoveryUrl = $null
        $registryHintPresent = $false
        $historicalHintCount = 0

        if (Test-Path -LiteralPath $registryPath) {
            $registry = Get-ItemProperty -LiteralPath $registryPath -ErrorAction Stop
            $tenantPropertyName = "$($linkId)_TenantIdHint"
            $discoveryPropertyName = "$($linkId)_DiscoveryUrl"

            $historicalHintCount = @($registry.PSObject.Properties | Where-Object { $_.Name -match '(?i)_TenantIdHint$' }).Count

            if ($registry.PSObject.Properties.Name -contains $tenantPropertyName) {
                $value = [string]$registry.$tenantPropertyName
                if (-not [string]::IsNullOrWhiteSpace($value)) {
                    $registryTenant = $value.Trim().Trim('{','}')
                    $registryHintPresent = $true
                }
            }

            if ($registry.PSObject.Properties.Name -contains $discoveryPropertyName) {
                $value = [string]$registry.$discoveryPropertyName
                if (-not [string]::IsNullOrWhiteSpace($value)) { $registryDiscoveryUrl = $value }
            }
        }

        $jwt = Get-WindowsDeviceLinkLocalAssociationJwtMetadata
        $correlation = Resolve-WindowsDeviceLinkLocalTenantCorrelation -RegistryTenantId $registryTenant -JwtTenantId $jwt.TenantId

        $discoveryUrl = if (-not [string]::IsNullOrWhiteSpace($jwt.DiscoveryUrl)) { $jwt.DiscoveryUrl } else { $registryDiscoveryUrl }

        [pscustomobject]@{
            PSTypeName='Windows.DeviceLink.LocalAssociation'
            LocalAssociationState=$localState
            FirmwareState=$firmwareState
            LinkId=$linkId
            TenantId=$correlation.TenantId
            DiscoveryUrl=$discoveryUrl
            RegistryHintPresent=$registryHintPresent
            RegistryTenantIdHint=$registryTenant
            RegistryDiscoveryUrl=$registryDiscoveryUrl
            HistoricalTenantHintCount=$historicalHintCount
            JwtPresent=[bool]$jwt.Present
            JwtParseState=$jwt.ParseState
            JwtEncoding=$jwt.Encoding
            JwtTenantId=$jwt.TenantId
            JwtTenantClaim=$jwt.TenantClaim
            JwtDiscoveryUrl=$jwt.DiscoveryUrl
            TenantSourcesMatch=$correlation.SourcesMatch
            Source=$correlation.Source
            TrustLevel=$correlation.TrustLevel
            SignatureValidation=$jwt.SignatureValidation
            ConflictDetected=$correlation.Conflict
            CloudChecked=$false
            Conclusion=$correlation.Conclusion
        }
    }
    finally {
        if ($linkRaw -and $linkRaw.Bytes) { [Array]::Clear($linkRaw.Bytes,0,$linkRaw.Bytes.Length) }
        $linkRaw = $null
    }
}
