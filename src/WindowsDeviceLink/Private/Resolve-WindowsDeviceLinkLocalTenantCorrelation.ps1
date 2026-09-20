function Resolve-WindowsDeviceLinkLocalTenantCorrelation {
    [CmdletBinding()]
    param(
        [string]$RegistryTenantId,
        [string]$JwtTenantId
    )

    $registry = if ([string]::IsNullOrWhiteSpace($RegistryTenantId)) { $null } else { $RegistryTenantId.Trim().Trim('{','}') }
    $jwt = if ([string]::IsNullOrWhiteSpace($JwtTenantId)) { $null } else { $JwtTenantId.Trim().Trim('{','}') }

    $match = $null
    if ($registry -and $jwt) {
        $match = [string]::Equals($registry,$jwt,[StringComparison]::OrdinalIgnoreCase)
    }

    if ($match -eq $false) {
        return [pscustomobject]@{ TenantId=$null; SourcesMatch=$false; Source='Conflict'; TrustLevel='Conflict'; Conflict=$true; Conclusion='The current-LinkId registry TenantIdHint and local Association JWT tenantId disagree. No source tenant was selected.' }
    }

    if ($registry -and $jwt) {
        return [pscustomobject]@{ TenantId=$jwt; SourcesMatch=$true; Source='RegistryAndAssociationJwt'; TrustLevel='CorrelatedLocalSources'; Conflict=$false; Conclusion='The current-LinkId registry TenantIdHint and local Association JWT tenantId agree.' }
    }

    if ($jwt) {
        return [pscustomobject]@{ TenantId=$jwt; SourcesMatch=$null; Source='AssociationJwt'; TrustLevel='StructurallyObservedJwtClaim'; Conflict=$false; Conclusion='The source tenant was observed in the local Association JWT. Cryptographic signature validation was not performed.' }
    }

    if ($registry) {
        return [pscustomobject]@{ TenantId=$registry; SourcesMatch=$null; Source='CurrentLinkIdRegistryHint'; TrustLevel='LocalRegistryHint'; Conflict=$false; Conclusion='The source tenant was observed in the TenantIdHint exactly scoped to the current DeviceLinkId.' }
    }

    [pscustomobject]@{ TenantId=$null; SourcesMatch=$null; Source='Unavailable'; TrustLevel='Unavailable'; Conflict=$false; Conclusion='No tenant identifier was found for the current DeviceLinkId in either known local source.' }
}
