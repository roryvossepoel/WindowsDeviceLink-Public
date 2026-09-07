function Remove-WindowsDeviceLinkAssociation {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [ValidateNotNullOrEmpty()]
        [string]$AssociationId,

        [ValidateNotNullOrEmpty()]
        [string]$SerialNumber,

        [Parameter(Mandatory)]
        [ValidateSet(
            'DeviceCode',
            'Interactive',
            'ClientSecret',
            'AccessToken',
            'Certificate',
            'CertificateThumbprint',
            'CertificateSubjectName',
            'EnvironmentVariable',
            'ManagedIdentity'
        )]
        [string]$Method,

        [ValidateNotNullOrEmpty()]
        [string]$TenantId,

        [ValidateNotNullOrEmpty()]
        [string]$ClientId,

        [securestring]$AccessToken,

        [System.Security.Cryptography.X509Certificates.X509Certificate2]$Certificate,

        [ValidateNotNullOrEmpty()]
        [string]$CertificateThumbprint,

        [ValidateNotNullOrEmpty()]
        [string]$CertificateSubjectName,

        [bool]$SendCertificateChain = $false,

        [securestring]$ClientSecret,

        [ValidateNotNullOrEmpty()]
        [string]$Environment = 'Global',

        [ValidateRange(1, 600)]
        [double]$ClientTimeout = 100
    )

    if ([string]::IsNullOrWhiteSpace($AssociationId) -eq [string]::IsNullOrWhiteSpace($SerialNumber)) {
        throw 'Specify exactly one of -AssociationId or -SerialNumber.'
    }

    $allowedByMethod = @{
        DeviceCode = @('TenantId','ClientId')
        Interactive = @('TenantId','ClientId')
        ClientSecret = @('TenantId','ClientId','ClientSecret')
        AccessToken = @('TenantId','AccessToken')
        Certificate = @('TenantId','ClientId','Certificate','SendCertificateChain')
        CertificateThumbprint = @('TenantId','ClientId','CertificateThumbprint','SendCertificateChain')
        CertificateSubjectName = @('TenantId','ClientId','CertificateSubjectName','SendCertificateChain')
        EnvironmentVariable = @()
        ManagedIdentity = @('ClientId')
    }

    $methodSpecificParameters = @(
        'TenantId','ClientId','AccessToken','Certificate','CertificateThumbprint',
        'CertificateSubjectName','SendCertificateChain','ClientSecret'
    )

    $invalidParameters = $methodSpecificParameters | Where-Object {
        $PSBoundParameters.ContainsKey($_) -and $_ -notin $allowedByMethod[$Method]
    }
    if ($invalidParameters) {
        throw "The following parameters are not valid with -Method $Method`: $($invalidParameters -join ', ')."
    }

    switch ($Method) {
        'DeviceCode' {
            if (-not $TenantId) { throw '-TenantId is required for -Method DeviceCode.' }
        }
        'Interactive' {
            if (-not $TenantId) { throw '-TenantId is required for -Method Interactive.' }
        }
        'ClientSecret' {
            if (-not $TenantId -or -not $ClientId -or -not $PSBoundParameters.ContainsKey('ClientSecret')) {
                throw '-TenantId, -ClientId, and -ClientSecret are required for -Method ClientSecret.'
            }
        }
        'AccessToken' {
            if (-not $TenantId -or -not $PSBoundParameters.ContainsKey('AccessToken')) {
                throw '-TenantId and -AccessToken are required for -Method AccessToken.'
            }
        }
        'Certificate' {
            if (-not $TenantId -or -not $ClientId -or -not $Certificate) {
                throw '-TenantId, -ClientId, and -Certificate are required for -Method Certificate.'
            }
        }
        'CertificateThumbprint' {
            if (-not $TenantId -or -not $ClientId -or -not $CertificateThumbprint) {
                throw '-TenantId, -ClientId, and -CertificateThumbprint are required for -Method CertificateThumbprint.'
            }
        }
        'CertificateSubjectName' {
            if (-not $TenantId -or -not $ClientId -or -not $CertificateSubjectName) {
                throw '-TenantId, -ClientId, and -CertificateSubjectName are required for -Method CertificateSubjectName.'
            }
        }
        'EnvironmentVariable' {
            $missingVariables = @('AZURE_TENANT_ID','AZURE_CLIENT_ID','AZURE_CLIENT_SECRET') | Where-Object {
                -not [Environment]::GetEnvironmentVariable($_)
            }
            if ($missingVariables) {
                throw "-Method EnvironmentVariable requires environment variables: $($missingVariables -join ', ')."
            }
        }
    }

    $baseUri = 'https://graph.microsoft.com/beta'
    $resolvedAssociationId = $AssociationId
    $resolvedSerialNumber = $SerialNumber
    $nativeAccessToken = $null
    $sdkMode = $false

    if ($Method -in @('DeviceCode','ClientSecret','EnvironmentVariable','AccessToken')) {
        if ($Environment -ne 'Global') {
            throw 'Native association removal currently supports the Global Microsoft cloud only.'
        }

        switch ($Method) {
            'DeviceCode' {
                $tokenParameters = @{ TenantId = $TenantId }
                if ($ClientId) { $tokenParameters.ClientId = $ClientId }
                Write-Information -InformationAction Continue -MessageData 'Using native OAuth device-code authentication for Device Association removal.'
                $token = Get-WindowsDeviceLinkDeviceCodeToken @tokenParameters
                $nativeAccessToken = $token.AccessToken
            }
            'ClientSecret' {
                Write-Information -InformationAction Continue -MessageData 'Using native OAuth client-credentials authentication for Device Association removal.'
                $token = Get-WindowsDeviceLinkClientSecretToken -TenantId $TenantId -ClientId $ClientId -ClientSecret $ClientSecret
                $nativeAccessToken = $token.AccessToken
            }
            'EnvironmentVariable' {
                $environmentSecret = ConvertTo-SecureString $env:AZURE_CLIENT_SECRET -AsPlainText -Force
                Write-Information -InformationAction Continue -MessageData 'Using native OAuth client-credentials authentication from environment variables for Device Association removal.'
                $token = Get-WindowsDeviceLinkClientSecretToken `
                    -TenantId $env:AZURE_TENANT_ID `
                    -ClientId $env:AZURE_CLIENT_ID `
                    -ClientSecret $environmentSecret
                $nativeAccessToken = $token.AccessToken
                $TenantId = $env:AZURE_TENANT_ID
            }
            'AccessToken' {
                $credential = New-Object System.Management.Automation.PSCredential('token', $AccessToken)
                $nativeAccessToken = $credential.GetNetworkCredential().Password
                $credential = $null
            }
        }
    }
    else {
        $connectParams = @{
            Environment   = $Environment
            ClientTimeout = $ClientTimeout
        }

        switch ($Method) {
            'Interactive' {
                $connectParams.TenantId = $TenantId
                if ($ClientId) { $connectParams.ClientId = $ClientId }
            }
            'Certificate' {
                $connectParams.TenantId = $TenantId
                $connectParams.ClientId = $ClientId
                $connectParams.Certificate = $Certificate
                $connectParams.SendCertificateChain = $SendCertificateChain
            }
            'CertificateThumbprint' {
                $connectParams.TenantId = $TenantId
                $connectParams.ClientId = $ClientId
                $connectParams.CertificateThumbprint = $CertificateThumbprint
                $connectParams.SendCertificateChain = $SendCertificateChain
            }
            'CertificateSubjectName' {
                $connectParams.TenantId = $TenantId
                $connectParams.ClientId = $ClientId
                $connectParams.CertificateSubjectName = $CertificateSubjectName
                $connectParams.SendCertificateChain = $SendCertificateChain
            }
            'ManagedIdentity' {
                $connectParams.Identity = $true
                if ($ClientId) { $connectParams.ClientId = $ClientId }
            }
        }

        Connect-WindowsDeviceLink @connectParams | Out-Null
        $sdkMode = $true
    }

    try {
        if (-not $resolvedAssociationId) {
            $escapedSerial = $SerialNumber.Replace("'", "''")
            $filter = [uri]::EscapeDataString("serialNumber eq '$escapedSerial'")
            $lookupUri = "$baseUri/deviceManagement/tenantAssociatedDevices?`$filter=$filter"

            if ($sdkMode) {
                $lookup = Invoke-MgGraphRequest -Method GET -Uri $lookupUri -ErrorAction Stop
            }
            else {
                $lookup = Invoke-RestMethod -Method GET -Uri $lookupUri -Headers @{ Authorization = "Bearer $nativeAccessToken" } -ErrorAction Stop
            }

            $matches = @($lookup.value)

            if ($matches.Count -eq 0) {
                Write-Information -InformationAction Continue -MessageData 'Filtered serial-number lookup returned no match; retrying with client-side matching.'

                $allRecords = @()
                $nextUri = "$baseUri/deviceManagement/tenantAssociatedDevices"
                while ($nextUri) {
                    if ($sdkMode) {
                        $page = Invoke-MgGraphRequest -Method GET -Uri $nextUri -ErrorAction Stop
                    }
                    else {
                        $page = Invoke-RestMethod -Method GET -Uri $nextUri -Headers @{ Authorization = "Bearer $nativeAccessToken" } -ErrorAction Stop
                    }

                    if ($page.value) { $allRecords += @($page.value) }
                    $nextUri = $page.'@odata.nextLink'
                }

                $matches = @($allRecords | Where-Object { [string]$_.serialNumber -eq [string]$SerialNumber })
            }

            if ($matches.Count -eq 0) {
                throw "No Device Association record was found for serial number '$SerialNumber'."
            }
            if ($matches.Count -gt 1) {
                throw "Multiple Device Association records were found for serial number '$SerialNumber'. Use -AssociationId to select the exact record."
            }

            $resolvedAssociationId = [string]$matches[0].id
            $resolvedSerialNumber = [string]$matches[0].serialNumber
        }

        $deleteUri = "$baseUri/deviceManagement/tenantAssociatedDevices/$resolvedAssociationId"
        $target = if ($resolvedSerialNumber) { "$resolvedSerialNumber ($resolvedAssociationId)" } else { $resolvedAssociationId }

        if ($PSCmdlet.ShouldProcess($target, 'Remove Device Association record')) {
            try {
                if ($sdkMode) {
                    Invoke-MgGraphRequest -Method DELETE -Uri $deleteUri -ErrorAction Stop | Out-Null
                }
                else {
                    Invoke-RestMethod -Method DELETE -Uri $deleteUri -Headers @{ Authorization = "Bearer $nativeAccessToken" } -ErrorAction Stop | Out-Null
                }
            }
            catch {
                $statusCode = $null
                try { $statusCode = [int]$_.Exception.Response.StatusCode } catch {}
                if ($statusCode -eq 404) {
                    throw "Device Association '$resolvedAssociationId' was not found or has already been removed."
                }
                throw
            }

            Write-Information -InformationAction Continue -MessageData "Device Association removed successfully. Association ID: $resolvedAssociationId"

            [pscustomobject]@{
                PSTypeName    = 'Windows.DeviceLink.AssociationRemovalResult'
                AssociationId = $resolvedAssociationId
                SerialNumber  = $resolvedSerialNumber
                TenantId      = $TenantId
                Removed       = $true
            }
        }
    }
    finally {
        $nativeAccessToken = $null
    }
}
