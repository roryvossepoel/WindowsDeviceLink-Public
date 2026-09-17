function Test-WindowsDeviceLinkAssociationJwt {
    <#
    .SYNOPSIS
    Safely validates the local DeviceLink Association JWT artifact without returning raw JWT content.

    .DESCRIPTION
    Reads DeviceLinkJwtCompressed from firmware through a private byte reader, attempts supported
    decoding, parses JWT structure and temporal claims, and correlates a known LinkId claim when
    present. The raw JWT and payload are never returned.

    This cmdlet does not validate the JWT cryptographic signature. SignatureValidation is therefore
    always reported as NotPerformed in the current implementation.
    #>
    [CmdletBinding()]
    param(
        [ValidateRange(5,600)][int]$TimeoutSeconds = 120,
        [ValidateNotNullOrEmpty()][string]$WindowsManagementServicePath
    )

    $firmware = @(Get-WindowsDeviceLinkFirmwareState)
    $jwtState = $firmware | Where-Object Name -eq 'DeviceLinkJwtCompressed' | Select-Object -First 1

    if (-not $jwtState -or -not $jwtState.Present) {
        return [pscustomobject]@{
            PSTypeName='Windows.DeviceLink.AssociationJwtValidation'
            State='NotPresent'; Present=$false; Size=0; Encoding=$null; Algorithm=$null
            IssuedAtUtc=$null; NotBeforeUtc=$null; ExpiresUtc=$null
            IdentityClaimPresent=$false; IdentityMatch=$null; SignatureValidation='NotPerformed'
            Reason='DeviceLinkJwtCompressed is not present in firmware.'
        }
    }

    $raw = Get-WindowsDeviceLinkFirmwareVariableBytes -Name DeviceLinkJwtCompressed
    if (-not $raw.Present -or -not $raw.Bytes) {
        return [pscustomobject]@{
            PSTypeName='Windows.DeviceLink.AssociationJwtValidation'
            State='Unknown'; Present=$true; Size=[int]$jwtState.Size; Encoding=$null; Algorithm=$null
            IssuedAtUtc=$null; NotBeforeUtc=$null; ExpiresUtc=$null
            IdentityClaimPresent=$false; IdentityMatch=$null; SignatureValidation='NotPerformed'
            Reason='Firmware metadata reported the JWT as present, but the private byte read did not return content.'
        }
    }

    $expectedLinkId = $null
    try {
        $dlParams = @{ TimeoutSeconds=$TimeoutSeconds }
        if ($PSBoundParameters.ContainsKey('WindowsManagementServicePath')) { $dlParams.WindowsManagementServicePath=$WindowsManagementServicePath }
        $identity = Get-WindowsDeviceLink @dlParams
        if ($identity -and $identity.LinkId) { $expectedLinkId = [string]$identity.LinkId }
    }
    catch {
        Write-Verbose 'Local DeviceLink identity could not be obtained for optional JWT LinkId correlation.'
    }

    try {
        $parsed = ConvertFrom-WindowsDeviceLinkAssociationJwtBytes -Bytes $raw.Bytes -ExpectedLinkId $expectedLinkId
    }
    finally {
        if ($raw -and $raw.Bytes) { [Array]::Clear($raw.Bytes,0,$raw.Bytes.Length) }
        $raw = $null
    }

    [pscustomobject]@{
        PSTypeName='Windows.DeviceLink.AssociationJwtValidation'
        State=$parsed.State
        Present=$true
        Size=[int]$jwtState.Size
        Encoding=$parsed.Encoding
        Algorithm=$parsed.Algorithm
        IssuedAtUtc=$parsed.IssuedAtUtc
        NotBeforeUtc=$parsed.NotBeforeUtc
        ExpiresUtc=$parsed.ExpiresUtc
        IdentityClaimPresent=$parsed.IdentityClaimPresent
        IdentityMatch=$parsed.IdentityMatch
        SignatureValidation=$parsed.SignatureValidation
        Reason=$parsed.Reason
    }
}
