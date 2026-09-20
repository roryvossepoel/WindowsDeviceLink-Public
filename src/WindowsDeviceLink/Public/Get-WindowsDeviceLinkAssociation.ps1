function Get-WindowsDeviceLinkAssociation {
    [CmdletBinding()]
    param(
        [ValidateNotNullOrEmpty()][string]$AssociationId,
        [ValidateNotNullOrEmpty()][string]$SerialNumber,
        [Parameter(Mandatory)]
        [ValidateSet('DeviceCode','Interactive','ClientSecret','AccessToken','Certificate','CertificateThumbprint','CertificateSubjectName','EnvironmentVariable','ManagedIdentity')]
        [string]$Method,
        [ValidateNotNullOrEmpty()][string]$TenantId,
        [ValidateNotNullOrEmpty()][string]$ClientId,
        [securestring]$AccessToken,
        [System.Security.Cryptography.X509Certificates.X509Certificate2]$Certificate,
        [ValidateNotNullOrEmpty()][string]$CertificateThumbprint,
        [ValidateNotNullOrEmpty()][string]$CertificateSubjectName,
        [bool]$SendCertificateChain = $false,
        [securestring]$ClientSecret,
        [ValidateNotNullOrEmpty()][string]$Environment = 'Global',
        [ValidateRange(1, 600)][double]$ClientTimeout = 100
    )

    if ([string]::IsNullOrWhiteSpace($AssociationId) -eq [string]::IsNullOrWhiteSpace($SerialNumber)) { throw 'Specify exactly one of -AssociationId or -SerialNumber.' }

    $allowedByMethod = @{
        DeviceCode=@('TenantId','ClientId'); Interactive=@('TenantId','ClientId'); ClientSecret=@('TenantId','ClientId','ClientSecret')
        AccessToken=@('TenantId','AccessToken'); Certificate=@('TenantId','ClientId','Certificate','SendCertificateChain')
        CertificateThumbprint=@('TenantId','ClientId','CertificateThumbprint','SendCertificateChain')
        CertificateSubjectName=@('TenantId','ClientId','CertificateSubjectName','SendCertificateChain'); EnvironmentVariable=@(); ManagedIdentity=@('ClientId')
    }
    $methodSpecificParameters = @('TenantId','ClientId','AccessToken','Certificate','CertificateThumbprint','CertificateSubjectName','SendCertificateChain','ClientSecret')
    $invalidParameters = $methodSpecificParameters | Where-Object { $PSBoundParameters.ContainsKey($_) -and $_ -notin $allowedByMethod[$Method] }
    if ($invalidParameters) { throw "The following parameters are not valid with -Method $Method`: $($invalidParameters -join ', ')." }

    switch ($Method) {
        'ClientSecret' { if(-not $TenantId -or -not $ClientId -or -not $PSBoundParameters.ContainsKey('ClientSecret')){throw '-TenantId, -ClientId, and -ClientSecret are required for -Method ClientSecret.'} }
        'AccessToken' { if(-not $PSBoundParameters.ContainsKey('AccessToken')){throw '-AccessToken is required for -Method AccessToken.'} }
        'Certificate' { if(-not $TenantId -or -not $ClientId -or -not $Certificate){throw '-TenantId, -ClientId, and -Certificate are required for -Method Certificate.'} }
        'CertificateThumbprint' { if(-not $TenantId -or -not $ClientId -or -not $CertificateThumbprint){throw '-TenantId, -ClientId, and -CertificateThumbprint are required for -Method CertificateThumbprint.'} }
        'CertificateSubjectName' { if(-not $TenantId -or -not $ClientId -or -not $CertificateSubjectName){throw '-TenantId, -ClientId, and -CertificateSubjectName are required for -Method CertificateSubjectName.'} }
        'EnvironmentVariable' {
            $missingVariables=@('AZURE_TENANT_ID','AZURE_CLIENT_ID','AZURE_CLIENT_SECRET')|Where-Object{-not [Environment]::GetEnvironmentVariable($_)}
            if($missingVariables){throw "-Method EnvironmentVariable requires environment variables: $($missingVariables -join ', ')."}
        }
    }

    $baseUri='https://graph.microsoft.com/beta'; $nativeAccessToken=$null; $sdkMode=$false
    if($Method -in @('DeviceCode','ClientSecret','EnvironmentVariable','AccessToken')){
        if($Environment -ne 'Global'){throw 'Native Device Association lookup currently supports the Global Microsoft cloud only.'}
        switch($Method){
            'DeviceCode'{$tokenParameters=@{};if($TenantId){$tokenParameters.TenantId=$TenantId};if($ClientId){$tokenParameters.ClientId=$ClientId};Write-Information -InformationAction Continue -MessageData 'Using native OAuth device-code authentication for Device Association lookup.';$token=Get-WindowsDeviceLinkDeviceCodeToken @tokenParameters;$nativeAccessToken=$token.AccessToken;$TenantId=$token.TenantId}
            'ClientSecret'{Write-Information -InformationAction Continue -MessageData 'Using native OAuth client-credentials authentication for Device Association lookup.';$token=Get-WindowsDeviceLinkClientSecretToken -TenantId $TenantId -ClientId $ClientId -ClientSecret $ClientSecret;$nativeAccessToken=$token.AccessToken}
            'EnvironmentVariable'{$environmentSecret=ConvertTo-SecureString $env:AZURE_CLIENT_SECRET -AsPlainText -Force;Write-Information -InformationAction Continue -MessageData 'Using native OAuth client-credentials authentication from environment variables for Device Association lookup.';$token=Get-WindowsDeviceLinkClientSecretToken -TenantId $env:AZURE_TENANT_ID -ClientId $env:AZURE_CLIENT_ID -ClientSecret $environmentSecret;$nativeAccessToken=$token.AccessToken;$TenantId=$env:AZURE_TENANT_ID}
            'AccessToken'{$credential=New-Object System.Management.Automation.PSCredential('token',$AccessToken);$nativeAccessToken=$credential.GetNetworkCredential().Password;if(-not $TenantId){$TenantId=Resolve-WindowsDeviceLinkAccessTokenTenantId -AccessToken $nativeAccessToken};$credential=$null}
        }
    } else {
        $connectParams=@{Environment=$Environment;ClientTimeout=$ClientTimeout}
        switch($Method){
            'Interactive'{if($TenantId){$connectParams.TenantId=$TenantId};if($ClientId){$connectParams.ClientId=$ClientId}}
            'Certificate'{$connectParams.TenantId=$TenantId;$connectParams.ClientId=$ClientId;$connectParams.Certificate=$Certificate;$connectParams.SendCertificateChain=$SendCertificateChain}
            'CertificateThumbprint'{$connectParams.TenantId=$TenantId;$connectParams.ClientId=$ClientId;$connectParams.CertificateThumbprint=$CertificateThumbprint;$connectParams.SendCertificateChain=$SendCertificateChain}
            'CertificateSubjectName'{$connectParams.TenantId=$TenantId;$connectParams.ClientId=$ClientId;$connectParams.CertificateSubjectName=$CertificateSubjectName;$connectParams.SendCertificateChain=$SendCertificateChain}
            'ManagedIdentity'{$connectParams.Identity=$true;if($ClientId){$connectParams.ClientId=$ClientId}}
        }
        Connect-WindowsDeviceLink @connectParams|Out-Null;$sdkMode=$true;$context=Get-MgContext;if($context -and $context.TenantId){$TenantId=$context.TenantId}
    }

    try {
        $graphReadParameters=@{};if($sdkMode){$graphReadParameters.SdkMode=$true}else{$graphReadParameters.AccessToken=$nativeAccessToken}

        if($AssociationId){
            $uri="$baseUri/deviceManagement/tenantAssociatedDevices/$AssociationId"
            $record=Invoke-WindowsDeviceLinkGraphGet -Uri $uri @graphReadParameters
            return ConvertTo-WindowsDeviceLinkAssociationResult -Record $record -TenantId $TenantId -ExpectedAssociationId $AssociationId
        }

        $escapedSerial=$SerialNumber.Replace("'","''")
        $filter=[uri]::EscapeDataString("serialNumber eq '$escapedSerial'")
        $uri="$baseUri/deviceManagement/tenantAssociatedDevices?`$filter=$filter"
        $filteredRecords=@(Get-WindowsDeviceLinkGraphCollection -Uri $uri @graphReadParameters)
        $records=@(Resolve-WindowsDeviceLinkSerialAssociationRecords -Records $filteredRecords -SerialNumber $SerialNumber)

        if($records.Count -eq 0){
            Write-Information -InformationAction Continue -MessageData 'Filtered serial-number lookup returned no exact match; retrying with client-side matching.'
            $allRecords=@(Get-WindowsDeviceLinkGraphCollection -Uri "$baseUri/deviceManagement/tenantAssociatedDevices" @graphReadParameters)
            $records=@(Resolve-WindowsDeviceLinkSerialAssociationRecords -Records $allRecords -SerialNumber $SerialNumber -RequireCompleteSerialCoverage)
        }

        if($records.Count -eq 0){Write-Information -InformationAction Continue -MessageData 'No Device Association record was found.';return}

        ConvertTo-WindowsDeviceLinkAssociationResult -Record $records[0] -TenantId $TenantId -ExpectedSerialNumber $SerialNumber
    } catch {
        $statusCode=$null;try{$statusCode=[int]$_.Exception.Response.StatusCode}catch{}
        if($null -eq $statusCode -and $_.Exception.Message -match '(?<!\d)404(?!\d)'){$statusCode=404}
        if($AssociationId -and $statusCode -eq 404){Write-Information -InformationAction Continue -MessageData 'No Device Association record was found.';return}
        throw
    } finally {$nativeAccessToken=$null}
}
