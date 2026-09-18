function Get-WindowsDeviceLinkDiscoveryPrerequisites {
    <#
    .SYNOPSIS
    Collects a read-only snapshot of prerequisites that may differ between full Windows and Windows PE.

    .DESCRIPTION
    This research command does not invoke DeviceLink discovery or configuration. It inventories
    selected services, WinRT registration locations, networking/crypto runtime files and basic
    environment information so results can be compared between full Windows and Windows PE.
    #>
    [CmdletBinding()]
    param()

    $environment = if (Test-Path -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Control\MiniNT') { 'WindowsPE' } else { 'Windows' }

    $items = New-Object System.Collections.Generic.List[object]

    function Add-ItemResult {
        param(
            [string]$Category,
            [string]$Name,
            [bool]$Present,
            [string]$State,
            [string]$Details
        )

        $items.Add([pscustomobject]@{
            PSTypeName  = 'Windows.DeviceLink.DiscoveryPrerequisite'
            Environment = $environment
            Category    = $Category
            Name        = $Name
            Present     = $Present
            State       = $State
            Details     = $Details
        })
    }

    foreach ($serviceName in @(
        'RpcSs',
        'DcomLaunch',
        'CryptSvc',
        'WinHttpAutoProxySvc',
        'BITS',
        'EventLog',
        'NlaSvc',
        'Dhcp',
        'Dnscache',
        'WManSvc',
        'dmwappushservice'
    )) {
        try {
            $service = Get-Service -Name $serviceName -ErrorAction Stop
            $startType = $null
            try {
                $serviceKey = "HKLM:\SYSTEM\CurrentControlSet\Services\$serviceName"
                $startValue = (Get-ItemProperty -LiteralPath $serviceKey -Name Start -ErrorAction Stop).Start
                $startType = switch ([int]$startValue) {
                    0 { 'Boot' }
                    1 { 'System' }
                    2 { 'Automatic' }
                    3 { 'Manual' }
                    4 { 'Disabled' }
                    default { [string]$startValue }
                }
            }
            catch { }

            Add-ItemResult -Category 'Service' -Name $serviceName -Present $true -State ([string]$service.Status) -Details $(if ($startType) { "Start=$startType" } else { $null })
        }
        catch {
            Add-ItemResult -Category 'Service' -Name $serviceName -Present $false -State $null -Details $null
        }
    }

    foreach ($className in @(
        'ModernDeployment.Autopilot.Core.DeviceLinkUtilities',
        'ModernDeployment.Autopilot.Core.DeviceLinkManager'
    )) {
        $paths = @(
            "HKLM:\SOFTWARE\Microsoft\WindowsRuntime\ActivatableClassId\$className",
            "HKLM:\SOFTWARE\Classes\ActivatableClasses\CLSID\$className"
        )

        $found = $false
        $foundPath = $null
        foreach ($path in $paths) {
            if (Test-Path -LiteralPath $path) {
                $found = $true
                $foundPath = $path
                break
            }
        }

        Add-ItemResult -Category 'WinRTRegistration' -Name $className -Present $found -State $(if ($found) { 'Registered' } else { 'NotFound' }) -Details $foundPath
    }

    foreach ($fileName in @(
        'Windows.Management.Service.dll',
        'winhttp.dll',
        'crypt32.dll',
        'bcrypt.dll',
        'ncrypt.dll',
        'tbs.dll',
        'webservices.dll',
        'combase.dll'
    )) {
        $path = Join-Path $env:SystemRoot "System32\$fileName"
        if (Test-Path -LiteralPath $path) {
            $file = Get-Item -LiteralPath $path
            Add-ItemResult -Category 'SystemFile' -Name $fileName -Present $true -State 'Present' -Details $file.VersionInfo.FileVersion
        }
        else {
            Add-ItemResult -Category 'SystemFile' -Name $fileName -Present $false -State 'Missing' -Details $null
        }
    }

    foreach ($regPath in @(
        'HKLM:\SOFTWARE\Microsoft\Provisioning',
        'HKLM:\SOFTWARE\Microsoft\Enrollments',
        'HKLM:\SOFTWARE\Microsoft\EnterpriseResourceManager'
    )) {
        Add-ItemResult -Category 'Registry' -Name $regPath -Present (Test-Path -LiteralPath $regPath) -State $(if (Test-Path -LiteralPath $regPath) { 'Present' } else { 'Missing' }) -Details $null
    }

    $items
}
