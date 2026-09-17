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

    No retry, firmware reset, cloud deletion or reboot is performed automatically.
    #>
    [CmdletBinding(SupportsShouldProcess=$true,ConfirmImpact='High')]
    param(
        [ValidateRange(5,600)]
        [int]$TimeoutSeconds = 180
    )

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

    $beforeFirmware=@(Get-WindowsDeviceLinkFirmwareState)
    $beforePresent=@($beforeFirmware|Where-Object Present|Select-Object -ExpandProperty Name)
    $expectedBefore=@('DeviceLinkId','DeviceLinkCreationTimeUtc')

    $alreadyComplete=(@($beforePresent).Count -eq 4 -and
        'DeviceLinkId' -in $beforePresent -and
        'DeviceLinkJwtCompressed' -in $beforePresent -and
        'DeviceLinkJwtLastWrite' -in $beforePresent -and
        'DeviceLinkCreationTimeUtc' -in $beforePresent)

    if ($alreadyComplete) {
        $existingJwt=Test-WindowsDeviceLinkAssociationJwt
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

    $identity = Get-WindowsDeviceLink -TimeoutSeconds $TimeoutSeconds
    $target = if($identity.LinkId){$identity.LinkId}else{'current device'}
    if(-not $PSCmdlet.ShouldProcess($target,'Complete DeviceLink association using native ConfigureDeviceLinkAsync')){
        return
    }

    $native=[WinPEDeviceLink.Native.DeviceLinkManagerClient]::ConfigureRegistered($identity.DeviceLink,$TimeoutSeconds)

    $afterFirmware=@(Get-WindowsDeviceLinkFirmwareState)
    $afterPresent=@($afterFirmware|Where-Object Present|Select-Object -ExpandProperty Name)
    $firmwareComplete=(@($afterPresent).Count -eq 4 -and
        'DeviceLinkId' -in $afterPresent -and
        'DeviceLinkJwtCompressed' -in $afterPresent -and
        'DeviceLinkJwtLastWrite' -in $afterPresent -and
        'DeviceLinkCreationTimeUtc' -in $afterPresent)

    $jwt=Test-WindowsDeviceLinkAssociationJwt
    $jwtValid=($jwt.State -eq 'Valid' -and $jwt.Present -and $jwt.IdentityMatch -ne $false)
    $nativeSucceeded=($native.ConfigureAsyncStatus -eq 1 -and $native.ConfigureAsyncError -eq 0 -and $native.ConfigureOperationResult -eq 1)

    if(-not $nativeSucceeded -or -not $firmwareComplete -or -not $jwtValid){
        $hr='0x{0:X8}' -f ([BitConverter]::ToUInt32([BitConverter]::GetBytes([int]$native.ConfigureAsyncError),0))
        throw "DeviceLink Configure completed without the expected verified post-state. NativeSuccess=$nativeSucceeded; AsyncStatus=$($native.ConfigureAsyncStatus); AsyncError=$hr; OperationResult=$($native.ConfigureOperationResult); FirmwareComplete=$firmwareComplete; JwtState=$($jwt.State); IdentityMatch=$($jwt.IdentityMatch). No cleanup or retry was performed."
    }

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
        RetryCount=0
        CleanupInvoked=$false
        RebootInvoked=$false
    }
}
