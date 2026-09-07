function Invoke-WindowsDeviceLinkWebhook {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [PSTypeName('Windows.DeviceLink.Information')]
        [psobject]$InputObject,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [uri]$WebhookUri,

        [ValidateNotNullOrEmpty()]
        [string]$WebhookApiKey,

        [ValidateNotNullOrEmpty()]
        [string]$TenantId
    )

    [Net.ServicePointManager]::SecurityProtocol =
        [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

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
            deviceLinkCreationTimeUtc = $InputObject.CreationTimeUtc
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

    $headers = @{
        'X-WindowsDeviceLink-Schema' = '1'
        'X-WindowsDeviceLink-RequestId' = $requestId
    }

    if ($PSBoundParameters.ContainsKey('WebhookApiKey')) {
        $headers['X-WindowsDeviceLink-Key'] = $WebhookApiKey
    }

    try {
        Write-Information -InformationAction Continue -MessageData "Sending DeviceLink payload to webhook. Request ID: $requestId"
        $response = Invoke-RestMethod `
            -Method POST `
            -Uri $WebhookUri `
            -Headers $headers `
            -ContentType 'application/json' `
            -Body ($payload | ConvertTo-Json -Depth 8 -Compress) `
            -ErrorAction Stop
    }
    catch {
        $statusCode = $null
        try {
            if ($_.Exception.Response -and $_.Exception.Response.StatusCode) {
                $statusCode = [int]$_.Exception.Response.StatusCode
            }
        }
        catch {}

        if ($statusCode) {
            throw "DeviceLink webhook request failed with HTTP $statusCode. Request ID: $requestId. $($_.Exception.Message)"
        }
        throw "DeviceLink webhook request failed. Request ID: $requestId. $($_.Exception.Message)"
    }
    finally {
        $headers.Remove('X-WindowsDeviceLink-Key') | Out-Null
    }

    [pscustomobject]@{
        PSTypeName = 'Windows.DeviceLink.WebhookResult'
        RequestId = $requestId
        TenantId = $TenantId
        SerialNumber = $InputObject.SerialNumber
        WebhookUri = [string]$WebhookUri
        Response = $response
    }
}
