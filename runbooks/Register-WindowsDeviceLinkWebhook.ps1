param(
    [Parameter(Mandatory = $false)]
    [object]$WebhookData
)

$ErrorActionPreference = 'Stop'

function Get-RequestHeaderValue {
    param(
        [Parameter(Mandatory)][object]$Headers,
        [Parameter(Mandatory)][string]$Name
    )

    if (-not $Headers) { return $null }

    foreach ($property in $Headers.PSObject.Properties) {
        if ($property.Name -ieq $Name) {
            return [string]$property.Value
        }
    }

    if ($Headers -is [System.Collections.IDictionary]) {
        foreach ($key in $Headers.Keys) {
            if ([string]$key -ieq $Name) {
                return [string]$Headers[$key]
            }
        }
    }

    return $null
}

function Get-TenantConfiguration {
    param([Parameter(Mandatory)][string]$TenantId)

    $raw = Get-AutomationVariable -Name 'WindowsDeviceLinkTenantConfiguration' -ErrorAction SilentlyContinue
    if (-not $raw) {
        return [pscustomobject]@{
            authMethod = 'ManagedIdentity'
            tenantId = $TenantId
        }
    }

    $configuration = $raw | ConvertFrom-Json
    $entry = $configuration.PSObject.Properties |
        Where-Object { $_.Name -eq $TenantId } |
        Select-Object -ExpandProperty Value -First 1

    if (-not $entry) {
        throw "No tenant configuration exists for tenant '$TenantId'."
    }

    $entry
}

function Connect-TargetTenant {
    param(
        [Parameter(Mandatory)][string]$TenantId,
        [Parameter(Mandatory)][psobject]$Configuration
    )

    $authMethod = if ($Configuration.authMethod) { [string]$Configuration.authMethod } else { 'ManagedIdentity' }

    switch ($authMethod) {
        'ManagedIdentity' {
            Connect-MgGraph -Identity -NoWelcome -ErrorAction Stop | Out-Null
            $context = Get-MgContext
            if (-not $context) {
                throw 'Managed Identity authentication did not produce a Microsoft Graph context.'
            }
            if ($context.TenantId -and $context.TenantId -ne $TenantId) {
                throw "Managed Identity is connected to tenant '$($context.TenantId)' but request targets '$TenantId'."
            }
        }
        'Certificate' {
            if (-not $Configuration.clientId -or -not $Configuration.certificateAssetName) {
                throw "Certificate authentication for tenant '$TenantId' requires clientId and certificateAssetName in WindowsDeviceLinkTenantConfiguration."
            }

            $certificate = Get-AutomationCertificate -Name ([string]$Configuration.certificateAssetName)
            if (-not $certificate) {
                throw "Automation certificate asset '$($Configuration.certificateAssetName)' was not found."
            }

            Connect-MgGraph `
                -TenantId $TenantId `
                -ClientId ([string]$Configuration.clientId) `
                -Certificate $certificate `
                -NoWelcome `
                -ErrorAction Stop | Out-Null
        }
        default {
            throw "Unsupported authMethod '$authMethod' for tenant '$TenantId'. Supported values: ManagedIdentity, Certificate."
        }
    }
}

if (-not $WebhookData) {
    throw 'This runbook must be started by an Azure Automation webhook.'
}

$expectedApiKey = Get-AutomationVariable -Name 'WindowsDeviceLinkWebhookApiKey' -ErrorAction SilentlyContinue
if ($expectedApiKey) {
    $providedApiKey = Get-RequestHeaderValue -Headers $WebhookData.RequestHeader -Name 'X-WindowsDeviceLink-Key'
    if (-not $providedApiKey -or $providedApiKey -cne [string]$expectedApiKey) {
        throw 'Webhook API key validation failed.'
    }
}

if (-not $WebhookData.RequestBody) {
    throw 'Webhook request body is empty.'
}

$request = $WebhookData.RequestBody | ConvertFrom-Json

if ($request.schemaVersion -ne 1) {
    throw "Unsupported schemaVersion '$($request.schemaVersion)'."
}
if ($request.requestType -ne 'DeviceLinkPreassociation') {
    throw "Unsupported requestType '$($request.requestType)'."
}
if (-not $request.device -or -not $request.device.deviceLink) {
    throw 'Request does not contain device.deviceLink.'
}

$tenantId = [string]$request.tenantId
if (-not $tenantId) {
    $tenantId = Get-AutomationVariable -Name 'WindowsDeviceLinkDefaultTenantId' -ErrorAction SilentlyContinue
}
if (-not $tenantId) {
    throw 'No tenantId was supplied and WindowsDeviceLinkDefaultTenantId is not configured.'
}

$tenantConfiguration = Get-TenantConfiguration -TenantId $tenantId
Connect-TargetTenant -TenantId $tenantId -Configuration $tenantConfiguration

$uri = 'https://graph.microsoft.com/beta/deviceManagement/tenantAssociatedDevices/importTenantAssociatedDevice'
$body = @{ deviceLink = [string]$request.device.deviceLink } | ConvertTo-Json -Compress

try {
    $response = Invoke-MgGraphRequest `
        -Method POST `
        -Uri $uri `
        -Body $body `
        -ContentType 'application/json' `
        -OutputType PSObject `
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

    if ($statusCode -eq 409 -or $_.Exception.Message -match '409\s+Conflict') {
        throw "A DeviceLink pre-association already exists or conflicts with serial '$($request.device.serialNumber)' in tenant '$tenantId'."
    }

    throw
}

$result = [ordered]@{
    success = $true
    requestId = [string]$request.requestId
    tenantId = $tenantId
    associationId = $response.id
    associationState = $response.associationState
    serialNumber = $response.serialNumber
    manufacturer = $response.manufacturerName
    model = $response.modelName
    preassociationDateTime = $response.preassociationDateTime
}

$result | ConvertTo-Json -Depth 5 -Compress
