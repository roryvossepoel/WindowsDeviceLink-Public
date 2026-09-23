function Resolve-WindowsDeviceLinkTenantAssignmentDecision {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateSet('Direct','Backend')][string]$OperationMode,
        [AllowNull()][AllowEmptyString()][string]$SourceTenantId,
        [string]$TargetTenantId,
        [Parameter(Mandatory)][ValidateSet('2/4','4/4')][string]$FirmwareState,
        [switch]$AssociationPresent
    )

    if ($OperationMode -eq 'Direct') {
        $decision = if ($AssociationPresent) { 'None' } else { 'New' }
    }
    else {
        if ([string]::IsNullOrWhiteSpace($TargetTenantId)) { throw 'Backend mode requires an explicit target tenant.' }
        $decision = if ([string]::IsNullOrWhiteSpace($SourceTenantId)) {
            'New'
        }
        elseif ($SourceTenantId -ieq $TargetTenantId) {
            'None'
        }
        else {
            'Move'
        }
    }

    # A backend registration is a deployment boundary. Always create a fresh local
    # identity for an actual New or Move operation; a locally cached 2/4 identity
    # may belong to a cloud association that was removed outside this catalog and
    # Microsoft Graph does not reliably accept that identity again.
    $renewIdentity = $OperationMode -eq 'Backend' -and $decision -in @('New','Move')
    [pscustomobject]@{
        PSTypeName='Windows.DeviceLink.TenantAssignmentDecision'
        OperationMode=$OperationMode
        Decision=$decision
        IdentityRenewalRequired=$renewIdentity
        ReasonCode=switch ($decision) {
            'Move' { 'WDL-BACKEND-MOVE' }
            'New' { if ($OperationMode -eq 'Direct') { 'WDL-DIRECT-NEW' } else { 'WDL-BACKEND-NEW' } }
            default { if ($OperationMode -eq 'Direct') { 'WDL-DIRECT-NO-CHANGE' } else { 'WDL-BACKEND-NO-CHANGE' } }
        }
    }
}
