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

function Get-TenantConfigurationDocument {
    $raw = Get-AutomationVariable -Name 'WindowsDeviceLinkTenantConfiguration' -ErrorAction SilentlyContinue
    if (-not $raw) { return $null }
    $raw | ConvertFrom-Json -ErrorAction Stop
}

function Get-TenantConfiguration {
    param(
        [Parameter(Mandatory)][string]$TenantId,
        [object]$ConfigurationDocument
    )

    if (-not $ConfigurationDocument) {
        return [pscustomobject]@{
            authMethod = 'ManagedIdentity'
            tenantId = $TenantId
        }
    }

    $entry = $ConfigurationDocument.PSObject.Properties |
        Where-Object { $_.Name -ieq $TenantId } |
        Select-Object -ExpandProperty Value -First 1

    if (-not $entry) {
        throw "No tenant configuration exists for tenant '$TenantId'."
    }

    $entry
}

function Get-ConfiguredTenantIds {
    param(
        [object]$ConfigurationDocument,
        [string]$FallbackTenantId
    )

    if ($ConfigurationDocument) {
        return @(
            $ConfigurationDocument.PSObject.Properties.Name |
                ForEach-Object { ([string]$_).Trim().ToLowerInvariant() } |
                Where-Object { $_ } |
                Sort-Object -Unique
        )
    }

    if ($FallbackTenantId) {
        return @($FallbackTenantId.Trim().ToLowerInvariant())
    }

    @()
}

function Connect-TargetTenant {
    param(
        [Parameter(Mandatory)][string]$TenantId,
        [Parameter(Mandatory)][psobject]$Configuration
    )

    Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null
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

function Get-ExactSerialMatches {
    param(
        [Parameter(Mandatory)][object[]]$Records,
        [Parameter(Mandatory)][string]$SerialNumber
    )

    @(
        $Records | Where-Object {
            -not [string]::IsNullOrWhiteSpace([string]$_.serialNumber) -and
            ([string]$_.serialNumber).Trim() -ieq $SerialNumber.Trim()
        }
    )
}

function Get-TenantAssociation {
    param(
        [Parameter(Mandatory)][string]$TenantId,
        [Parameter(Mandatory)][string]$SerialNumber,
        [Parameter(Mandatory)][object]$ConfigurationDocument
    )

    $configuration = Get-TenantConfiguration -TenantId $TenantId -ConfigurationDocument $ConfigurationDocument
    Connect-TargetTenant -TenantId $TenantId -Configuration $configuration

    $escapedSerial = $SerialNumber.Replace("'","''")
    $filter = [uri]::EscapeDataString("serialNumber eq '$escapedSerial'")
    $uri = "https://graph.microsoft.com/beta/deviceManagement/tenantAssociatedDevices?%24filter=$filter"

    $response = Invoke-MgGraphRequest -Method GET -Uri $uri -OutputType PSObject -ErrorAction Stop
    $matches = @(Get-ExactSerialMatches -Records @($response.value) -SerialNumber $SerialNumber)
    $lookupMode = 'ServerFilter'

    if ($matches.Count -eq 0) {
        $all = Invoke-MgGraphRequest -Method GET -Uri 'https://graph.microsoft.com/beta/deviceManagement/tenantAssociatedDevices' -OutputType PSObject -ErrorAction Stop
        $records = New-Object System.Collections.Generic.List[object]
        foreach ($item in @($all.value)) { $records.Add($item) }

        $next = [string]$all.'@odata.nextLink'
        $page = 1
        while ($next) {
            $page++
            if ($page -gt 100) { throw 'Graph collection paging exceeded the safety limit of 100 pages.' }
            $nextPage = Invoke-MgGraphRequest -Method GET -Uri $next -OutputType PSObject -ErrorAction Stop
            foreach ($item in @($nextPage.value)) { $records.Add($item) }
            $next = [string]$nextPage.'@odata.nextLink'
        }

        $matches = @(Get-ExactSerialMatches -Records @($records) -SerialNumber $SerialNumber)
        $lookupMode = 'ClientFallback'
    }

    [pscustomobject]@{
        TenantId = $TenantId
        LookupMode = $lookupMode
        Matches = $matches
    }
}

function New-TenantAssociation {
    param(
        [Parameter(Mandatory)][string]$TenantId,
        [Parameter(Mandatory)][string]$DeviceLink,
        [Parameter(Mandatory)][object]$ConfigurationDocument
    )

    $configuration = Get-TenantConfiguration -TenantId $TenantId -ConfigurationDocument $ConfigurationDocument
    Connect-TargetTenant -TenantId $TenantId -Configuration $configuration

    $uri = 'https://graph.microsoft.com/beta/deviceManagement/tenantAssociatedDevices/importTenantAssociatedDevice'
    $body = @{ deviceLink = $DeviceLink } | ConvertTo-Json -Compress
    try {
        # Intentionally one POST only; do not blindly retry mutations after ambiguous transport failures.
        Invoke-MgGraphRequest -Method POST -Uri $uri -Body $body -ContentType 'application/json' -OutputType PSObject -ErrorAction Stop
    }
    finally {
        $body = $null
    }
}

function Remove-TenantAssociation {
    param(
        [Parameter(Mandatory)][string]$TenantId,
        [Parameter(Mandatory)][string]$AssociationId,
        [Parameter(Mandatory)][object]$ConfigurationDocument
    )

    $configuration = Get-TenantConfiguration -TenantId $TenantId -ConfigurationDocument $ConfigurationDocument
    Connect-TargetTenant -TenantId $TenantId -Configuration $configuration

    $uri = "https://graph.microsoft.com/beta/deviceManagement/tenantAssociatedDevices/$AssociationId"
    # Intentionally one DELETE only; do not blindly retry mutations after ambiguous transport failures.
    Invoke-MgGraphRequest -Method DELETE -Uri $uri -ErrorAction Stop | Out-Null
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

$request = $WebhookData.RequestBody | ConvertFrom-Json -ErrorAction Stop
if ([int]$request.schemaVersion -ne 1) {
    throw "Unsupported schemaVersion '$($request.schemaVersion)'."
}
if ([string]::IsNullOrWhiteSpace([string]$request.requestId)) {
    throw 'requestId is required.'
}
if (-not $request.device -or [string]::IsNullOrWhiteSpace([string]$request.device.deviceLink)) {
    throw 'Request does not contain device.deviceLink.'
}

$configurationDocument = Get-TenantConfigurationDocument

switch ([string]$request.requestType) {
    'DeviceLinkPreassociation' {
        $tenantId = [string]$request.tenantId
        if (-not $tenantId) {
            $tenantId = Get-AutomationVariable -Name 'WindowsDeviceLinkDefaultTenantId' -ErrorAction SilentlyContinue
        }
        if (-not $tenantId) {
            throw 'No tenantId was supplied and WindowsDeviceLinkDefaultTenantId is not configured.'
        }
        $tenantId = $tenantId.Trim().ToLowerInvariant()

        try {
            $response = New-TenantAssociation -TenantId $tenantId -DeviceLink ([string]$request.device.deviceLink) -ConfigurationDocument $configurationDocument
        }
        catch {
            $statusCode = $null
            try {
                if ($_.Exception.Response -and $_.Exception.Response.StatusCode) {
                    $statusCode = [int]$_.Exception.Response.StatusCode
                }
            } catch {}

            if ($statusCode -eq 409 -or $_.Exception.Message -match '409\s+Conflict') {
                throw "A DeviceLink pre-association already exists or conflicts with serial '$($request.device.serialNumber)' in tenant '$tenantId'."
            }
            throw
        }

        [ordered]@{
            success = $true
            requestId = [string]$request.requestId
            decision = 'New'
            changed = $true
            tenantId = $tenantId
            associationId = $response.id
            associationState = $response.associationState
            serialNumber = $response.serialNumber
            manufacturer = $response.manufacturerName
            model = $response.modelName
            preassociationDateTime = $response.preassociationDateTime
        } | ConvertTo-Json -Depth 6 -Compress
    }

    'DeviceLinkReconcile' {
        $targetTenantId = ([string]$request.targetTenantId).Trim().ToLowerInvariant()
        $sourceTenantId = ([string]$request.sourceTenantId).Trim().ToLowerInvariant()
        $serialNumber = ([string]$request.device.serialNumber).Trim()

        if (-not $targetTenantId) { throw 'targetTenantId is required for DeviceLinkReconcile.' }
        if (-not $serialNumber) { throw 'device.serialNumber is required for DeviceLinkReconcile.' }

        $fallbackTenant = Get-AutomationVariable -Name 'WindowsDeviceLinkDefaultTenantId' -ErrorAction SilentlyContinue
        $tenantIds = @(Get-ConfiguredTenantIds -ConfigurationDocument $configurationDocument -FallbackTenantId $fallbackTenant)
        if ($targetTenantId -notin $tenantIds) {
            throw "Target tenant '$targetTenantId' is not configured for this Automation backend."
        }
        if ($sourceTenantId -and $sourceTenantId -notin $tenantIds) {
            throw "Source tenant '$sourceTenantId' is not configured for this Automation backend."
        }

        $detected = New-Object System.Collections.Generic.List[object]
        foreach ($tenantId in $tenantIds) {
            try {
                $lookup = Get-TenantAssociation -TenantId $tenantId -SerialNumber $serialNumber -ConfigurationDocument $configurationDocument
            }
            catch {
                throw "Reconcile lookup failed for configured tenant '$tenantId'. No state-changing action was performed. $($_.Exception.Message)"
            }

            foreach ($match in @($lookup.Matches)) {
                $detected.Add([pscustomobject]@{
                    TenantId = $tenantId
                    AssociationId = [string]$match.id
                    AssociationState = [string]$match.associationState
                })
            }
        }

        if ($detected.Count -gt 1) {
            throw 'AmbiguousState: the serial number exists in more than one configured tenant. No state-changing action was performed.'
        }

        $current = if ($detected.Count -eq 1) { $detected[0] } else { $null }
        $decision = $null

        if (-not $current) {
            if ($sourceTenantId) {
                throw 'SourceStateMismatch: a source tenant was supplied, but the device is not present in any configured tenant.'
            }
            $decision = 'New'
        }
        elseif ($current.TenantId -eq $targetTenantId) {
            if ($sourceTenantId -and $sourceTenantId -ne $targetTenantId) {
                throw 'SourceStateMismatch: the supplied source tenant does not match the freshly detected tenant state.'
            }
            $decision = 'Update'
        }
        else {
            if (-not $sourceTenantId) {
                throw 'SourceTenantRequired: the device exists in another tenant. sourceTenantId is required before Move.'
            }
            if ($sourceTenantId -ne $current.TenantId) {
                throw 'SourceStateMismatch: the supplied source tenant does not match the freshly detected tenant state.'
            }
            $decision = 'Move'
        }

        if ($decision -eq 'Update') {
            [ordered]@{
                success = $true
                requestId = [string]$request.requestId
                decision = 'Update'
                changed = $false
                sourceTenantId = $current.TenantId
                targetTenantId = $targetTenantId
                associationId = $current.AssociationId
                associationState = $current.AssociationState
                serialNumber = $serialNumber
            } | ConvertTo-Json -Depth 6 -Compress
            break
        }

        if ($decision -eq 'New') {
            try {
                $null = New-TenantAssociation -TenantId $targetTenantId -DeviceLink ([string]$request.device.deviceLink) -ConfigurationDocument $configurationDocument
            }
            catch {
                throw "TargetCreateUncertain: target creation failed or its commit state is uncertain. Re-run lookup before retrying. $($_.Exception.Message)"
            }

            $verify = Get-TenantAssociation -TenantId $targetTenantId -SerialNumber $serialNumber -ConfigurationDocument $configurationDocument
            $matches = @($verify.Matches)
            if ($matches.Count -ne 1) {
                throw 'TargetVerificationFailed: target association could not be verified after creation.'
            }

            [ordered]@{
                success = $true
                requestId = [string]$request.requestId
                decision = 'New'
                changed = $true
                targetTenantId = $targetTenantId
                associationId = [string]$matches[0].id
                associationState = [string]$matches[0].associationState
                serialNumber = $serialNumber
            } | ConvertTo-Json -Depth 6 -Compress
            break
        }

        # Move: re-read exact source immediately before DELETE.
        $sourceLookup = Get-TenantAssociation -TenantId $sourceTenantId -SerialNumber $serialNumber -ConfigurationDocument $configurationDocument
        $sourceMatches = @($sourceLookup.Matches)
        if ($sourceMatches.Count -ne 1 -or [string]$sourceMatches[0].id -ne $current.AssociationId) {
            throw 'SourceStateChanged: source association changed between decision and mutation. No deletion was performed.'
        }

        try {
            Remove-TenantAssociation -TenantId $sourceTenantId -AssociationId $current.AssociationId -ConfigurationDocument $configurationDocument
        }
        catch {
            $verifySourceAfterError = Get-TenantAssociation -TenantId $sourceTenantId -SerialNumber $serialNumber -ConfigurationDocument $configurationDocument
            if (@($verifySourceAfterError.Matches).Count -ne 0) {
                throw 'SourceRemovalUncertain: source removal failed or remains uncertain. No target registration was attempted.'
            }
        }

        $verifySource = Get-TenantAssociation -TenantId $sourceTenantId -SerialNumber $serialNumber -ConfigurationDocument $configurationDocument
        if (@($verifySource.Matches).Count -ne 0) {
            throw 'SourceVerificationFailed: source association is still present. No target registration was attempted.'
        }

        $targetBeforeCreate = Get-TenantAssociation -TenantId $targetTenantId -SerialNumber $serialNumber -ConfigurationDocument $configurationDocument
        if (@($targetBeforeCreate.Matches).Count -gt 0) {
            throw 'TargetStateChanged: target tenant now contains an association. Source was removed; verify final state before another mutation.'
        }

        try {
            $null = New-TenantAssociation -TenantId $targetTenantId -DeviceLink ([string]$request.device.deviceLink) -ConfigurationDocument $configurationDocument
        }
        catch {
            throw 'MoveIncomplete: source association was removed, but target creation failed or is uncertain. Re-run lookup before retrying.'
        }

        $verifyTarget = Get-TenantAssociation -TenantId $targetTenantId -SerialNumber $serialNumber -ConfigurationDocument $configurationDocument
        $targetMatches = @($verifyTarget.Matches)
        if ($targetMatches.Count -ne 1) {
            throw 'MoveIncomplete: source association was removed, but target association could not be verified. Re-run lookup before retrying.'
        }

        [ordered]@{
            success = $true
            requestId = [string]$request.requestId
            decision = 'Move'
            changed = $true
            sourceTenantId = $sourceTenantId
            targetTenantId = $targetTenantId
            sourceAssociationId = $current.AssociationId
            targetAssociationId = [string]$targetMatches[0].id
            associationState = [string]$targetMatches[0].associationState
            serialNumber = $serialNumber
        } | ConvertTo-Json -Depth 6 -Compress
    }

    default {
        throw "Unsupported requestType '$($request.requestType)'. Supported values: DeviceLinkPreassociation, DeviceLinkReconcile."
    }
}
