function Invoke-WindowsDeviceLinkWebhook {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][PSTypeName('Windows.DeviceLink.Information')][psobject]$InputObject,
        [Parameter(Mandatory)][ValidateNotNull()][uri]$WebhookUri,
        [ValidateNotNullOrEmpty()][string]$WebhookApiKey,
        [ValidateNotNullOrEmpty()][string]$TenantId,
        [scriptblock]$RequestScript
    )

    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    $module = Get-Module WindowsDeviceLink | Sort-Object Version -Descending | Select-Object -First 1
    $requestId = [guid]::NewGuid().ToString()

    $payload = [ordered]@{
        schemaVersion = 1
        requestType = 'DeviceLinkPreassociation'
        requestId = $requestId
        tenantId = if ($TenantId) { $TenantId } else { $null }
        generatedAtUtc = [DateTime]::UtcNow.ToString('o')
        device = [ordered]@{
            serialNumber = $InputObject.SerialNumber
            manufacturer = $InputObject.Manufacturer
            model = $InputObject.Model
            smbiosUuid = $InputObject.SmbiosUuid
            linkId = $InputObject.LinkId
            deviceLinkCreationTimeUtc = $InputObject.PayloadCreationTimeUtc
            deviceLink = $InputObject.DeviceLink
        }
        source = [ordered]@{
            computerName = $env:COMPUTERNAME
            environment = $InputObject.Environment
            architecture = $env:PROCESSOR_ARCHITECTURE
            moduleVersion = if ($module) { [string]$module.Version } else { $null }
            powerShellVersion = [string]$PSVersionTable.PSVersion
            dllSource = $InputObject.DllSource
            dllVersion = $InputObject.DllVersion
            activationMode = $InputObject.ActivationMode
        }
    }

    $headers = @{'X-WindowsDeviceLink-Schema'='1';'X-WindowsDeviceLink-RequestId'=$requestId}
    if ($PSBoundParameters.ContainsKey('WebhookApiKey')) { $headers['X-WindowsDeviceLink-Key'] = $WebhookApiKey }
    $body = $payload | ConvertTo-Json -Depth 8 -Compress

    try {
        Write-Information -InformationAction Continue -MessageData "Sending DeviceLink payload to webhook. Request ID: $requestId"
        if ($RequestScript) {
            $response = & $RequestScript $WebhookUri $headers $body
        }
        else {
            $response = Invoke-RestMethod -Method POST -Uri $WebhookUri -Headers $headers -ContentType 'application/json' -Body $body -ErrorAction Stop
        }
    }
    catch {
        $statusCode = $null
        try { if ($_.Exception.Response -and $_.Exception.Response.StatusCode) { $statusCode = [int]$_.Exception.Response.StatusCode } } catch {}
        if ($null -eq $statusCode -and $_.Exception.Message -match '(?<!\d)(400|401|403|404|408|429|500|502|503|504)(?!\d)') { $statusCode = [int]$Matches[1] }
        $detail = Protect-WindowsDeviceLinkSensitiveText -Text ([string]$_.Exception.Message) -SensitiveValue @($WebhookApiKey,[string]$InputObject.DeviceLink)

        switch ($statusCode) {
            400 { throw "DeviceLink webhook rejected the request with HTTP 400 (Bad Request). Request ID: $requestId. $detail" }
            401 { throw "DeviceLink webhook authentication failed with HTTP 401 (Unauthorized). Request ID: $requestId. $detail" }
            403 { throw "DeviceLink webhook authorization failed with HTTP 403 (Forbidden). Request ID: $requestId. $detail" }
            404 { throw "DeviceLink webhook endpoint was not found (HTTP 404). Verify -WebhookUri. Request ID: $requestId. $detail" }
            408 { throw "DeviceLink webhook request timed out (HTTP 408). Request ID: $requestId. $detail" }
            429 { throw "DeviceLink webhook is throttling requests (HTTP 429). Request ID: $requestId. $detail" }
        }
        if ($statusCode -ge 500) { throw "DeviceLink webhook returned server error HTTP $statusCode. Request ID: $requestId. $detail" }
        if ($statusCode) { throw "DeviceLink webhook request failed with HTTP $statusCode. Request ID: $requestId. $detail" }
        throw "DeviceLink webhook could not be reached or the request failed before an HTTP response was received. Request ID: $requestId. $detail"
    }
    finally {
        $headers.Remove('X-WindowsDeviceLink-Key') | Out-Null
        $body = $null
    }

    $safeResponse = Protect-WindowsDeviceLinkObject -InputObject $response -SensitiveValue @($WebhookApiKey,[string]$InputObject.DeviceLink)

    [pscustomobject]@{
        PSTypeName='Windows.DeviceLink.WebhookResult'
        RequestId=$requestId
        TenantId=$TenantId
        SerialNumber=$InputObject.SerialNumber
        WebhookUri=[string]$WebhookUri
        Response=$safeResponse
    }
}
