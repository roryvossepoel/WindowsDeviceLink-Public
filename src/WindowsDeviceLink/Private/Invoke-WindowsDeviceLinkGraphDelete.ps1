function Invoke-WindowsDeviceLinkGraphDelete {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$Uri,
        [AllowNull()][string]$AccessToken,
        [switch]$SdkMode,
        [scriptblock]$RequestScript
    )

    try {
        if ($RequestScript) {
            & $RequestScript $Uri ([bool]$SdkMode) $AccessToken | Out-Null
            return
        }
        if ($SdkMode) {
            Invoke-MgGraphRequest -Method DELETE -Uri $Uri -ErrorAction Stop | Out-Null
            return
        }
        if ([string]::IsNullOrWhiteSpace($AccessToken)) {
            throw 'A native Graph DELETE requires an access token.'
        }
        Invoke-RestMethod -Method DELETE -Uri $Uri -Headers @{Authorization="Bearer $AccessToken"} -ErrorAction Stop | Out-Null
    }
    catch {
        $statusCode=$null
        try{if($_.Exception.Response -and $_.Exception.Response.StatusCode){$statusCode=[int]$_.Exception.Response.StatusCode}}catch{}
        if($null -eq $statusCode -and $_.Exception.Message -match '(?<!\d)(400|401|403|404|409|429|500|502|503|504)(?!\d)'){$statusCode=[int]$Matches[1]}
        $safeDetail=Protect-WindowsDeviceLinkSensitiveText -Text ([string]$_.Exception.Message) -SensitiveValue @($AccessToken)
        if($statusCode -eq 404){throw 'Microsoft Graph DELETE returned HTTP 404.'}
        if($statusCode){throw "Microsoft Graph DELETE failed with HTTP $statusCode. $safeDetail"}
        throw "Microsoft Graph DELETE failed before a valid response was received. $safeDetail"
    }
}
