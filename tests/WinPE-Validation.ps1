<#
WindowsDeviceLink - WinPE validation runner

This public test runner contains no tenant-specific or device-specific values.

When invoked without -Interactive, it performs automation-safe contract validation only
and exits without prompting. Use -Interactive for the live WinPE menu.

Example:
.\WinPE-Validation.ps1 -Interactive

TenantId and ClientId are only required for authentication methods that technically
need them, such as client-secret and certificate flows.

For certificate tests, provide a PFX containing the private key when prompted.
The public WindowsDeviceLink package does not include Windows.Management.Service.dll.
#>

[CmdletBinding()]
param(
    [string]$TenantId,
    [string]$ClientId,
    [string]$ModulePath,
    [string]$ExportRoot = 'X:\WindowsDeviceLink-Test',
    [switch]$Interactive
)

$ErrorActionPreference = 'Stop'
$script:ClientSecret = $null
$script:PfxPath = $null
$script:PfxPassword = $null
$script:LoadedCertificate = $null
$script:CertificateInstalledInStore = $false

function ConvertFrom-SecureStringPlainText {
    param([Parameter(Mandatory)][securestring]$SecureString)
    $credential = New-Object System.Management.Automation.PSCredential('WindowsDeviceLink', $SecureString)
    $credential.GetNetworkCredential().Password
}

function Resolve-WindowsDeviceLinkModule {
    if ($ModulePath) { return (Resolve-Path -LiteralPath $ModulePath -ErrorAction Stop).Path }

    $candidates = @(
        (Join-Path $PSScriptRoot '..\src\WindowsDeviceLink\WindowsDeviceLink.psd1'),
        (Join-Path $PSScriptRoot 'src\WindowsDeviceLink\WindowsDeviceLink.psd1')
    )

    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            return (Resolve-Path -LiteralPath $candidate).Path
        }
    }

    $manual = Read-Host 'Full path to WindowsDeviceLink.psd1'
    return (Resolve-Path -LiteralPath $manual -ErrorAction Stop).Path
}

function Assert-AppOnlyConfiguration {
    if ([string]::IsNullOrWhiteSpace($TenantId) -or [string]::IsNullOrWhiteSpace($ClientId)) {
        throw 'This authentication method requires -TenantId and -ClientId. Restart the live WinPE runner with those parameters.'
    }
}

function Get-ClientSecret {
    if (-not $script:ClientSecret) {
        $script:ClientSecret = Read-Host 'Client secret' -AsSecureString
    }
    $script:ClientSecret
}

function Get-AppOnlyAccessToken {
    Assert-AppOnlyConfiguration
    $secret = Get-ClientSecret
    $plainSecret = ConvertFrom-SecureStringPlainText -SecureString $secret
    try {
        $response = Invoke-RestMethod -Method POST `
            -Uri "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token" `
            -ContentType 'application/x-www-form-urlencoded' `
            -Body @{
                client_id = $ClientId
                client_secret = $plainSecret
                grant_type = 'client_credentials'
                scope = 'https://graph.microsoft.com/.default'
            }
    }
    finally {
        $plainSecret = $null
    }
    ConvertTo-SecureString $response.access_token -AsPlainText -Force
}

function Get-TestCertificate {
    if ($script:LoadedCertificate) { return $script:LoadedCertificate }
    if (-not $script:PfxPath) { $script:PfxPath = Read-Host 'Full path to PFX' }
    if (-not $script:PfxPassword) { $script:PfxPassword = Read-Host 'PFX password' -AsSecureString }

    $plainPassword = ConvertFrom-SecureStringPlainText -SecureString $script:PfxPassword
    $flags = [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::Exportable -bor
             [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::PersistKeySet -bor
             [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::UserKeySet

    $script:LoadedCertificate = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2(
        $script:PfxPath,
        $plainPassword,
        $flags
    )
    $script:LoadedCertificate
}

function Install-TestCertificate {
    $cert = Get-TestCertificate
    if ($script:CertificateInstalledInStore) { return $cert }
    $store = New-Object System.Security.Cryptography.X509Certificates.X509Store('My','CurrentUser')
    try {
        $store.Open([System.Security.Cryptography.X509Certificates.OpenFlags]::ReadWrite)
        $store.Add($cert)
        $script:CertificateInstalledInStore = $true
    }
    finally { $store.Close() }
    $cert
}

function Invoke-Test {
    param([string]$Name,[scriptblock]$Body)
    Write-Host ''
    Write-Host "--- $Name ---"
    try {
        & $Body
        Write-Host "PASS: $Name"
    }
    catch {
        Write-Host "FAIL: $Name"
        Write-Host $_.Exception.Message
    }
}

$resolvedModule = Resolve-WindowsDeviceLinkModule
Import-Module $resolvedModule -Force

if (-not $Interactive) {
    $getLocal = Get-Command Get-WindowsDeviceLink -Module WindowsDeviceLink
    if ($getLocal.Parameters.ContainsKey('Online')) {
        throw 'FAIL: Get-WindowsDeviceLink unexpectedly exposes the legacy -Online parameter.'
    }

    $register = Get-Command Register-WindowsDeviceLink -Module WindowsDeviceLink
    if (-not $register.Parameters.ContainsKey('Method')) {
        throw 'FAIL: Register-WindowsDeviceLink is missing -Method.'
    }

    $registerSource = $register.ScriptBlock.ToString()
    if ($registerSource -match '-TenantId is required for -Method DeviceCode') {
        throw 'FAIL: DeviceCode registration unexpectedly requires -TenantId.'
    }

    Write-Host 'PASS: WinPE validation runner uses the current local-identity + explicit cloud-registration contract and is automation-safe by default.'
    return
}

while ($true) {
    Write-Host ''
    Write-Host 'WindowsDeviceLink - WinPE validation'
    Write-Host '1  Support + local generation'
    Write-Host '2  CSV export regression'
    Write-Host '3  Device code + CSV + online registration'
    Write-Host '4  Client secret'
    Write-Host '5  Access token'
    Write-Host '6  Environment variables'
    Write-Host '7  Certificate object'
    Write-Host '8  Certificate thumbprint'
    Write-Host '9  Certificate subject name'
    Write-Host 'Q  Quit'

    $choice = (Read-Host 'Select test').Trim().ToUpperInvariant()
    switch ($choice) {
        '1' { Invoke-Test 'Support + local generation' { Test-WindowsDeviceLinkSupport | Format-List *; Get-WindowsDeviceLink | Format-List Environment,SerialNumber,Manufacturer,Model,LinkId,DllSource,ActivationMode,DllVersion } }
        '2' { Invoke-Test 'CSV export regression' { Get-WindowsDeviceLink -OutputDirectory $ExportRoot | Out-Host } }
        '3' { Invoke-Test 'Device code + CSV + online registration' {
            $deviceLink = Get-WindowsDeviceLink
            $deviceLink | Export-WindowsDeviceLinkCsv -DestinationPath $ExportRoot | Out-Host
            $deviceLink | Register-WindowsDeviceLink -Method DeviceCode | Format-List
        } }
        '4' { Invoke-Test 'Client secret' { Assert-AppOnlyConfiguration; $secret = Get-ClientSecret; Get-WindowsDeviceLink | Register-WindowsDeviceLink -Method ClientSecret -TenantId $TenantId -ClientId $ClientId -ClientSecret $secret | Format-List } }
        '5' { Invoke-Test 'Access token' { $token = Get-AppOnlyAccessToken; Get-WindowsDeviceLink | Register-WindowsDeviceLink -Method AccessToken -AccessToken $token | Format-List } }
        '6' { Invoke-Test 'Environment variables' {
            Assert-AppOnlyConfiguration
            $secret = Get-ClientSecret
            $plainSecret = ConvertFrom-SecureStringPlainText -SecureString $secret
            try {
                $env:AZURE_TENANT_ID = $TenantId
                $env:AZURE_CLIENT_ID = $ClientId
                $env:AZURE_CLIENT_SECRET = $plainSecret
                Get-WindowsDeviceLink | Register-WindowsDeviceLink -Method EnvironmentVariable | Format-List
            }
            finally {
                Remove-Item Env:AZURE_TENANT_ID,Env:AZURE_CLIENT_ID,Env:AZURE_CLIENT_SECRET -ErrorAction SilentlyContinue
                $plainSecret = $null
            }
        } }
        '7' { Invoke-Test 'Certificate object' { Assert-AppOnlyConfiguration; $cert = Get-TestCertificate; Get-WindowsDeviceLink | Register-WindowsDeviceLink -Method Certificate -TenantId $TenantId -ClientId $ClientId -Certificate $cert | Format-List } }
        '8' { Invoke-Test 'Certificate thumbprint' { Assert-AppOnlyConfiguration; $cert = Install-TestCertificate; Get-WindowsDeviceLink | Register-WindowsDeviceLink -Method CertificateThumbprint -TenantId $TenantId -ClientId $ClientId -CertificateThumbprint $cert.Thumbprint | Format-List } }
        '9' { Invoke-Test 'Certificate subject name' { Assert-AppOnlyConfiguration; $cert = Install-TestCertificate; Get-WindowsDeviceLink | Register-WindowsDeviceLink -Method CertificateSubjectName -TenantId $TenantId -ClientId $ClientId -CertificateSubjectName $cert.Subject | Format-List } }
        'Q' { break }
        default { Write-Host 'Unknown selection.' }
    }
}
