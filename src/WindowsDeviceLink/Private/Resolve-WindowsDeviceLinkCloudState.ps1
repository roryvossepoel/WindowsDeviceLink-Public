function Resolve-WindowsDeviceLinkCloudState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][bool]$CloudChecked,
        [AllowNull()][psobject]$Association,
        [AllowNull()][string]$AssociationError
    )

    if (-not $CloudChecked) {
        return [pscustomobject]@{ AssociationPresent=$null; AssociationState=$null }
    }

    if (-not [string]::IsNullOrWhiteSpace($AssociationError)) {
        # Any authentication, transport, API, duplicate-result, or parsing failure is
        # indeterminate. Never collapse it to confirmed absence.
        return [pscustomobject]@{ AssociationPresent=$null; AssociationState='Unknown' }
    }

    if ($null -ne $Association) {
        return [pscustomobject]@{ AssociationPresent=$true; AssociationState=[string]$Association.AssociationState }
    }

    [pscustomobject]@{ AssociationPresent=$false; AssociationState='NotAssociated' }
}
