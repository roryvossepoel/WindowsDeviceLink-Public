function Get-WindowsDeviceLinkExactSerialMatches {
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

function Get-WindowsDeviceLinkTenantAssociation {
    param(
        [Parameter(Mandatory)][string]$TenantId,
        [Parameter(Mandatory)][string]$SerialNumber,
        [Parameter(Mandatory)][string]$ClientId
    )

    $token = $null
    try {
        $token = Get-WindowsDeviceLinkBackendGraphToken -TenantId $TenantId -ClientId $ClientId
        if ([string]::IsNullOrWhiteSpace($token)) {
            throw 'Microsoft identity platform returned no access token.'
        }

        $escapedSerial = $SerialNumber.Replace("'","''")
        $filter = [uri]::EscapeDataString("serialNumber eq '$escapedSerial'")
        $filteredUri = "https://graph.microsoft.com/beta/deviceManagement/tenantAssociatedDevices?%24filter=$filter"

        $filtered = @(Invoke-WindowsDeviceLinkGraphCollection -Uri $filteredUri -AccessToken $token)
        $matches = @(Get-WindowsDeviceLinkExactSerialMatches -Records $filtered -SerialNumber $SerialNumber)
        $lookupMode = 'ServerFilter'

        if ($matches.Count -eq 0) {
            $allUri = 'https://graph.microsoft.com/beta/deviceManagement/tenantAssociatedDevices'
            $all = @(Invoke-WindowsDeviceLinkGraphCollection -Uri $allUri -AccessToken $token)
            $matches = @(Get-WindowsDeviceLinkExactSerialMatches -Records $all -SerialNumber $SerialNumber)
            $lookupMode = 'ClientFallback'
        }

        [pscustomobject]@{
            TenantId = $TenantId
            LookupMode = $lookupMode
            Matches = $matches
            AccessToken = $token
        }
    }
    catch {
        $token = $null
        throw
    }
}

function Remove-WindowsDeviceLinkBackendAssociation {
    param(
        [Parameter(Mandatory)][string]$AssociationId,
        [Parameter(Mandatory)][string]$AccessToken
    )

    $uri = "https://graph.microsoft.com/beta/deviceManagement/tenantAssociatedDevices/$AssociationId"
    $headers = @{ Authorization = "Bearer $AccessToken" }

    # Intentionally one DELETE only. Do not retry a mutation after an ambiguous transport failure.
    Invoke-RestMethod -Method DELETE -Uri $uri -Headers $headers -ErrorAction Stop | Out-Null
}

function New-WindowsDeviceLinkBackendAssociation {
    param(
        [Parameter(Mandatory)][string]$DeviceLink,
        [Parameter(Mandatory)][string]$AccessToken
    )

    $uri = 'https://graph.microsoft.com/beta/deviceManagement/tenantAssociatedDevices/importTenantAssociatedDevice'
    $headers = @{ Authorization = "Bearer $AccessToken" }
    $body = @{ deviceLink = $DeviceLink } | ConvertTo-Json -Compress

    try {
        # Intentionally one POST only. Do not retry a mutation after an ambiguous transport failure.
        Invoke-RestMethod -Method POST -Uri $uri -Headers $headers -ContentType 'application/json' -Body $body -ErrorAction Stop
    }
    finally {
        $body = $null
    }
}
