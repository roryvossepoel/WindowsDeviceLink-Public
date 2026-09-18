function Test-WindowsDeviceLinkRuntime {
    <#
    .SYNOPSIS
    Performs a read-only validation of a Windows.Management.Service.dll candidate.

    .DESCRIPTION
    Intended primarily for Windows PE research and diagnostics. The command never generates
    a DeviceLink, never creates/removes a tenant association, never resets firmware and never
    invokes ConfigureDeviceLinkAsync.

    The current prototype validates:
    - file presence;
    - PE machine architecture;
    - file/product version;
    - Authenticode status;
    - host process architecture;
    - direct DeviceLink runtime activation through the existing native probe.

    Load/activation failures are classified into practical diagnostic states where possible.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$DllPath
    )

    function Get-PeMachine {
        param([Parameter(Mandatory)][string]$Path)

        $stream = $null
        $reader = $null
        try {
            $stream = [IO.File]::Open($Path,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::ReadWrite)
            $reader = New-Object IO.BinaryReader($stream)

            if ($reader.ReadUInt16() -ne 0x5A4D) {
                return [pscustomobject]@{ Machine=$null; Architecture='Unknown'; Error='Missing MZ header.' }
            }

            $stream.Position = 0x3C
            $peOffset = $reader.ReadInt32()
            if ($peOffset -lt 0 -or $peOffset -gt ($stream.Length - 6)) {
                return [pscustomobject]@{ Machine=$null; Architecture='Unknown'; Error='Invalid PE header offset.' }
            }

            $stream.Position = $peOffset
            if ($reader.ReadUInt32() -ne 0x00004550) {
                return [pscustomobject]@{ Machine=$null; Architecture='Unknown'; Error='Missing PE signature.' }
            }

            $machine = $reader.ReadUInt16()
            $architecture = switch ($machine) {
                0x8664 { 'AMD64' }
                0xAA64 { 'ARM64' }
                0x014C { 'X86' }
                default { 'Unknown' }
            }

            [pscustomobject]@{
                Machine      = ('0x{0:X4}' -f $machine)
                Architecture = $architecture
                Error        = $null
            }
        }
        catch {
            [pscustomobject]@{ Machine=$null; Architecture='Unknown'; Error=$_.Exception.Message }
        }
        finally {
            if ($reader) { $reader.Dispose() }
            elseif ($stream) { $stream.Dispose() }
        }
    }

    $environment = if (Test-Path -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Control\MiniNT') { 'WindowsPE' } else { 'Windows' }
    $hostArchitecture = $env:PROCESSOR_ARCHITECTURE
    $resolvedPath = $null

    try {
        $resolvedPath = (Resolve-Path -LiteralPath $DllPath -ErrorAction Stop).Path
    }
    catch {
        return [pscustomobject]@{
            PSTypeName              = 'Windows.DeviceLink.RuntimeProbe'
            State                   = 'RuntimeMissing'
            Ready                   = $false
            Environment             = $environment
            HostArchitecture        = $hostArchitecture
            DllPath                 = $DllPath
            DllPresent              = $false
            DllArchitecture         = $null
            PeMachine               = $null
            FileVersion             = $null
            ProductVersion          = $null
            SignatureStatus         = $null
            MicrosoftSigned         = $false
            LoadActivationSucceeded = $false
            NativeProbe             = $null
            NativeErrorCode         = $null
            BlockingReason          = 'Windows.Management.Service.dll was not found at the supplied path.'
        }
    }

    $file = Get-Item -LiteralPath $resolvedPath -ErrorAction Stop
    $pe = Get-PeMachine -Path $resolvedPath

    $signatureStatus = $null
    $microsoftSigned = $false
    try {
        $signature = Get-AuthenticodeSignature -LiteralPath $resolvedPath -ErrorAction Stop
        $signatureStatus = [string]$signature.Status
        $microsoftSigned = $signature.Status -eq 'Valid' -and $signature.SignerCertificate -and $signature.SignerCertificate.Subject -match 'Microsoft'
    }
    catch {
        $signatureStatus = 'Unavailable'
    }

    $hostSupported = [Environment]::Is64BitProcess -and $hostArchitecture -eq 'AMD64'
    $dllArchCompatible = $pe.Architecture -eq 'AMD64'

    if (-not $hostSupported) {
        return [pscustomobject]@{
            PSTypeName              = 'Windows.DeviceLink.RuntimeProbe'
            State                   = 'UnsupportedHostArchitecture'
            Ready                   = $false
            Environment             = $environment
            HostArchitecture        = $hostArchitecture
            DllPath                 = $resolvedPath
            DllPresent              = $true
            DllArchitecture         = $pe.Architecture
            PeMachine               = $pe.Machine
            FileVersion             = $file.VersionInfo.FileVersion
            ProductVersion          = $file.VersionInfo.ProductVersion
            SignatureStatus         = $signatureStatus
            MicrosoftSigned         = $microsoftSigned
            LoadActivationSucceeded = $false
            NativeProbe             = $null
            NativeErrorCode         = $null
            BlockingReason          = 'The current prototype supports AMD64 64-bit PowerShell only.'
        }
    }

    if (-not $dllArchCompatible) {
        return [pscustomobject]@{
            PSTypeName              = 'Windows.DeviceLink.RuntimeProbe'
            State                   = 'WrongArchitecture'
            Ready                   = $false
            Environment             = $environment
            HostArchitecture        = $hostArchitecture
            DllPath                 = $resolvedPath
            DllPresent              = $true
            DllArchitecture         = $pe.Architecture
            PeMachine               = $pe.Machine
            FileVersion             = $file.VersionInfo.FileVersion
            ProductVersion          = $file.VersionInfo.ProductVersion
            SignatureStatus         = $signatureStatus
            MicrosoftSigned         = $microsoftSigned
            LoadActivationSucceeded = $false
            NativeProbe             = $null
            NativeErrorCode         = $null
            BlockingReason          = if ($pe.Error) { $pe.Error } else { "The supplied DLL architecture '$($pe.Architecture)' is not compatible with the AMD64 prototype." }
        }
    }

    $probe = [WinPEDeviceLink.Native.DeviceLinkClient]::Test($resolvedPath)
    $nativeMessage = [string]$probe.Message
    $nativeErrorCode = $null

    if ($nativeMessage -match '(?i)HRESULT\s+0x([0-9A-F]{8})') {
        $nativeErrorCode = '0x' + $matches[1].ToUpperInvariant()
    }
    elseif ($nativeMessage -match '(?i)(?:Win32Exception|error)\D+(\d+)') {
        $nativeErrorCode = [string]$matches[1]
    }
    elseif ($nativeMessage -match '\((\d+)\)') {
        $nativeErrorCode = [string]$matches[1]
    }

    if ($probe.Success) {
        $state = 'Ready'
        $reason = $null
    }
    elseif ($nativeMessage -match '(?i)LoadLibraryEx failed' -and $nativeMessage -match '(?:\b126\b|module could not be found)') {
        $state = 'DependencyMissing'
        $reason = 'LoadLibraryEx could not resolve the supplied runtime or one of its dependencies.'
    }
    elseif ($nativeMessage -match '(?i)LoadLibraryEx failed') {
        $state = 'LoadFailed'
        $reason = $nativeMessage
    }
    else {
        $state = 'ActivationFailed'
        $reason = $nativeMessage
    }

    [pscustomobject]@{
        PSTypeName              = 'Windows.DeviceLink.RuntimeProbe'
        State                   = $state
        Ready                   = [bool]$probe.Success
        Environment             = $environment
        HostArchitecture        = $hostArchitecture
        DllPath                 = $resolvedPath
        DllPresent              = $true
        DllArchitecture         = $pe.Architecture
        PeMachine               = $pe.Machine
        FileVersion             = $file.VersionInfo.FileVersion
        ProductVersion          = $file.VersionInfo.ProductVersion
        SignatureStatus         = $signatureStatus
        MicrosoftSigned         = $microsoftSigned
        LoadActivationSucceeded = [bool]$probe.Success
        NativeProbe             = $nativeMessage
        NativeErrorCode         = $nativeErrorCode
        BlockingReason          = $reason
    }
}
