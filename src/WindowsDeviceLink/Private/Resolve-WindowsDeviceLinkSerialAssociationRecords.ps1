function Resolve-WindowsDeviceLinkSerialAssociationRecords {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$Records,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$SerialNumber,

        [switch]$RequireCompleteSerialCoverage
    )

    $matches = @($Records | Where-Object { [string]$_.serialNumber -eq [string]$SerialNumber })

    if ($matches.Count -gt 1) {
        throw "Multiple Device Association records were returned for serial number '$SerialNumber'. Use -AssociationId to select an exact record."
    }

    if ($matches.Count -eq 0 -and $RequireCompleteSerialCoverage) {
        $recordsWithoutSerial = @($Records | Where-Object { [string]::IsNullOrWhiteSpace([string]$_.serialNumber) })
        if ($recordsWithoutSerial.Count -gt 0) {
            throw "Microsoft Graph returned one or more Device Association records without serialNumber; absence of serial number '$SerialNumber' cannot be confirmed safely."
        }
    }

    @($matches)
}
