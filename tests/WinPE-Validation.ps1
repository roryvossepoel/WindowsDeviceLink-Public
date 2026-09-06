<#
WindowsDeviceLink - WinPE validation runner

This public test runner contains no tenant-specific or device-specific values.
Provide TenantId and ClientId when starting the script.

Example:
.\WinPE-Validation.ps1 -TenantId '<tenant-id>' -ClientId '<app-id>'

For certificate tests, provide a PFX containing the private key when prompted.
The public WindowsDeviceLink package does not include Windows.Management.Service.dll.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$TenantId,

    [Parameter(Mandatory)]
    [string]$ClientId,

    [string]$ModulePath,
    [string]$ExportRoot = 'X:\WindowsDeviceLink-Test'
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

function Get-ClientSecret {
    if (-not $script:ClientSecret) {
        $script:ClientSecret = Read-Host 'Client secret' -AsSecureString
    }
    $script:ClientSecret
}

function Get-AppOnlyAccessToken {
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
        '3' { Invoke-Test 'Device code + CSV + online registration' { Get-WindowsDeviceLink -OutputDirectory $ExportRoot -Online -TenantId $TenantId -UseDeviceCode | Format-List } }
        '4' { Invoke-Test 'Client secret' { $secret = Get-ClientSecret; Get-WindowsDeviceLink -Online -TenantId $TenantId -ClientId $ClientId -ClientSecret $secret | Format-List } }
        '5' { Invoke-Test 'Access token' { $token = Get-AppOnlyAccessToken; Get-WindowsDeviceLink -Online -TenantId $TenantId -AccessToken $token | Format-List } }
        '6' { Invoke-Test 'Environment variables' {
            $secret = Get-ClientSecret
            $plainSecret = ConvertFrom-SecureStringPlainText -SecureString $secret
            try {
                $env:AZURE_TENANT_ID = $TenantId
                $env:AZURE_CLIENT_ID = $ClientId
                $env:AZURE_CLIENT_SECRET = $plainSecret
                Get-WindowsDeviceLink -Online -EnvironmentVariable | Format-List
            }
            finally {
                Remove-Item Env:AZURE_TENANT_ID,Env:AZURE_CLIENT_ID,Env:AZURE_CLIENT_SECRET -ErrorAction SilentlyContinue
                $plainSecret = $null
            }
        } }
        '7' { Invoke-Test 'Certificate object' { $cert = Get-TestCertificate; Get-WindowsDeviceLink -Online -TenantId $TenantId -ClientId $ClientId -Certificate $cert | Format-List } }
        '8' { Invoke-Test 'Certificate thumbprint' { $cert = Install-TestCertificate; Get-WindowsDeviceLink -Online -TenantId $TenantId -ClientId $ClientId -CertificateThumbprint $cert.Thumbprint | Format-List } }
        '9' { Invoke-Test 'Certificate subject name' { $cert = Install-TestCertificate; Get-WindowsDeviceLink -Online -TenantId $TenantId -ClientId $ClientId -CertificateSubjectName $cert.Subject | Format-List } }
        'Q' { break }
        default { Write-Host 'Unknown selection.' }
    }
}
