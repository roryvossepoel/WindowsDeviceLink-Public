function Get-WindowsDeviceLinkGraphCollection {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$Uri,
        [AllowNull()][string]$AccessToken,
        [switch]$SdkMode,
        [ValidateRange(1, 1000)][int]$MaxPages = 100,
        [ValidateRange(1, 5)][int]$MaxAttempts = 3,
        [scriptblock]$RequestScript,
        [scriptblock]$SleepScript
    )

    $records = @()
    $nextUri = $Uri
    $visited = @{}
    $pageNumber = 0

    while ($nextUri) {
        $pageNumber++
        if ($pageNumber -gt $MaxPages) {
            throw "Microsoft Graph paging exceeded the safety limit of $MaxPages pages."
        }

        if ($visited.ContainsKey($nextUri)) {
            throw "Microsoft Graph returned a repeated @odata.nextLink; paging was stopped to prevent a loop."
        }
        $visited[$nextUri] = $true

        $parsedUri = $null
        if (-not [uri]::TryCreate($nextUri, [UriKind]::Absolute, [ref]$parsedUri) -or
            $parsedUri.Scheme -ne 'https' -or
            $parsedUri.Host -ne 'graph.microsoft.com') {
            throw 'Microsoft Graph returned an invalid or unexpected @odata.nextLink.'
        }

        $requestParameters = @{ Uri=$nextUri; MaxAttempts=$MaxAttempts }
        if ($SdkMode) { $requestParameters.SdkMode = $true }
        else { $requestParameters.AccessToken = $AccessToken }
        if ($RequestScript) { $requestParameters.RequestScript = $RequestScript }
        if ($SleepScript) { $requestParameters.SleepScript = $SleepScript }
        $page = Invoke-WindowsDeviceLinkGraphGet @requestParameters

        if ($null -eq $page) {
            throw 'Microsoft Graph returned an empty response while paging Device Association records.'
        }

        $isDictionary = $page -is [System.Collections.IDictionary]
        $propertyNames = if ($isDictionary) { @($page.Keys) } else { @($page.PSObject.Properties.Name) }

        if ($propertyNames -notcontains 'value') {
            throw "Microsoft Graph returned a malformed Device Association collection response: the required 'value' property is missing."
        }

        $value = if ($isDictionary) { $page['value'] } else { $page.value }
        if ($null -eq $value) {
            # Some Microsoft Graph SDK response shapes represent an empty collection as
            # an explicitly present value key with a null value. Treat that as zero records.
            $value = @()
        }

        $records += @($value)

        $nextUri = $null
        if ($propertyNames -contains '@odata.nextLink') {
            $nextLink = if ($isDictionary) { $page['@odata.nextLink'] } else { $page.'@odata.nextLink' }
            if ($nextLink) { $nextUri = [string]$nextLink }
        }
    }

    @($records)
}
