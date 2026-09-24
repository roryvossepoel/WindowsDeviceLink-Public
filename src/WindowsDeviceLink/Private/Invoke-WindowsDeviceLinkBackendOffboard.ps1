function Invoke-WindowsDeviceLinkBackendOffboard {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateNotNull()][uri]$BackendUri,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$BackendApiKey,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$SerialNumber,
        [AllowNull()][AllowEmptyString()][string]$SourceTenantId,
        [scriptblock]$RequestScript
    )

    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    $endpoint = Resolve-WindowsDeviceLinkBackendEndpoint -BackendUri $BackendUri -Route offboard
    $requestId = [guid]::NewGuid().ToString()
    $headers = @{
        'X-WindowsDeviceLink-Key' = $BackendApiKey
        'X-WindowsDeviceLink-Schema' = '1'
        'X-WindowsDeviceLink-RequestId' = $requestId
    }
    $payload = [ordered]@{
        schemaVersion = 1
        requestType = 'DeviceLinkOffboard'
        requestId = $requestId
        sourceTenantId = if ($SourceTenantId) { $SourceTenantId } else { $null }
        serialNumber = $SerialNumber
    }
    $body = $payload | ConvertTo-Json -Depth 4 -Compress
    try {
        $response = if ($RequestScript) { & $RequestScript $endpoint $headers $body } else {
            Invoke-RestMethod -Method Post -Uri $endpoint -Headers $headers -ContentType 'application/json' -Body $body -ErrorAction Stop
        }
        if (-not $response -or $response.success -ne $true) { throw 'The Function offboarding operation did not return success.' }
        Protect-WindowsDeviceLinkObject -InputObject $response -SensitiveValue @($BackendApiKey)
    }
    catch {
        $detail = Protect-WindowsDeviceLinkSensitiveText -Text ([string]$_.Exception.Message) -SensitiveValue @($BackendApiKey)
        throw "WindowsDeviceLink Function offboarding failed. Request ID: $requestId. $detail"
    }
    finally {
        $headers.Remove('X-WindowsDeviceLink-Key') | Out-Null
        $body = $null
    }
}
