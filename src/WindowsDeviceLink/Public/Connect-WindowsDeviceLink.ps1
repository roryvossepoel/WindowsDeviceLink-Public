function Connect-WindowsDeviceLink {
    [CmdletBinding(DefaultParameterSetName = 'Interactive')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'Interactive')]
        [Parameter(Mandatory, ParameterSetName = 'DeviceCode')]
        [Parameter(Mandatory, ParameterSetName = 'Certificate')]
        [Parameter(Mandatory, ParameterSetName = 'CertificateThumbprint')]
        [Parameter(Mandatory, ParameterSetName = 'CertificateSubjectName')]
        [Parameter(Mandatory, ParameterSetName = 'ClientSecret')]
        [ValidateNotNullOrEmpty()]
        [string]$TenantId,

        [Parameter(ParameterSetName = 'Interactive')]
        [Parameter(Mandatory, ParameterSetName = 'Certificate')]
        [Parameter(Mandatory, ParameterSetName = 'CertificateThumbprint')]
        [Parameter(Mandatory, ParameterSetName = 'CertificateSubjectName')]
        [Parameter(Mandatory, ParameterSetName = 'ClientSecret')]
        [Parameter(ParameterSetName = 'ManagedIdentity')]
        [ValidateNotNullOrEmpty()]
        [string]$ClientId,

        [Parameter(ParameterSetName = 'Interactive')]
        [Parameter(ParameterSetName = 'DeviceCode')]
        [ValidateNotNullOrEmpty()]
        [string[]]$Scopes = @('DeviceManagementServiceConfig.ReadWrite.All'),

        [Parameter(Mandatory, ParameterSetName = 'DeviceCode')]
        [switch]$UseDeviceCode,

        [Parameter(Mandatory, ParameterSetName = 'AccessToken')]
        [ValidateNotNull()]
        [securestring]$AccessToken,

        [Parameter(Mandatory, ParameterSetName = 'Certificate')]
        [ValidateNotNull()]
        [System.Security.Cryptography.X509Certificates.X509Certificate2]$Certificate,

        [Parameter(Mandatory, ParameterSetName = 'CertificateThumbprint')]
        [ValidateNotNullOrEmpty()]
        [string]$CertificateThumbprint,

        [Parameter(Mandatory, ParameterSetName = 'CertificateSubjectName')]
        [ValidateNotNullOrEmpty()]
        [string]$CertificateSubjectName,

        [Parameter(ParameterSetName = 'Certificate')]
        [Parameter(ParameterSetName = 'CertificateThumbprint')]
        [Parameter(ParameterSetName = 'CertificateSubjectName')]
        [bool]$SendCertificateChain = $false,

        [Parameter(Mandatory, ParameterSetName = 'ClientSecret')]
        [ValidateNotNull()]
        [securestring]$ClientSecret,

        [Parameter(Mandatory, ParameterSetName = 'ManagedIdentity')]
        [Alias('ManagedIdentity')]
        [switch]$Identity,

        [Parameter(Mandatory, ParameterSetName = 'EnvironmentVariable')]
        [switch]$EnvironmentVariable,

        [ValidateNotNullOrEmpty()]
        [string]$Environment = 'Global',

        [ValidateRange(1, 600)]
        [double]$ClientTimeout = 100
    )

    Initialize-WindowsDeviceLinkOnline

    if (-not (Get-Command Connect-MgGraph -ErrorAction SilentlyContinue)) {
        throw 'Microsoft.Graph.Authentication is unavailable after dependency initialization.'
    }

    $parameters = @{ Environment = $Environment; ClientTimeout = $ClientTimeout; NoWelcome = $true }

    switch ($PSCmdlet.ParameterSetName) {
        'Interactive' {
            $parameters.TenantId = $TenantId
            $parameters.Scopes = $Scopes
            $parameters.ContextScope = 'Process'
            if ($ClientId) { $parameters.ClientId = $ClientId }
            if (Test-Path -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Control\MiniNT') {
                Write-Warning 'Interactive browser authentication may not be available in WinPE. Use another supported authentication method if necessary.'
            }
        }
        'DeviceCode' {
            $parameters.TenantId = $TenantId
            $parameters.Scopes = $Scopes
            $parameters.ContextScope = 'Process'
            $parameters.UseDeviceCode = $true
        }
        'AccessToken' { $parameters.AccessToken = $AccessToken }
        'Certificate' {
            $parameters.TenantId = $TenantId; $parameters.ClientId = $ClientId; $parameters.Certificate = $Certificate
            $parameters.SendCertificateChain = $SendCertificateChain; $parameters.ContextScope = 'Process'
        }
        'CertificateThumbprint' {
            $parameters.TenantId = $TenantId; $parameters.ClientId = $ClientId; $parameters.CertificateThumbprint = $CertificateThumbprint
            $parameters.SendCertificateChain = $SendCertificateChain; $parameters.ContextScope = 'Process'
        }
        'CertificateSubjectName' {
            $parameters.TenantId = $TenantId; $parameters.ClientId = $ClientId; $parameters.CertificateSubjectName = $CertificateSubjectName
            $parameters.SendCertificateChain = $SendCertificateChain; $parameters.ContextScope = 'Process'
        }
        'ClientSecret' {
            $parameters.TenantId = $TenantId
            $parameters.ClientSecretCredential = New-Object System.Management.Automation.PSCredential($ClientId, $ClientSecret)
            $parameters.ContextScope = 'Process'
        }
        'ManagedIdentity' {
            $parameters.Identity = $true; $parameters.ContextScope = 'Process'
            if ($ClientId) { $parameters.ClientId = $ClientId }
        }
        'EnvironmentVariable' { $parameters.EnvironmentVariable = $true; $parameters.ContextScope = 'Process' }
        default { throw "Unsupported authentication parameter set: $($PSCmdlet.ParameterSetName)" }
    }

    Connect-MgGraph @parameters
}
