function Export-WindowsDeviceLinkCsv {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [PSTypeName('Windows.DeviceLink.Information')]
        [psobject]$InputObject,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$DestinationPath,

        [ValidateRange(5, 600)]
        [int]$TimeoutSeconds = 120
    )

    process {
        try {
            $resolvedDestination = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($DestinationPath)
        }
        catch {
            throw "Invalid destination path '$DestinationPath': $($_.Exception.Message)"
        }

        if (Test-Path -LiteralPath $resolvedDestination) {
            $destinationItem = Get-Item -LiteralPath $resolvedDestination -ErrorAction Stop
            if (-not $destinationItem.PSIsContainer) {
                throw "Destination path '$DestinationPath' exists but is not a directory."
            }
            $destinationFolder = $destinationItem.FullName
        }
        else {
            New-Item -Path $resolvedDestination -ItemType Directory -Force -ErrorAction Stop | Out-Null
            $destinationFolder = (Get-Item -LiteralPath $resolvedDestination -ErrorAction Stop).FullName
        }

        function ConvertTo-SafeFileNamePart {
            param([string]$Value)

            if ([string]::IsNullOrWhiteSpace($Value)) {
                return 'Unknown'
            }

            $safe = $Value.Trim()
            foreach ($character in [IO.Path]::GetInvalidFileNameChars()) {
                $safe = $safe.Replace([string]$character, '-')
            }
            $safe = $safe -replace '\s+', '-'
            $safe = $safe -replace '-{2,}', '-'
            $safe.Trim('-', '.', ' ')
        }

        $nativeExportFolder = Join-Path -Path $destinationFolder -ChildPath ('.WindowsDeviceLinkExport-' + [Guid]::NewGuid().ToString('N'))
        New-Item -Path $nativeExportFolder -ItemType Directory -Force -ErrorAction Stop | Out-Null

        try {
            try {
                if ($InputObject.ActivationMode -eq 'RegisteredWinRT') {
                    $nativePath = [WinPEDeviceLink.Native.DeviceLinkClient]::ExportCsvRegistered($nativeExportFolder, $TimeoutSeconds)
                }
                else {
                    $nativePath = [WinPEDeviceLink.Native.DeviceLinkClient]::ExportCsv($InputObject.DllPath, $nativeExportFolder, $TimeoutSeconds)
                }
            }
            catch {
                $message = $_.Exception.Message
                if ($_.Exception.InnerException -and $_.Exception.InnerException.Message) {
                    $message = $_.Exception.InnerException.Message
                }
                throw "Native DeviceLink CSV export failed: $message"
            }

            if ([string]::IsNullOrWhiteSpace($nativePath)) {
                throw 'Native DeviceLink CSV export completed without identifying the created CSV file.'
            }

            $nativePath = [Environment]::ExpandEnvironmentVariables($nativePath)
            if (-not [IO.Path]::IsPathRooted($nativePath)) {
                $nativePath = Join-Path -Path $nativeExportFolder -ChildPath $nativePath
            }

            if (-not (Test-Path -LiteralPath $nativePath -PathType Leaf)) {
                throw "Windows returned DeviceLink CSV path '$nativePath', but the file was not found."
            }

            $serial = ConvertTo-SafeFileNamePart $InputObject.SerialNumber
            $manufacturer = ConvertTo-SafeFileNamePart $InputObject.Manufacturer
            $model = ConvertTo-SafeFileNamePart $InputObject.Model
            $date = [DateTime]::UtcNow.ToString('yyyy-MM-dd')
            $baseName = '{0}_{1}_{2}_{3}' -f $serial, $manufacturer, $model, $date
            $targetPath = Join-Path -Path $destinationFolder -ChildPath ($baseName + '.devicelink.csv')

            $suffix = 2
            while (Test-Path -LiteralPath $targetPath) {
                $targetPath = Join-Path -Path $destinationFolder -ChildPath ('{0}_{1}.devicelink.csv' -f $baseName, $suffix)
                $suffix++
            }

            Move-Item -LiteralPath $nativePath -Destination $targetPath -ErrorAction Stop
            Get-Item -LiteralPath $targetPath
        }
        finally {
            if (Test-Path -LiteralPath $nativeExportFolder) {
                Remove-Item -LiteralPath $nativeExportFolder -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
}
