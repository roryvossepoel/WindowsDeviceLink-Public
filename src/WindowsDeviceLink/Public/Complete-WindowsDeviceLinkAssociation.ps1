function Complete-WindowsDeviceLinkAssociation {
    <#
    .SYNOPSIS
    Completes device-side DeviceLink association after tenant preassociation.

    .DESCRIPTION
    Performs a guarded native DeviceLink Configure operation on full Windows. The cmdlet requires
    a healthy preflight and a clean local preassociation firmware state (DeviceLinkId plus
    DeviceLinkCreationTimeUtc only), invokes ConfigureDeviceLinkAsync exactly once, and then
    verifies that all four known DeviceLink firmware variables are present and the resulting
    association JWT is structurally/temporally valid and bound to the current device identity.

    Progress information is emitted for each major phase. While the native Windows configure
    operation remains in progress, a heartbeat is emitted every 15 seconds with elapsed time.
    This is observational only; no percentage-complete is invented and progress reporting cannot
    trigger retries or alter the native operation.

    No retry, firmware reset, cloud deletion or reboot is performed automatically.
    #>
    [CmdletBinding(SupportsShouldProcess=$true,ConfirmImpact='High')]
    param(
        [ValidateRange(5,600)]
        [int]$TimeoutSeconds = 180
    )

    $totalTimer=[Diagnostics.Stopwatch]::StartNew()

    Write-Information -InformationAction Continue -MessageData 'Starting device-side DeviceLink association completion...'
    Write-Information -InformationAction Continue -MessageData 'Validating DeviceLink runtime and prerequisites...'

    $support = Test-WindowsDeviceLinkSupport
    if (-not $support.Supported) {
        throw "DeviceLink isn't supported: $($support.Reason)"
    }
    if ($support.Environment -ne 'Windows' -or $support.ActivationMode -ne 'RegisteredWinRT') {
        throw 'DeviceLink association completion currently requires full Windows with the registered DeviceLink WinRT runtime.'
    }

    $preflight = Test-WindowsDeviceLinkPreflight
    if ($preflight.BlockingCount -gt 0) {
        $blocked=@($preflight.Checks|Where-Object State -eq 'Blocked'|ForEach-Object{"$($_.Name): $($_.Summary)"})
        throw "DeviceLink preflight is blocked: $($blocked -join '; ')"
    }
    Write-Information -InformationAction Continue -MessageData "DeviceLink preflight passed. Warnings: $($preflight.WarningCount); blockers: $($preflight.BlockingCount)."

    Write-Information -InformationAction Continue -MessageData 'Inspecting local DeviceLink firmware state...'
    $beforeFirmware=@(Get-WindowsDeviceLinkFirmwareState)
    $beforePresent=@($beforeFirmware|Where-Object Present|Select-Object -ExpandProperty Name)
    $expectedBefore=@('DeviceLinkId','DeviceLinkCreationTimeUtc')

    $alreadyComplete=(@($beforePresent).Count -eq 4 -and
        'DeviceLinkId' -in $beforePresent -and
        'DeviceLinkJwtCompressed' -in $beforePresent -and
        'DeviceLinkJwtLastWrite' -in $beforePresent -and
        'DeviceLinkCreationTimeUtc' -in $beforePresent)

    if ($alreadyComplete) {
        Write-Information -InformationAction Continue -MessageData 'Local DeviceLink firmware state is already complete (4/4). Validating the existing association JWT...'
        $existingJwt=Test-WindowsDeviceLinkAssociationJwt
        $totalTimer.Stop()
        Write-Information -InformationAction Continue -MessageData "Existing DeviceLink association is complete. JWT state: $($existingJwt.State); identity match: $($existingJwt.IdentityMatch)."
        return [pscustomobject]@{
            PSTypeName='Windows.DeviceLink.AssociationCompletion'
            Changed=$false
            AlreadyComplete=$true
            Result='AlreadyComplete'
            ConfigureOperationResult=$null
            ConfigureAsyncStatus=$null
            ConfigureAsyncError=$null
            FirmwareVariablesPresent='4/4'
            JwtState=$existingJwt.State
            IdentityMatch=$existingJwt.IdentityMatch
            DiscoveryDurationSeconds=$null
            ConfigureDurationSeconds=$null
            VerificationDurationSeconds=[math]::Round($totalTimer.Elapsed.TotalSeconds,1)
            TotalDurationSeconds=[math]::Round($totalTimer.Elapsed.TotalSeconds,1)
            RetryCount=0
            CleanupInvoked=$false
            RebootInvoked=$false
        }
    }

    $cleanPreassociation=(@($beforePresent).Count -eq 2 -and
        ($expectedBefore|Where-Object{$_ -notin $beforePresent}).Count -eq 0)
    if (-not $cleanPreassociation) {
        throw "Refusing DeviceLink association completion because local firmware state is not the expected clean preassociation state. Present: $($beforePresent -join ', ')."
    }
    Write-Information -InformationAction Continue -MessageData 'Local DeviceLink preassociation state verified (2/4).'

    Write-Information -InformationAction Continue -MessageData 'Obtaining the current local DeviceLink identity...'
    $identity = Get-WindowsDeviceLink -TimeoutSeconds $TimeoutSeconds
    $target = if($identity.LinkId){$identity.LinkId}else{'current device'}
    if(-not $PSCmdlet.ShouldProcess($target,'Complete DeviceLink association using native ConfigureDeviceLinkAsync')){
        return
    }

    $progressCallback=[Action[string]]{
        param([string]$message)
        Write-Information -InformationAction Continue -MessageData $message
    }

    $native=[WinPEDeviceLink.Native.DeviceLinkManagerClient]::ConfigureRegistered(
        $identity.DeviceLink,
        $TimeoutSeconds,
        $progressCallback
    )

    $verificationTimer=[Diagnostics.Stopwatch]::StartNew()
    Write-Information -InformationAction Continue -MessageData 'Verifying DeviceLink firmware state after native configuration...'
    $afterFirmware=@(Get-WindowsDeviceLinkFirmwareState)
    $afterPresent=@($afterFirmware|Where-Object Present|Select-Object -ExpandProperty Name)
    $firmwareComplete=(@($afterPresent).Count -eq 4 -and
        'DeviceLinkId' -in $afterPresent -and
        'DeviceLinkJwtCompressed' -in $afterPresent -and
        'DeviceLinkJwtLastWrite' -in $afterPresent -and
        'DeviceLinkCreationTimeUtc' -in $afterPresent)
    Write-Information -InformationAction Continue -MessageData "DeviceLink firmware variables present: $(@($afterPresent).Count)/4."

    Write-Information -InformationAction Continue -MessageData 'Validating the resulting DeviceLink association JWT...'
    $jwt=Test-WindowsDeviceLinkAssociationJwt
    $jwtValid=($jwt.State -eq 'Valid' -and $jwt.Present -and $jwt.IdentityMatch -ne $false)
    Write-Information -InformationAction Continue -MessageData "Association JWT validation completed. State: $($jwt.State); identity match: $($jwt.IdentityMatch); signature validation: $($jwt.SignatureValidation)."

    $nativeSucceeded=($native.ConfigureAsyncStatus -eq 1 -and $native.ConfigureAsyncError -eq 0 -and $native.ConfigureOperationResult -eq 1)
    $verificationTimer.Stop()
    $totalTimer.Stop()

    if(-not $nativeSucceeded -or -not $firmwareComplete -or -not $jwtValid){
        $hr='0x{0:X8}' -f ([BitConverter]::ToUInt32([BitConverter]::GetBytes([int]$native.ConfigureAsyncError),0))
        throw "DeviceLink Configure completed without the expected verified post-state. NativeSuccess=$nativeSucceeded; AsyncStatus=$($native.ConfigureAsyncStatus); AsyncError=$hr; OperationResult=$($native.ConfigureOperationResult); FirmwareComplete=$firmwareComplete; JwtState=$($jwt.State); IdentityMatch=$($jwt.IdentityMatch). No cleanup or retry was performed."
    }

    Write-Information -InformationAction Continue -MessageData "DeviceLink association completion verified successfully in $([math]::Round($totalTimer.Elapsed.TotalSeconds,1)) seconds."

    $errorHex='0x{0:X8}' -f ([BitConverter]::ToUInt32([BitConverter]::GetBytes([int]$native.ConfigureAsyncError),0))
    [pscustomobject]@{
        PSTypeName='Windows.DeviceLink.AssociationCompletion'
        Changed=$true
        AlreadyComplete=$false
        Result='AssociatedLocally'
        LinkId=$identity.LinkId
        TenantId=$native.TenantId
        DiscoveryResult=$native.DiscoveryResult
        DiscoveryUrl=$native.DiscoveryUrl
        ConfigureResultBefore=$native.ConfigureResultBefore
        ConfigureResultAfter=$native.ConfigureResultAfter
        ConfigureOperationResult=$native.ConfigureOperationResult
        ConfigureAsyncStatus=$native.ConfigureAsyncStatus
        ConfigureAsyncError=$errorHex
        FirmwareVariablesPresent='4/4'
        JwtState=$jwt.State
        IdentityMatch=$jwt.IdentityMatch
        SignatureValidation=$jwt.SignatureValidation
        DiscoveryDurationSeconds=[math]::Round([double]$native.DiscoveryDurationSeconds,1)
        ConfigureDurationSeconds=[math]::Round([double]$native.ConfigureDurationSeconds,1)
        VerificationDurationSeconds=[math]::Round($verificationTimer.Elapsed.TotalSeconds,1)
        TotalDurationSeconds=[math]::Round($totalTimer.Elapsed.TotalSeconds,1)
        RetryCount=0
        CleanupInvoked=$false
        RebootInvoked=$false
    }
}
