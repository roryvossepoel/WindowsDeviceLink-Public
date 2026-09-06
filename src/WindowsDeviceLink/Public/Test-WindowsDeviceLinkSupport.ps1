function Test-WindowsDeviceLinkSupport {
    [CmdletBinding()]
    param(
        [ValidateNotNullOrEmpty()]
        [string]$WindowsManagementServicePath
    )

    $isWinPE = Test-Path -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Control\MiniNT'
    $environment = if ($isWinPE) { 'WindowsPE' } else { 'Windows' }

    if ($PSBoundParameters.ContainsKey('WindowsManagementServicePath')) {
        $candidatePath = $WindowsManagementServicePath
        $dllSource = 'Explicit'
        $activationMode = 'DirectDll'
    }
    elseif ($isWinPE) {
        $candidatePath = $script:BundledWindowsManagementServicePath
        $dllSource = 'Bundled'
        $activationMode = 'DirectDll'
    }
    else {
        $candidatePath = Join-Path $env:SystemRoot 'System32\Windows.Management.Service.dll'
        $dllSource = 'System'
        $activationMode = 'RegisteredWinRT'
    }

    try {
        $resolvedPath = (Resolve-Path -LiteralPath $candidatePath -ErrorAction Stop).Path
    }
    catch {
        $missingReason = if ($dllSource -eq 'System') {
            'The Windows system copy of Windows.Management.Service.dll was not found.'
        }
        elseif ($isWinPE -and -not $PSBoundParameters.ContainsKey('WindowsManagementServicePath')) {
            'Windows.Management.Service.dll was not found. PowerShell Gallery packages intentionally do not include this Microsoft binary because redistribution rights have not been confirmed. For WinPE, place a compatible copy in the module Runtime folder or supply -WindowsManagementServicePath explicitly.'
        }
        else {
            'Windows.Management.Service.dll was not found at the supplied path.'
        }

        return [pscustomobject]@{
            Supported        = $false
            Environment      = $environment
            Architecture     = $env:PROCESSOR_ARCHITECTURE
            DllSource        = $dllSource
            ActivationMode   = $activationMode
            DllPath          = $candidatePath
            DllVersion       = $null
            SignatureStatus  = $null
            MicrosoftSigned  = $false
            NativeProbe      = $null
            Warning          = $null
            Reason           = $missingReason
        }
    }

    $signatureStatus = $null
    $isMicrosoftSigned = $false
    $signatureWarning = $null
    try {
        $signature = Get-AuthenticodeSignature -LiteralPath $resolvedPath -ErrorAction Stop
        $signatureStatus = [string]$signature.Status
        $isMicrosoftSigned = $signature.Status -eq 'Valid' -and $signature.SignerCertificate -and $signature.SignerCertificate.Subject -match 'Microsoft'
        if (-not $isMicrosoftSigned) {
            $signatureWarning = "Authenticode could not validate the DLL as Microsoft-signed in the current environment (status: $signatureStatus). This is informational and does not block the native probe."
        }
    }
    catch {
        $signatureStatus = 'Unavailable'
        $signatureWarning = "Authenticode validation was unavailable: $($_.Exception.Message)"
    }

    $architectureSupported = [Environment]::Is64BitProcess -and $env:PROCESSOR_ARCHITECTURE -eq 'AMD64'
    if ($architectureSupported) {
        if ($activationMode -eq 'RegisteredWinRT') {
            $nativeProbe = [WinPEDeviceLink.Native.DeviceLinkClient]::TestRegistered()
        }
        else {
            $nativeProbe = [WinPEDeviceLink.Native.DeviceLinkClient]::Test($resolvedPath)
        }
    }
    else {
        $nativeProbe = [pscustomobject]@{ Success = $false; Message = 'Native probe skipped because the current process is not AMD64 64-bit PowerShell.' }
    }

    [pscustomobject]@{
        Supported        = $architectureSupported -and $nativeProbe.Success
        Environment      = $environment
        Architecture     = $env:PROCESSOR_ARCHITECTURE
        DllSource        = $dllSource
        ActivationMode   = $activationMode
        DllPath          = $resolvedPath
        DllVersion       = (Get-Item -LiteralPath $resolvedPath).VersionInfo.FileVersion
        SignatureStatus  = $signatureStatus
        MicrosoftSigned  = $isMicrosoftSigned
        NativeProbe      = $nativeProbe.Message
        Warning          = $signatureWarning
        Reason           = if (-not $architectureSupported) { 'The current preview supports AMD64 64-bit PowerShell only.' } elseif (-not $nativeProbe.Success) { $nativeProbe.Message } else { $null }
    }
}
