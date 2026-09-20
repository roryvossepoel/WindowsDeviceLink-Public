function Test-WindowsDeviceLinkHealth {
    <#
    .SYNOPSIS
    Classifies Windows DeviceLink status into machine-readable health states.

    .DESCRIPTION
    Evaluates a Windows.DeviceLink.Status object and returns a non-destructive health assessment.
    When no InputObject is supplied, the cmdlet obtains local-only status by calling
    Get-WindowsDeviceLinkStatus. To assess tenant-side state, first call
    Get-WindowsDeviceLinkStatus -Online and pipe the result to this cmdlet.

    The assessment deliberately distinguishes observed state from recommended action.
    It does not repair, reset, register, remove, reboot, or otherwise modify DeviceLink state.

    Firmware patterns are based on states validated by this project:
      2/4 = base local state (DeviceLinkId + DeviceLinkCreationTimeUtc)
      4/4 = complete known firmware state
      1/4 or 3/4 = incomplete/unexpected known-variable set

    .EXAMPLE
    Test-WindowsDeviceLinkHealth | Format-List *

    Performs a local-only status collection and assessment.

    .EXAMPLE
    Get-WindowsDeviceLinkStatus -Online -Method DeviceCode |
        Test-WindowsDeviceLinkHealth |
        Format-List *

    Assesses combined local and tenant-side state without performing any repair action.
    #>
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline)]
        [PSTypeName('Windows.DeviceLink.Status')]
        [psobject]$InputObject
    )

    process {
        $status = if ($PSBoundParameters.ContainsKey('InputObject') -and $null -ne $InputObject) {
            $InputObject
        }
        else {
            Get-WindowsDeviceLinkStatus
        }

        $state = 'Unknown'
        $severity = 'Warning'
        $summary = 'The DeviceLink state could not be classified.'
        $recommendedAction = 'Review the detailed status and error properties.'

        if (-not $status.Supported) {
            $state = 'Unsupported'
            $severity = 'Error'
            $summary = 'DeviceLink is not supported in the current runtime or environment.'
            $recommendedAction = 'Resolve the support/runtime issue before using DeviceLink operations.'
        }
        elseif (-not $status.DeviceLinkPresent) {
            $state = 'IdentityUnavailable'
            $severity = 'Error'
            $summary = 'A local DeviceLink identity could not be obtained.'
            $recommendedAction = 'Review IdentityError and runtime support details.'
        }
        elseif (-not $status.FirmwareChecked) {
            $state = 'FirmwareUnavailable'
            $severity = 'Error'
            $summary = 'Local DeviceLink firmware state could not be read.'
            $recommendedAction = 'Review FirmwareError and confirm elevated firmware access is available.'
        }
        elseif ($status.CloudChecked -and $status.AssociationState -eq 'Unknown') {
            $state = 'CloudUnknown'
            $severity = 'Warning'
            $summary = 'Local DeviceLink state is available, but tenant-side association state could not be determined.'
            $recommendedAction = 'Review AssociationError and retry the tenant-side lookup.'
        }
        else {
            $presentCount = $null
            if ([string]$status.FirmwareVariablesPresent -match '^(\d+)/4$') {
                $presentCount = [int]$Matches[1]
            }

            if ($null -eq $presentCount) {
                $state = 'FirmwareStateUnknown'
                $severity = 'Warning'
                $summary = 'Firmware state was read but the known-variable count could not be classified.'
                $recommendedAction = 'Inspect Get-WindowsDeviceLinkFirmwareState output.'
            }
            elseif ($presentCount -in @(1,3)) {
                $state = 'IncompleteFirmwareState'
                $severity = 'Warning'
                $summary = "An unexpected partial DeviceLink firmware state was observed ($presentCount/4 known variables)."
                $recommendedAction = 'Inspect the individual firmware variables before considering reset or repair.'
            }
            elseif ($presentCount -eq 0) {
                $state = 'NoFirmwareState'
                $severity = 'Warning'
                $summary = 'No known DeviceLink firmware variables are present.'
                $recommendedAction = 'Confirm whether this is an intentional clean/reset state before generating or registering a DeviceLink.'
            }
            elseif (-not $status.CloudChecked) {
                if ($presentCount -eq 2) {
                    $state = 'LocalBaseIdentity'
                    $severity = 'Information'
                    $summary = 'The validated local base DeviceLink state is present; tenant-side state was not checked.'
                    $recommendedAction = 'No action is required for local-only use. Use Get-WindowsDeviceLinkStatus -Online when tenant-side state is needed.'
                }
                elseif ($presentCount -eq 4) {
                    $state = 'LocalCompleteFirmwareState'
                    $severity = 'Information'
                    $summary = 'All four known DeviceLink firmware variables are present; tenant-side state was not checked.'
                    $recommendedAction = 'No local action is implied. Use Get-WindowsDeviceLinkStatus -Online to correlate with Intune when needed.'
                }
            }
            elseif (-not $status.AssociationPresent -and $status.AssociationState -eq 'NotAssociated') {
                if ($presentCount -eq 2) {
                    $state = 'LocalOnly'
                    $severity = 'Information'
                    $summary = 'A local base DeviceLink identity exists, but no tenant-side Device Association was found.'
                    $recommendedAction = 'Register the DeviceLink only if a tenant-side preassociation is intended.'
                }
                elseif ($presentCount -eq 4) {
                    $state = 'CloudAssociationMissingWithCompleteFirmware'
                    $severity = 'Warning'
                    $summary = 'All four known firmware variables are present, but no tenant-side Device Association was found.'
                    $recommendedAction = 'Review the device lifecycle before changing state; server-side removal does not automatically clear local firmware state.'
                }
            }
            elseif ($status.AssociationPresent -and $status.AssociationState -eq 'preassociated') {
                if ($presentCount -eq 2) {
                    $state = 'Preassociated'
                    $severity = 'Information'
                    $summary = 'The validated base firmware state and tenant-side preassociation are both present.'
                    $recommendedAction = 'Continue the normal Device Association lifecycle; no repair action is indicated.'
                }
                else {
                    $state = 'PreassociatedUnexpectedFirmwareState'
                    $severity = 'Warning'
                    $summary = "The tenant reports preassociated while $presentCount/4 known firmware variables are present."
                    $recommendedAction = 'Review the lifecycle state before performing reset, removal, or re-registration.'
                }
            }
            elseif ($status.AssociationPresent -and $status.AssociationState -eq 'associated') {
                if ($presentCount -eq 4) {
                    $state = 'Associated'
                    $severity = 'Information'
                    $summary = 'The tenant reports associated and all four known DeviceLink firmware variables are present.'
                    $recommendedAction = 'No action is indicated.'
                }
                else {
                    $state = 'AssociatedIncompleteFirmwareState'
                    $severity = 'Warning'
                    $summary = "The tenant reports associated, but only $presentCount/4 known firmware variables are present."
                    $recommendedAction = 'Re-check after the normal lifecycle/reboot before considering repair; do not reset state solely from this observation.'
                }
            }
            else {
                $state = 'UnclassifiedAssociationState'
                $severity = 'Warning'
                $summary = "The Device Association state '$($status.AssociationState)' is not yet classified by this preview."
                $recommendedAction = 'Preserve the status output and review the lifecycle before taking action.'
            }
        }

        [pscustomobject]@{
            PSTypeName               = 'Windows.DeviceLink.Health'
            State                    = $state
            Severity                 = $severity
            Summary                  = $summary
            RecommendedAction        = $recommendedAction
            Environment              = $status.Environment
            Supported                = $status.Supported
            DeviceLinkPresent        = $status.DeviceLinkPresent
            LinkId                   = $status.LinkId
            FirmwareVariablesPresent = $status.FirmwareVariablesPresent
            FirmwareStateComplete    = $status.FirmwareStateComplete
            FirmwareCreationTimeUtc  = $status.FirmwareCreationTimeUtc
            CloudChecked             = $status.CloudChecked
            AssociationPresent       = $status.AssociationPresent
            AssociationState         = $status.AssociationState
            AssociationId            = $status.AssociationId
            SupportReason            = $status.SupportReason
            IdentityError            = $status.IdentityError
            FirmwareError            = $status.FirmwareError
            AssociationError         = $status.AssociationError
        }
    }
}
