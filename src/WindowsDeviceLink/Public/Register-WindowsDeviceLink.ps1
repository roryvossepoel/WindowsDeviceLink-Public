function Register-WindowsDeviceLink {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [PSTypeName('Windows.DeviceLink.Information')]
        [psobject]$InputObject,

        [ValidateSet(
            'DeviceCode',
            'Interactive',
            'ClientSecret',
            'AccessToken',
            'Certificate',
            'CertificateThumbprint',
            'CertificateSubjectName',
            'EnvironmentVariable',
            'ManagedIdentity',
            'Webhook'
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

        [uri]$WebhookUri,

        [ValidateNotNullOrEmpty()]
        [string]$WebhookApiKey,

        [ValidateNotNullOrEmpty()]
        [string]$Environment = 'Global',

        [ValidateRange(1, 600)]
        [double]$ClientTimeout = 100
    )

    process {
        if ($Method) {
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
                Webhook = @('WebhookUri','WebhookApiKey','TenantId')
            }

            $methodSpecificParameters = @(
                'TenantId','ClientId','AccessToken','Certificate','CertificateThumbprint',
                'CertificateSubjectName','SendCertificateChain','ClientSecret','WebhookUri','WebhookApiKey'
            )
            $invalidParameters = $methodSpecificParameters | Where-Object {
                $PSBoundParameters.ContainsKey($_) -and $_ -notin $allowedByMethod[$Method]
            }
            if ($invalidParameters) {
                throw "The following parameters are not valid with -Method $Method`: $($invalidParameters -join ', ')."
            }

            switch ($Method) {
                'ClientSecret' {
                    if (-not $TenantId -or -not $ClientId -or -not $PSBoundParameters.ContainsKey('ClientSecret')) {
                        throw '-TenantId, -ClientId, and -ClientSecret are required for -Method ClientSecret.'
                    }
                }
                'AccessToken' {
                    if (-not $PSBoundParameters.ContainsKey('AccessToken')) { throw '-AccessToken is required for -Method AccessToken.' }
                }
                'Certificate' {
                    if (-not $TenantId -or -not $ClientId -or -not $Certificate) { throw '-TenantId, -ClientId, and -Certificate are required for -Method Certificate.' }
                }
                'CertificateThumbprint' {
                    if (-not $TenantId -or -not $ClientId -or -not $CertificateThumbprint) { throw '-TenantId, -ClientId, and -CertificateThumbprint are required for -Method CertificateThumbprint.' }
                }
                'CertificateSubjectName' {
                    if (-not $TenantId -or -not $ClientId -or -not $CertificateSubjectName) { throw '-TenantId, -ClientId, and -CertificateSubjectName are required for -Method CertificateSubjectName.' }
                }
                'EnvironmentVariable' {
                    $missingVariables = @('AZURE_TENANT_ID','AZURE_CLIENT_ID','AZURE_CLIENT_SECRET') | Where-Object { -not [Environment]::GetEnvironmentVariable($_) }
                    if ($missingVariables) { throw "-Method EnvironmentVariable requires environment variables: $($missingVariables -join ', ')." }
                }
                'Webhook' {
                    if (-not $WebhookUri) { throw '-WebhookUri is required for -Method Webhook.' }
                    if (-not $PSBoundParameters.ContainsKey('WebhookApiKey')) {
                        Write-Warning 'No -WebhookApiKey was supplied. A webhook API key is strongly recommended unless equivalent protection is implemented at the webhook endpoint.'
                    }
                }
            }
        }

        if ($Method -eq 'Webhook') {
            $webhookParameters = @{ InputObject = $InputObject; WebhookUri = $WebhookUri }
            if ($PSBoundParameters.ContainsKey('WebhookApiKey')) { $webhookParameters.WebhookApiKey = $WebhookApiKey }
            if ($TenantId) { $webhookParameters.TenantId = $TenantId }
            return Invoke-WindowsDeviceLinkWebhook @webhookParameters
        }

        if ($Method -in @('DeviceCode','ClientSecret','EnvironmentVariable','AccessToken')) {
            if ($Environment -ne 'Global') {
                throw 'Native registration currently supports the Global Microsoft cloud only.'
            }

            $plainToken = $null
            try {
                switch ($Method) {
                    'DeviceCode' {
                        $tokenParameters = @{}
                        if ($TenantId) { $tokenParameters.TenantId = $TenantId }
                        if ($ClientId) { $tokenParameters.ClientId = $ClientId }
                        Write-Information -InformationAction Continue -MessageData 'Using native OAuth device-code authentication for Device Association registration.'
                        $token = Get-WindowsDeviceLinkDeviceCodeToken @tokenParameters
                        $plainToken = $token.AccessToken
                        $TenantId = $token.TenantId
                    }
                    'ClientSecret' {
                        Write-Information -InformationAction Continue -MessageData 'Using native OAuth client-credentials authentication for Device Association registration.'
                        $token = Get-WindowsDeviceLinkClientSecretToken -TenantId $TenantId -ClientId $ClientId -ClientSecret $ClientSecret
                        $plainToken = $token.AccessToken
                    }
                    'EnvironmentVariable' {
                        $environmentSecret = ConvertTo-SecureString $env:AZURE_CLIENT_SECRET -AsPlainText -Force
                        Write-Information -InformationAction Continue -MessageData 'Using native OAuth client-credentials authentication from environment variables for Device Association registration.'
                        $token = Get-WindowsDeviceLinkClientSecretToken -TenantId $env:AZURE_TENANT_ID -ClientId $env:AZURE_CLIENT_ID -ClientSecret $environmentSecret
                        $plainToken = $token.AccessToken
                        $TenantId = $env:AZURE_TENANT_ID
                    }
                    'AccessToken' {
                        $credential = New-Object System.Management.Automation.PSCredential('token', $AccessToken)
                        $plainToken = $credential.GetNetworkCredential().Password
                        if (-not $TenantId) { $TenantId = Resolve-WindowsDeviceLinkAccessTokenTenantId -AccessToken $plainToken }
                        $credential = $null
                    }
                }

                if ($PSCmdlet.ShouldProcess($InputObject.SerialNumber, "Create the Intune DeviceLink pre-association in tenant $TenantId")) {
                    return Invoke-WindowsDeviceLinkGraphRegistration -InputObject $InputObject -AccessToken $plainToken -TenantId $TenantId
                }
                return
            }
            finally {
                $plainToken = $null
            }
        }

        if ($Method) {
            $connectParams = @{ Environment = $Environment; ClientTimeout = $ClientTimeout }
            switch ($Method) {
                'Interactive' {
                    if ($TenantId) { $connectParams.TenantId = $TenantId }
                    if ($ClientId) { $connectParams.ClientId = $ClientId }
                }
                'Certificate' {
                    $connectParams.TenantId = $TenantId; $connectParams.ClientId = $ClientId
                    $connectParams.Certificate = $Certificate; $connectParams.SendCertificateChain = $SendCertificateChain
                }
                'CertificateThumbprint' {
                    $connectParams.TenantId = $TenantId; $connectParams.ClientId = $ClientId
                    $connectParams.CertificateThumbprint = $CertificateThumbprint; $connectParams.SendCertificateChain = $SendCertificateChain
                }
                'CertificateSubjectName' {
                    $connectParams.TenantId = $TenantId; $connectParams.ClientId = $ClientId
                    $connectParams.CertificateSubjectName = $CertificateSubjectName; $connectParams.SendCertificateChain = $SendCertificateChain
                }
                'ManagedIdentity' {
                    $connectParams.Identity = $true
                    if ($ClientId) { $connectParams.ClientId = $ClientId }
                }
            }
            Connect-WindowsDeviceLink @connectParams | Out-Null
        }

        if (-not (Get-Command Invoke-MgGraphRequest -ErrorAction SilentlyContinue)) {
            throw 'Microsoft.Graph.Authentication is required for this registration mode. Use -Method DeviceCode, ClientSecret, EnvironmentVariable or AccessToken for native authentication, or run Connect-WindowsDeviceLink first.'
        }

        $context = Get-MgContext
        if (-not $context) {
            throw 'No Microsoft Graph session exists. Supply -Method or run Connect-WindowsDeviceLink first.'
        }

        $uri = 'https://graph.microsoft.com/beta/deviceManagement/tenantAssociatedDevices/importTenantAssociatedDevice'
        $body = @{ deviceLink = $InputObject.DeviceLink } | ConvertTo-Json -Compress

        if ($PSCmdlet.ShouldProcess($InputObject.SerialNumber, "Create the Intune DeviceLink pre-association in tenant $($context.TenantId)")) {
            try {
                $response = Invoke-MgGraphRequest -Method POST -Uri $uri -Body $body -ContentType 'application/json' -OutputType PSObject -ErrorAction Stop
            }
            catch {
                $statusCode = $null
                try {
                    if ($_.Exception.Response -and $_.Exception.Response.StatusCode) { $statusCode = [int]$_.Exception.Response.StatusCode }
                }
                catch { $statusCode = $null }

                if ($statusCode -eq 409 -or $_.Exception.Message -match '409\s+Conflict') {
                    throw "A DeviceLink pre-association already exists or conflicts with this device (HTTP 409). Serial number: $($InputObject.SerialNumber). Remove the existing association in Intune before registering the device again."
                }
                throw
            }

            $result = ConvertTo-WindowsDeviceLinkAssociationResult `
                -Record $response `
                -TenantId $context.TenantId `
                -ResultType Registration `
                -ExpectedSerialNumber ([string]$InputObject.SerialNumber)

            Write-Information -InformationAction Continue -MessageData ("DeviceLink registration succeeded. Serial number: {0}; Association state: {1}; Association ID: {2}" -f $result.SerialNumber, $result.AssociationState, $result.Id)
            $result
        }
    }
}
