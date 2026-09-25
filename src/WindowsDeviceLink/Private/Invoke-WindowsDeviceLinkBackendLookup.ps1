function Invoke-WindowsDeviceLinkBackendLookup {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateNotNull()][uri]$BackendUri,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$BackendApiKey,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$SerialNumber,
        [ValidateRange(5,600)][int]$TimeoutSeconds = 120,
        [scriptblock]$RequestScript
    )

    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    $endpoint = Resolve-WindowsDeviceLinkBackendEndpoint -BackendUri $BackendUri -Route lookup
    $builder = New-Object System.UriBuilder($endpoint)
    $builder.Query = 'serialNumber=' + [uri]::EscapeDataString($SerialNumber.Trim())
    $headers = @{ 'X-WindowsDeviceLink-Key' = $BackendApiKey }

    try {
        if ($RequestScript) {
            $response = & $RequestScript $builder.Uri $headers $TimeoutSeconds
        }
        else {
            $response = Invoke-RestMethod -Method GET -Uri $builder.Uri -Headers $headers -TimeoutSec $TimeoutSeconds -ErrorAction Stop
        }

        if ($null -eq $response) {
            throw 'The Function lookup returned no response.'
        }
        if ($response.PSObject.Properties.Name -contains 'success' -and -not [bool]$response.success) {
            $errorName = if ($response.error) { [string]$response.error } else { 'BackendLookupFailed' }
            $message = if ($response.message) { [string]$response.message } else { 'The Function lookup did not succeed.' }
            throw ($errorName + ': ' + $message)
        }

        $response
    }
    catch {
        $detail = Protect-WindowsDeviceLinkSensitiveText -Text ([string]$_.Exception.Message) -SensitiveValue @($BackendApiKey)
        throw ('WindowsDeviceLink Function lookup failed. ' + $detail)
    }
    finally {
        $headers.Remove('X-WindowsDeviceLink-Key') | Out-Null
    }
}
