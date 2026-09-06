function Initialize-WindowsDeviceLinkOnline {
    [CmdletBinding()]
    param(
        [version]$MinimumGraphAuthenticationVersion = [version]'2.8.0',
        [version]$FallbackGraphAuthenticationVersion = [version]'2.28.0'
    )

    if (-not $env:APPDATA -and $env:USERPROFILE) {
        $env:APPDATA = Join-Path $env:USERPROFILE 'AppData\Roaming'
    }
    if (-not $env:LOCALAPPDATA -and $env:USERPROFILE) {
        $env:LOCALAPPDATA = Join-Path $env:USERPROFILE 'AppData\Local'
    }

    [Net.ServicePointManager]::SecurityProtocol =
        [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

    $availableGraph = Get-Module -ListAvailable -Name Microsoft.Graph.Authentication |
        Where-Object { $_.Version -ge $MinimumGraphAuthenticationVersion } |
        Sort-Object Version -Descending |
        Select-Object -First 1

    if ($availableGraph) {
        Import-Module $availableGraph.Path -Force -ErrorAction Stop
        return
    }

    $isWinPE = Test-Path -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Control\MiniNT'

    if (-not $isWinPE) {
        Write-Information -InformationAction Continue -MessageData 'Microsoft.Graph.Authentication is not available. Installing it from PowerShell Gallery...'

        if (-not (Get-Command Install-Module -ErrorAction SilentlyContinue)) {
            throw 'Microsoft.Graph.Authentication is not installed and Install-Module is unavailable. Install Microsoft.Graph.Authentication 2.8.0 or later and retry.'
        }

        Install-Module -Name Microsoft.Graph.Authentication `
            -MinimumVersion $MinimumGraphAuthenticationVersion `
            -Repository PSGallery `
            -Scope CurrentUser `
            -Force `
            -AllowClobber `
            -ErrorAction Stop

        Import-Module Microsoft.Graph.Authentication -MinimumVersion $MinimumGraphAuthenticationVersion -Force -ErrorAction Stop
        return
    }

    Write-Information -InformationAction Continue -MessageData 'Microsoft.Graph.Authentication is not available. Bootstrapping the official PowerShell Gallery package for this WinPE session...'

    $cacheRoot = if ($env:TEMP) {
        Join-Path $env:TEMP 'WindowsDeviceLink\GraphAuthentication'
    }
    else {
        'X:\Windows\Temp\WindowsDeviceLink\GraphAuthentication'
    }
    New-Item -Path $cacheRoot -ItemType Directory -Force | Out-Null

    $runId = [guid]::NewGuid().ToString('N')
    $runRoot = Join-Path $cacheRoot $runId
    $extractPath = Join-Path $runRoot 'module'
    $packagePath = Join-Path $runRoot 'Microsoft.Graph.Authentication.nupkg'
    New-Item -Path $extractPath -ItemType Directory -Force | Out-Null

    $downloadUris = @(
        'https://www.powershellgallery.com/api/v2/package/Microsoft.Graph.Authentication',
        ('https://www.powershellgallery.com/api/v2/package/Microsoft.Graph.Authentication/{0}' -f $FallbackGraphAuthenticationVersion)
    )

    $downloaded = $false
    $lastError = $null
    foreach ($downloadUri in $downloadUris) {
        try {
            Write-Information -InformationAction Continue -MessageData 'Downloading Microsoft.Graph.Authentication from PowerShell Gallery...'
            $webClient = New-Object System.Net.WebClient
            $webClient.Headers.Add('User-Agent', 'WindowsDeviceLink-PowerShell/0.3')
            $webClient.DownloadFile($downloadUri, $packagePath)
            $webClient.Dispose()

            if ((Test-Path -LiteralPath $packagePath) -and (Get-Item -LiteralPath $packagePath).Length -gt 0) {
                $downloaded = $true
                break
            }
        }
        catch {
            $lastError = $_
            if ($webClient) { $webClient.Dispose() }
        }
    }

    if (-not $downloaded) {
        throw "Unable to download Microsoft.Graph.Authentication from PowerShell Gallery. $($lastError.Exception.Message)"
    }

    try {
        Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue
        [System.IO.Compression.ZipFile]::ExtractToDirectory($packagePath, $extractPath)
    }
    catch {
        throw "Unable to extract Microsoft.Graph.Authentication package in WinPE: $($_.Exception.Message)"
    }

    $manifest = Get-ChildItem -Path $extractPath -Filter 'Microsoft.Graph.Authentication.psd1' -Recurse -File |
        Select-Object -First 1

    if (-not $manifest) {
        throw 'The downloaded Microsoft.Graph.Authentication package did not contain Microsoft.Graph.Authentication.psd1.'
    }

    try {
        $moduleData = Test-ModuleManifest -Path $manifest.FullName -ErrorAction Stop
        if ($moduleData.Version -lt $MinimumGraphAuthenticationVersion) {
            throw "Downloaded Microsoft.Graph.Authentication version $($moduleData.Version) is older than required version $MinimumGraphAuthenticationVersion."
        }

        Import-Module $manifest.FullName -Force -ErrorAction Stop
    }
    catch {
        throw "Microsoft.Graph.Authentication was downloaded but could not be imported in WinPE: $($_.Exception.Message)"
    }

    if (-not (Get-Command Connect-MgGraph -ErrorAction SilentlyContinue)) {
        throw 'Microsoft.Graph.Authentication was bootstrapped but Connect-MgGraph is still unavailable.'
    }

    Write-Information -InformationAction Continue -MessageData "Microsoft.Graph.Authentication $($moduleData.Version) loaded temporarily for this WinPE session."
}
