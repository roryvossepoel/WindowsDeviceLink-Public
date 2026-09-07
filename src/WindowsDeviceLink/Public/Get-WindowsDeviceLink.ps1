function Get-WindowsDeviceLink {
    [CmdletBinding()]
    param(
        [ValidateNotNullOrEmpty()]
        [string]$WindowsManagementServicePath,

        [ValidateRange(5, 600)]
        [int]$TimeoutSeconds = 120,

        [ValidateNotNullOrEmpty()]
        [string]$OutputDirectory,

        [switch]$Online,

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

    $onlineParameters = @(
        'Method','TenantId','ClientId','AccessToken','Certificate','CertificateThumbprint',
        'CertificateSubjectName','SendCertificateChain','ClientSecret','WebhookUri','WebhookApiKey',
        'Environment','ClientTimeout'
    )

    if (-not $Online) {
        $usedOnlineOnly = $onlineParameters | Where-Object {
            $PSBoundParameters.ContainsKey($_) -and $_ -notin @('Environment','ClientTimeout','SendCertificateChain')
        }
        if ($usedOnlineOnly) {
            throw "Online parameters require -Online. Parameters supplied: $($usedOnlineOnly -join ', ')."
        }
    }
    elseif (-not $PSBoundParameters.ContainsKey('Method')) {
        throw "-Method is required with -Online. Supported methods: DeviceCode, Interactive, ClientSecret, AccessToken, Certificate, CertificateThumbprint, CertificateSubjectName, EnvironmentVariable, ManagedIdentity, Webhook."
    }

    if ($Online) {
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
            'Webhook' {
                if (-not $WebhookUri) { throw '-WebhookUri is required for -Method Webhook.' }
                if (-not $PSBoundParameters.ContainsKey('WebhookApiKey')) {
                    Write-Warning 'No -WebhookApiKey was supplied. A webhook API key is strongly recommended unless equivalent protection is implemented at the webhook endpoint.'
                }
            }
        }
    }

    if ($PSBoundParameters.ContainsKey('WindowsManagementServicePath')) {
        $support = Test-WindowsDeviceLinkSupport -WindowsManagementServicePath $WindowsManagementServicePath
    }
    else {
        $support = Test-WindowsDeviceLinkSupport
    }

    if (-not $support.Supported) {
        throw "DeviceLink isn't supported: $($support.Reason)"
    }

    if ($support.ActivationMode -eq 'RegisteredWinRT') {
        $payload = [WinPEDeviceLink.Native.DeviceLinkClient]::GetDeviceLinkRegistered($TimeoutSeconds)
    }
    else {
        $payload = [WinPEDeviceLink.Native.DeviceLinkClient]::GetDeviceLink($support.DllPath, $TimeoutSeconds)
    }

    $decoded = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($payload)) | ConvertFrom-Json

    $deviceLink = [pscustomobject]@{
        PSTypeName      = 'Windows.DeviceLink.Information'
        Environment     = $support.Environment
        SerialNumber    = $decoded.DeviceInfo.SerialNumber
        Manufacturer    = $decoded.DeviceInfo.Manufacturer
        Model           = $decoded.DeviceInfo.ModelName
        SmbiosUuid      = $decoded.DeviceInfo.SmbiosUuid
        LinkId          = $decoded.DeviceInfo.LinkId
        CreationTimeUtc = $decoded.DeviceLinkCreationTimeUtc
        DeviceLink      = $payload
        DllSource       = $support.DllSource
        ActivationMode  = $support.ActivationMode
        DllPath         = $support.DllPath
        DllVersion      = $support.DllVersion
    }

    $exportedFile = $null
    if ($PSBoundParameters.ContainsKey('OutputDirectory')) {
        $exportedFile = $deviceLink | Export-WindowsDeviceLinkCsv -DestinationPath $OutputDirectory
        Write-Information -InformationAction Continue -MessageData "DeviceLink CSV exported successfully: $($exportedFile.FullName)"
    }

    if (-not $Online) {
        if ($exportedFile) { return $exportedFile }
        return $deviceLink
    }

    if ($Method -eq 'Webhook') {
        $webhookParameters = @{
            InputObject = $deviceLink
            WebhookUri  = $WebhookUri
        }
        if ($PSBoundParameters.ContainsKey('WebhookApiKey')) { $webhookParameters.WebhookApiKey = $WebhookApiKey }
        if ($TenantId) { $webhookParameters.TenantId = $TenantId }
        return Invoke-WindowsDeviceLinkWebhook @webhookParameters
    }

    if ($Method -eq 'DeviceCode') {
        if ($Environment -ne 'Global') {
            throw 'Native device-code authentication currently supports the Global Microsoft cloud only.'
        }

        $tokenParameters = @{ TenantId = $TenantId }
        if ($ClientId) { $tokenParameters.ClientId = $ClientId }

        Write-Information -InformationAction Continue -MessageData 'Using native OAuth device-code authentication (Microsoft.Graph.Authentication is not required).'
        $token = Get-WindowsDeviceLinkDeviceCodeToken @tokenParameters
        return Invoke-WindowsDeviceLinkGraphRegistration -InputObject $deviceLink -AccessToken $token.AccessToken -TenantId $TenantId
    }

    if ($Method -eq 'ClientSecret') {
        if ($Environment -ne 'Global') {
            throw 'Native client-secret authentication currently supports the Global Microsoft cloud only.'
        }

        Write-Information -InformationAction Continue -MessageData 'Using native OAuth client-credentials authentication (Microsoft.Graph.Authentication is not required).'
        $token = Get-WindowsDeviceLinkClientSecretToken -TenantId $TenantId -ClientId $ClientId -ClientSecret $ClientSecret
        return Invoke-WindowsDeviceLinkGraphRegistration -InputObject $deviceLink -AccessToken $token.AccessToken -TenantId $TenantId
    }

    if ($Method -eq 'EnvironmentVariable') {
        if ($Environment -ne 'Global') {
            throw 'Native environment-variable authentication currently supports the Global Microsoft cloud only.'
        }

        $environmentSecret = ConvertTo-SecureString $env:AZURE_CLIENT_SECRET -AsPlainText -Force
        Write-Information -InformationAction Continue -MessageData 'Using native OAuth client-credentials authentication from environment variables (Microsoft.Graph.Authentication is not required).'
        $token = Get-WindowsDeviceLinkClientSecretToken `
            -TenantId $env:AZURE_TENANT_ID `
            -ClientId $env:AZURE_CLIENT_ID `
            -ClientSecret $environmentSecret
        return Invoke-WindowsDeviceLinkGraphRegistration `
            -InputObject $deviceLink `
            -AccessToken $token.AccessToken `
            -TenantId $env:AZURE_TENANT_ID
    }

    if ($support.Environment -eq 'WindowsPE') {
        if ($Environment -ne 'Global') {
            throw 'Native WinPE authentication currently supports the Global Microsoft cloud only.'
        }

        switch ($Method) {
            'AccessToken' {
                $credential = New-Object System.Management.Automation.PSCredential('token', $AccessToken)
                $plainToken = $credential.GetNetworkCredential().Password
                try {
                    Write-Information -InformationAction Continue -MessageData 'Using supplied access token directly for WinPE Graph registration.'
                    return Invoke-WindowsDeviceLinkGraphRegistration -InputObject $deviceLink -AccessToken $plainToken -TenantId $TenantId
                }
                finally {
                    $plainToken = $null
                    $credential = $null
                }
            }
        }
    }

    $connectParams = @{
        Environment   = $Environment
        ClientTimeout = $ClientTimeout
    }

    switch ($Method) {
        'Interactive' {
            $connectParams.TenantId = $TenantId
            if ($ClientId) { $connectParams.ClientId = $ClientId }
        }
        'AccessToken' { $connectParams.AccessToken = $AccessToken }
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
    $deviceLink | Register-WindowsDeviceLink
}
