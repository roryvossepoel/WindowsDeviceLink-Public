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

        [ValidateNotNullOrEmpty()]
        [string]$TenantId,

        [ValidateNotNullOrEmpty()]
        [string]$ClientId,

        [switch]$Interactive,

        [switch]$UseDeviceCode,

        [securestring]$AccessToken,

        [System.Security.Cryptography.X509Certificates.X509Certificate2]$Certificate,

        [ValidateNotNullOrEmpty()]
        [string]$CertificateThumbprint,

        [ValidateNotNullOrEmpty()]
        [string]$CertificateSubjectName,

        [bool]$SendCertificateChain = $false,

        [securestring]$ClientSecret,

        [switch]$Identity,

        [switch]$EnvironmentVariable,

        [ValidateNotNullOrEmpty()]
        [string]$Environment = 'Global',

        [ValidateRange(1, 600)]
        [double]$ClientTimeout = 100
    )

    if (-not $Online) {
        $onlineOnlyParameters = @(
            'TenantId','ClientId','Interactive','UseDeviceCode','AccessToken','Certificate',
            'CertificateThumbprint','CertificateSubjectName','ClientSecret','Identity','EnvironmentVariable'
        )
        $usedOnlineOnly = $onlineOnlyParameters | Where-Object { $PSBoundParameters.ContainsKey($_) }
        if ($usedOnlineOnly) {
            throw "Online authentication parameters require -Online. Parameters supplied: $($usedOnlineOnly -join ', ')."
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

    $methods = @()
    if ($Interactive) { $methods += 'Interactive' }
    if ($UseDeviceCode) { $methods += 'DeviceCode' }
    if ($PSBoundParameters.ContainsKey('AccessToken')) { $methods += 'AccessToken' }
    if ($PSBoundParameters.ContainsKey('Certificate')) { $methods += 'Certificate' }
    if ($PSBoundParameters.ContainsKey('CertificateThumbprint')) { $methods += 'CertificateThumbprint' }
    if ($PSBoundParameters.ContainsKey('CertificateSubjectName')) { $methods += 'CertificateSubjectName' }
    if ($PSBoundParameters.ContainsKey('ClientSecret')) { $methods += 'ClientSecret' }
    if ($Identity) { $methods += 'ManagedIdentity' }
    if ($EnvironmentVariable) { $methods += 'EnvironmentVariable' }

    if ($methods.Count -eq 0) {
        throw 'When using -Online, specify an authentication method: -Interactive, -UseDeviceCode, -AccessToken, -Certificate, -CertificateThumbprint, -CertificateSubjectName, -ClientSecret, -Identity, or -EnvironmentVariable.'
    }
    if ($methods.Count -gt 1) {
        throw "Specify only one authentication method with -Online. Methods supplied: $($methods -join ', ')."
    }

    if ($methods[0] -eq 'DeviceCode') {
        if (-not $TenantId) { throw '-TenantId is required for -Online -UseDeviceCode.' }
        if ($Environment -ne 'Global') {
            throw 'Native device-code authentication currently supports the Global Microsoft cloud only.'
        }

        $tokenParameters = @{ TenantId = $TenantId }
        if ($ClientId) { $tokenParameters.ClientId = $ClientId }

        Write-Information -InformationAction Continue -MessageData 'Using native OAuth device-code authentication (Microsoft.Graph.Authentication is not required).'
        $token = Get-WindowsDeviceLinkDeviceCodeToken @tokenParameters
        return Invoke-WindowsDeviceLinkGraphRegistration -InputObject $deviceLink -AccessToken $token.AccessToken -TenantId $TenantId
    }

    if ($support.Environment -eq 'WindowsPE') {
        if ($Environment -ne 'Global') {
            throw 'Native WinPE authentication currently supports the Global Microsoft cloud only.'
        }

        switch ($methods[0]) {
            'ClientSecret' {
                if (-not $TenantId -or -not $ClientId) {
                    throw '-TenantId and -ClientId are required for client secret authentication.'
                }
                Write-Information -InformationAction Continue -MessageData 'Using native OAuth client-credentials authentication for WinPE (Microsoft.Graph.Authentication is not required).'
                $token = Get-WindowsDeviceLinkClientSecretToken -TenantId $TenantId -ClientId $ClientId -ClientSecret $ClientSecret
                return Invoke-WindowsDeviceLinkGraphRegistration -InputObject $deviceLink -AccessToken $token.AccessToken -TenantId $TenantId
            }
            'AccessToken' {
                if (-not $TenantId) {
                    throw '-TenantId is required with -AccessToken in WinPE so the registration result can identify the tenant.'
                }
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
            'EnvironmentVariable' {
                if (-not $env:AZURE_TENANT_ID -or -not $env:AZURE_CLIENT_ID -or -not $env:AZURE_CLIENT_SECRET) {
                    throw 'WinPE environment-variable authentication requires AZURE_TENANT_ID, AZURE_CLIENT_ID, and AZURE_CLIENT_SECRET.'
                }
                $environmentSecret = ConvertTo-SecureString $env:AZURE_CLIENT_SECRET -AsPlainText -Force
                Write-Information -InformationAction Continue -MessageData 'Using native OAuth client-credentials authentication from environment variables for WinPE.'
                $token = Get-WindowsDeviceLinkClientSecretToken `
                    -TenantId $env:AZURE_TENANT_ID `
                    -ClientId $env:AZURE_CLIENT_ID `
                    -ClientSecret $environmentSecret
                return Invoke-WindowsDeviceLinkGraphRegistration `
                    -InputObject $deviceLink `
                    -AccessToken $token.AccessToken `
                    -TenantId $env:AZURE_TENANT_ID
            }
        }
    }

    $connectParams = @{
        Environment   = $Environment
        ClientTimeout = $ClientTimeout
    }

    switch ($methods[0]) {
        'Interactive' {
            if (-not $TenantId) { throw '-TenantId is required for -Online -Interactive.' }
            $connectParams.TenantId = $TenantId
            if ($ClientId) { $connectParams.ClientId = $ClientId }
        }
        'AccessToken' { $connectParams.AccessToken = $AccessToken }
        'Certificate' {
            if (-not $TenantId -or -not $ClientId) { throw '-TenantId and -ClientId are required for certificate authentication.' }
            $connectParams.TenantId = $TenantId
            $connectParams.ClientId = $ClientId
            $connectParams.Certificate = $Certificate
            $connectParams.SendCertificateChain = $SendCertificateChain
        }
        'CertificateThumbprint' {
            if (-not $TenantId -or -not $ClientId) { throw '-TenantId and -ClientId are required for certificate thumbprint authentication.' }
            $connectParams.TenantId = $TenantId
            $connectParams.ClientId = $ClientId
            $connectParams.CertificateThumbprint = $CertificateThumbprint
            $connectParams.SendCertificateChain = $SendCertificateChain
        }
        'CertificateSubjectName' {
            if (-not $TenantId -or -not $ClientId) { throw '-TenantId and -ClientId are required for certificate subject authentication.' }
            $connectParams.TenantId = $TenantId
            $connectParams.ClientId = $ClientId
            $connectParams.CertificateSubjectName = $CertificateSubjectName
            $connectParams.SendCertificateChain = $SendCertificateChain
        }
        'ClientSecret' {
            if (-not $TenantId -or -not $ClientId) { throw '-TenantId and -ClientId are required for client secret authentication.' }
            $connectParams.TenantId = $TenantId
            $connectParams.ClientId = $ClientId
            $connectParams.ClientSecret = $ClientSecret
        }
        'ManagedIdentity' {
            $connectParams.Identity = $true
            if ($ClientId) { $connectParams.ClientId = $ClientId }
        }
        'EnvironmentVariable' { $connectParams.EnvironmentVariable = $true }
    }

    Connect-WindowsDeviceLink @connectParams | Out-Null
    $deviceLink | Register-WindowsDeviceLink
}
