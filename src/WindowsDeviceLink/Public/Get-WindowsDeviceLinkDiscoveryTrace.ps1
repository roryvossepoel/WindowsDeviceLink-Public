function Get-WindowsDeviceLinkDiscoveryTrace {
    <#
    .SYNOPSIS
    Captures a read-only DeviceLink discovery prerequisite snapshot.

    .DESCRIPTION
    Intended for A/B comparison between full Windows and Windows PE. This command does not
    invoke DeviceLink discovery or configuration and does not modify DeviceLink state.

    It captures:
    - environment/build information;
    - relevant service status/start configuration;
    - selected registry/prerequisite locations;
    - DeviceLink WinRT registration state;
    - selected system/runtime files and versions;
    - selected modules loaded in the current PowerShell process.
    #>
    [CmdletBinding()]
    param()

    $environment = if (Test-Path -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Control\MiniNT') { 'WindowsPE' } else { 'Windows' }

    function Get-StartTypeName {
        param([int]$Value)
        switch ($Value) {
            0 { 'Boot' }
            1 { 'System' }
            2 { 'Automatic' }
            3 { 'Manual' }
            4 { 'Disabled' }
            default { [string]$Value }
        }
    }

    $os = $null
    try {
        $cv = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction Stop
        $os = [pscustomobject]@{
            ProductName    = $cv.ProductName
            DisplayVersion = $cv.DisplayVersion
            CurrentBuild   = $cv.CurrentBuild
            UBR            = $cv.UBR
            BuildLabEx     = $cv.BuildLabEx
            EditionID      = $cv.EditionID
        }
    }
    catch {
        $os = [pscustomobject]@{
            ProductName    = $null
            DisplayVersion = $null
            CurrentBuild   = $null
            UBR            = $null
            BuildLabEx     = $null
            EditionID      = $null
        }
    }

    $services = foreach ($serviceName in @(
        'RpcSs','DcomLaunch','CryptSvc','WinHttpAutoProxySvc','BITS','EventLog',
        'NlaSvc','Dhcp','Dnscache','WManSvc','dmwappushservice','gpsvc','ProfSvc',
        'StateRepository','TokenBroker','wlidsvc','NgcSvc','BrokerInfrastructure'
    )) {
        $present = $false
        $status = $null
        $startType = $null
        try {
            $service = Get-Service -Name $serviceName -ErrorAction Stop
            $present = $true
            $status = [string]$service.Status
        }
        catch { }

        try {
            $serviceKey = "HKLM:\SYSTEM\CurrentControlSet\Services\$serviceName"
            if (Test-Path -LiteralPath $serviceKey) {
                $startValue = (Get-ItemProperty -LiteralPath $serviceKey -Name Start -ErrorAction Stop).Start
                $startType = Get-StartTypeName -Value ([int]$startValue)
            }
        }
        catch { }

        [pscustomobject]@{
            Name      = $serviceName
            Present   = $present
            Status    = $status
            StartType = $startType
        }
    }

    $winRtClasses = foreach ($className in @(
        'ModernDeployment.Autopilot.Core.DeviceLinkUtilities',
        'ModernDeployment.Autopilot.Core.DeviceLinkManager'
    )) {
        $candidatePaths = @(
            "HKLM:\SOFTWARE\Microsoft\WindowsRuntime\ActivatableClassId\$className",
            "HKLM:\SOFTWARE\Classes\ActivatableClasses\CLSID\$className"
        )

        $foundPath = $candidatePaths | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1

        [pscustomobject]@{
            ClassName = $className
            Present   = [bool]$foundPath
            Path      = $foundPath
        }
    }

    $registry = foreach ($path in @(
        'HKLM:\SOFTWARE\Microsoft\Provisioning',
        'HKLM:\SOFTWARE\Microsoft\Enrollments',
        'HKLM:\SOFTWARE\Microsoft\EnterpriseResourceManager',
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Authentication',
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\DeviceAccess',
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Setup',
        'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Svchost'
    )) {
        [pscustomobject]@{
            Path    = $path
            Present = Test-Path -LiteralPath $path
        }
    }

    $files = foreach ($fileName in @(
        'Windows.Management.Service.dll',
        'winhttp.dll','crypt32.dll','bcrypt.dll','ncrypt.dll','tbs.dll',
        'webservices.dll','combase.dll','urlmon.dll','wininet.dll','iertutil.dll',
        'secur32.dll','sspicli.dll','schannel.dll','cryptnet.dll','webauthn.dll'
    )) {
        $path = Join-Path $env:SystemRoot "System32\$fileName"
        $present = Test-Path -LiteralPath $path
        $version = $null
        if ($present) {
            try { $version = (Get-Item -LiteralPath $path).VersionInfo.FileVersion } catch { }
        }

        [pscustomobject]@{
            Name    = $fileName
            Present = $present
            Path    = $path
            Version = $version
        }
    }

    $loadedModules = @()
    try {
        $loadedModules = [Diagnostics.Process]::GetCurrentProcess().Modules |
            Where-Object {
                $_.ModuleName -match 'Windows\.Management|winhttp|crypt|bcrypt|ncrypt|tbs|webservices|combase|urlmon|wininet|secur32|sspicli|schannel|cryptnet'
            } |
            ForEach-Object {
                [pscustomobject]@{
                    Name    = $_.ModuleName
                    Path    = $_.FileName
                    Version = $_.FileVersionInfo.FileVersion
                }
            } |
            Sort-Object Name,Path -Unique
    }
    catch { }

    [pscustomobject]@{
        PSTypeName       = 'Windows.DeviceLink.DiscoveryTrace'
        CapturedAtUtc    = [DateTime]::UtcNow
        Environment      = $environment
        Architecture     = $env:PROCESSOR_ARCHITECTURE
        Is64BitProcess   = [Environment]::Is64BitProcess
        SystemRoot       = $env:SystemRoot
        PowerShell       = $PSVersionTable.PSVersion.ToString()
        OS               = $os
        Services         = @($services)
        WinRTClasses     = @($winRtClasses)
        Registry         = @($registry)
        SystemFiles      = @($files)
        LoadedModules    = @($loadedModules)
        DiscoveryInvoked = $false
        ConfigureInvoked = $false
        StateChanging    = $false
    }
}
