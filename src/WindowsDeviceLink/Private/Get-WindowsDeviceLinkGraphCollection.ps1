function Get-WindowsDeviceLinkGraphCollection {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$Uri,
        [AllowNull()][string]$AccessToken,
        [switch]$SdkMode,
        [ValidateRange(1, 1000)][int]$MaxPages = 100,
        [ValidateRange(1, 5)][int]$MaxAttempts = 3
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
        $page = Invoke-WindowsDeviceLinkGraphGet @requestParameters

        if ($null -eq $page) {
            throw 'Microsoft Graph returned an empty response while paging Device Association records.'
        }

        if ($page.PSObject.Properties.Name -contains 'value' -and $null -ne $page.value) {
            $records += @($page.value)
        }

        $nextUri = $null
        if ($page.PSObject.Properties.Name -contains '@odata.nextLink' -and $page.'@odata.nextLink') {
            $nextUri = [string]$page.'@odata.nextLink'
        }
    }

    @($records)
}
