function Invoke-WindowsDeviceLinkBackendReconcile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateNotNull()][uri]$BackendUri,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$BackendApiKey,
        [Parameter(Mandatory)][PSTypeName('Windows.DeviceLink.Information')][psobject]$InputObject,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$TargetTenantId,
        [AllowNull()][AllowEmptyString()][string]$SourceTenantId,
        [switch]$RepairExistingAssociation,
        [scriptblock]$RequestScript
    )

    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    $endpoint = Resolve-WindowsDeviceLinkBackendEndpoint -BackendUri $BackendUri -Route reconcile
    $requestId = [guid]::NewGuid().ToString()
    $headers = @{
        'X-WindowsDeviceLink-Key' = $BackendApiKey
        'X-WindowsDeviceLink-Schema' = '1'
        'X-WindowsDeviceLink-RequestId' = $requestId
    }
    $payload = [ordered]@{
        schemaVersion = 1
        requestType = 'DeviceLinkReconcile'
        requestId = $requestId
        sourceTenantId = if ($SourceTenantId) { $SourceTenantId } else { $null }
        targetTenantId = $TargetTenantId
        repairExistingAssociation = [bool]$RepairExistingAssociation
        device = [ordered]@{ serialNumber=[string]$InputObject.SerialNumber; deviceLink=[string]$InputObject.DeviceLink }
    }
    $body = $payload | ConvertTo-Json -Depth 5 -Compress
    try {
        $response = if ($RequestScript) { & $RequestScript $endpoint $headers $body } else {
            Invoke-RestMethod -Method Post -Uri $endpoint -Headers $headers -ContentType 'application/json' -Body $body -ErrorAction Stop
        }
        if (-not $response -or $response.success -ne $true) { throw 'The Function reconcile operation did not return success.' }
        Protect-WindowsDeviceLinkObject -InputObject $response -SensitiveValue @($BackendApiKey,[string]$InputObject.DeviceLink)
    }
    catch {
        $detail = Protect-WindowsDeviceLinkSensitiveText -Text ([string]$_.Exception.Message) -SensitiveValue @($BackendApiKey,[string]$InputObject.DeviceLink)
        throw "WindowsDeviceLink Function reconcile failed. Request ID: $requestId. $detail"
    }
    finally {
        $headers.Remove('X-WindowsDeviceLink-Key') | Out-Null
        $body = $null
    }
}
