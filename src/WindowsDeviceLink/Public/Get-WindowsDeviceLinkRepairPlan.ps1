function Get-WindowsDeviceLinkRepairPlan {
    <#
    .SYNOPSIS
    Creates a non-destructive DeviceLink lifecycle repair plan.

    .DESCRIPTION
    Converts a Windows.DeviceLink.Health assessment into a machine-readable lifecycle plan.
    This cmdlet never registers, removes, resets, or reboots a device. It deliberately avoids
    inferring destructive repair from an unhealthy or unknown state.

    When no InputObject is supplied, local-only health is collected. For tenant-aware planning,
    pipe the output of Get-WindowsDeviceLinkStatus -Online through Test-WindowsDeviceLinkHealth.

    Destructive operations such as tenant association removal and local firmware reset are never
    marked safe for automatic execution by this planner. Those operations require an explicitly
    selected lifecycle scenario and administrator authorization outside this cmdlet.
    #>
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline)]
        [PSTypeName('Windows.DeviceLink.Health')]
        [psobject]$InputObject
    )

    process {
        $health = if ($PSBoundParameters.ContainsKey('InputObject') -and $null -ne $InputObject) {
            $InputObject
        }
        else {
            Get-WindowsDeviceLinkStatus | Test-WindowsDeviceLinkHealth
        }

        $action = 'Investigate'
        $reason = $health.RecommendedAction
        $requiresInvestigation = $true
        $requiresRegistration = $false
        $requiresCloudDelete = $false
        $requiresFirmwareReset = $false
        $requiresReboot = $false
        $safeToAutomate = $false

        switch ([string]$health.State) {
            'LocalOnly' {
                $action = 'UseInitialize'
                $reason = 'The local base identity is valid and no tenant association exists. Use Initialize-WindowsDeviceLink when preassociation is intended.'
                $requiresInvestigation = $false
                $requiresRegistration = $true
                $safeToAutomate = $true
            }
            'Preassociated' {
                $action = 'NoAction'
                $reason = 'The local base identity and tenant-side preassociation are healthy.'
                $requiresInvestigation = $false
                $safeToAutomate = $true
            }
            'Associated' {
                $action = 'NoAction'
                $reason = 'The tenant reports associated and the known local firmware state is complete.'
                $requiresInvestigation = $false
                $safeToAutomate = $true
            }
            'LocalBaseIdentity' {
                $action = 'NoLocalRepair'
                $reason = 'The validated local base identity is healthy. Tenant-side state was not checked, so no lifecycle repair can be inferred.'
                $requiresInvestigation = $false
                $safeToAutomate = $true
            }
            'LocalCompleteFirmwareState' {
                $action = 'CheckCloudState'
                $reason = 'All known local firmware variables are present, but tenant-side state was not checked. Check cloud state before considering lifecycle repair.'
                $requiresInvestigation = $false
                $safeToAutomate = $true
            }
            'CloudAssociationMissingWithCompleteFirmware' {
                $action = 'ReviewLifecycleIntent'
                $reason = 'Complete local firmware remains while no tenant association exists. This can follow intentional cloud removal; do not reset firmware until lifecycle intent is explicitly confirmed.'
            }
            'NoFirmwareState' {
                $action = 'ReviewLifecycleIntent'
                $reason = 'No known DeviceLink firmware variables are present. Confirm whether this is an intentional clean/reset state before generating a new identity.'
            }
            'IncompleteFirmwareState' {
                $action = 'InvestigateFirmware'
                $reason = 'A partial known firmware state is present. Do not reset automatically; inspect individual variables and lifecycle history first.'
            }
            'PreassociatedUnexpectedFirmwareState' {
                $action = 'InvestigateLifecycleMismatch'
                $reason = 'Tenant preassociation and local firmware shape disagree. Do not remove or reset either side automatically.'
            }
            'AssociatedIncompleteFirmwareState' {
                $action = 'RecheckThenInvestigate'
                $reason = 'The tenant reports associated but local firmware is incomplete. Re-check after the expected lifecycle/reboot before considering repair.'
            }
            'Unsupported' {
                $action = 'ResolveSupportIssue'
            }
            'IdentityUnavailable' {
                $action = 'ResolveIdentityIssue'
            }
            'FirmwareUnavailable' {
                $action = 'ResolveFirmwareAccessIssue'
            }
            'CloudUnknown' {
                $action = 'RetryCloudLookup'
                $reason = 'Tenant state is unknown. A cloud lookup failure can never authorize association removal or firmware reset.'
            }
            'FirmwareStateUnknown' {
                $action = 'InvestigateFirmware'
            }
            'UnclassifiedAssociationState' {
                $action = 'InvestigateAssociationState'
                $reason = 'The tenant association state is not classified. Preserve state and investigate; destructive lifecycle actions are blocked.'
            }
            default {
                $action = 'InvestigateUnknownState'
                $reason = "Health state '$($health.State)' is not recognized by the repair planner. Destructive lifecycle actions are blocked."
            }
        }

        [pscustomobject]@{
            PSTypeName              = 'Windows.DeviceLink.RepairPlan'
            CurrentState            = [string]$health.State
            Severity                = [string]$health.Severity
            Action                  = $action
            SafeToAutomate          = $safeToAutomate
            RequiresInvestigation   = $requiresInvestigation
            RequiresRegistration    = $requiresRegistration
            RequiresCloudDelete     = $requiresCloudDelete
            RequiresFirmwareReset   = $requiresFirmwareReset
            RequiresReboot          = $requiresReboot
            DestructiveActionsAllowed = $false
            Reason                  = $reason
            AssociationId           = $health.AssociationId
            AssociationState        = $health.AssociationState
            LinkId                  = $health.LinkId
            FirmwareVariablesPresent = $health.FirmwareVariablesPresent
            CloudChecked            = $health.CloudChecked
        }
    }
}
