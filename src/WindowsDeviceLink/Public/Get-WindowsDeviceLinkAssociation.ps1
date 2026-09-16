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
        'DeviceCode' { if(-not $TenantId){throw '-TenantId is required for -Method DeviceCode.'} }
        'Interactive' { if(-not $TenantId){throw '-TenantId is required for -Method Interactive.'} }
        'ClientSecret' { if(-not $TenantId -or -not $ClientId -or -not $PSBoundParameters.ContainsKey('ClientSecret')){throw '-TenantId, -ClientId, and -ClientSecret are required for -Method ClientSecret.'} }
        'AccessToken' { if(-not $TenantId -or -not $PSBoundParameters.ContainsKey('AccessToken')){throw '-TenantId and -AccessToken are required for -Method AccessToken.'} }
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
            'DeviceCode'{$tokenParameters=@{TenantId=$TenantId};if($ClientId){$tokenParameters.ClientId=$ClientId};Write-Information -InformationAction Continue -MessageData 'Using native OAuth device-code authentication for Device Association lookup.';$token=Get-WindowsDeviceLinkDeviceCodeToken @tokenParameters;$nativeAccessToken=$token.AccessToken}
            'ClientSecret'{Write-Information -InformationAction Continue -MessageData 'Using native OAuth client-credentials authentication for Device Association lookup.';$token=Get-WindowsDeviceLinkClientSecretToken -TenantId $TenantId -ClientId $ClientId -ClientSecret $ClientSecret;$nativeAccessToken=$token.AccessToken}
            'EnvironmentVariable'{$environmentSecret=ConvertTo-SecureString $env:AZURE_CLIENT_SECRET -AsPlainText -Force;Write-Information -InformationAction Continue -MessageData 'Using native OAuth client-credentials authentication from environment variables for Device Association lookup.';$token=Get-WindowsDeviceLinkClientSecretToken -TenantId $env:AZURE_TENANT_ID -ClientId $env:AZURE_CLIENT_ID -ClientSecret $environmentSecret;$nativeAccessToken=$token.AccessToken;$TenantId=$env:AZURE_TENANT_ID}
            'AccessToken'{$credential=New-Object System.Management.Automation.PSCredential('token',$AccessToken);$nativeAccessToken=$credential.GetNetworkCredential().Password;$credential=$null}
        }
    } else {
        $connectParams=@{Environment=$Environment;ClientTimeout=$ClientTimeout}
        switch($Method){
            'Interactive'{$connectParams.TenantId=$TenantId;if($ClientId){$connectParams.ClientId=$ClientId}}
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
            if($null -eq $record){throw "Microsoft Graph returned an empty response for Device Association '$AssociationId'; lookup result is indeterminate."}
            if([string]::IsNullOrWhiteSpace([string]$record.id) -or [string]$record.id -eq [guid]::Empty.ToString()){throw "Microsoft Graph returned a malformed Device Association record for '$AssociationId': association ID is missing or empty."}
            if([string]$record.id -ne [string]$AssociationId){throw "Microsoft Graph returned a mismatched Device Association record. Requested ID '$AssociationId', received '$($record.id)'."}
            $records=@($record)
        } else {
            $escapedSerial=$SerialNumber.Replace("'","''");$filter=[uri]::EscapeDataString("serialNumber eq '$escapedSerial'");$uri="$baseUri/deviceManagement/tenantAssociatedDevices?`$filter=$filter"
            $filteredRecords=@(Get-WindowsDeviceLinkGraphCollection -Uri $uri @graphReadParameters)
            $records=@($filteredRecords|Where-Object{[string]$_.serialNumber -eq [string]$SerialNumber})
            if($records.Count -eq 0){
                Write-Information -InformationAction Continue -MessageData 'Filtered serial-number lookup returned no exact match; retrying with client-side matching.'
                $allRecords=@(Get-WindowsDeviceLinkGraphCollection -Uri "$baseUri/deviceManagement/tenantAssociatedDevices" @graphReadParameters)
                $records=@($allRecords|Where-Object{[string]$_.serialNumber -eq [string]$SerialNumber})
                if($records.Count -eq 0){
                    $recordsWithoutSerial=@($allRecords|Where-Object{[string]::IsNullOrWhiteSpace([string]$_.serialNumber)})
                    if($recordsWithoutSerial.Count -gt 0){throw "Microsoft Graph returned one or more Device Association records without serialNumber; absence of serial number '$SerialNumber' cannot be confirmed safely."}
                }
            }
            if($records.Count -gt 1){throw "Multiple Device Association records were returned for serial number '$SerialNumber'. Use -AssociationId to select an exact record."}
        }
        if($records.Count -eq 0){Write-Information -InformationAction Continue -MessageData 'No Device Association record was found.';return}
        foreach($record in $records){
            if([string]::IsNullOrWhiteSpace([string]$record.id) -or [string]$record.id -eq [guid]::Empty.ToString()){throw 'Microsoft Graph returned a malformed Device Association record: association ID is missing or empty.'}
            if([string]::IsNullOrWhiteSpace([string]$record.associationState)){throw "Microsoft Graph returned a malformed Device Association record '$($record.id)': associationState is missing or empty."}

            $managedDeviceId=if([string]::IsNullOrWhiteSpace([string]$record.managedDeviceId) -or [string]$record.managedDeviceId -eq [guid]::Empty.ToString()){$null}else{[string]$record.managedDeviceId}
            $devicePreparationPolicyId=if([string]::IsNullOrWhiteSpace([string]$record.devicePreparationPolicyId) -or [string]$record.devicePreparationPolicyId -eq [guid]::Empty.ToString()){$null}else{[string]$record.devicePreparationPolicyId}

            [pscustomobject]@{
                PSTypeName='Windows.DeviceLink.Association';Id=[string]$record.id;TenantId=$TenantId;ManagedDeviceId=$managedDeviceId;ManagedDeviceName=$record.managedDeviceName
                SerialNumber=$record.serialNumber;SmbiosUuid=$record.smbiosUuid;Manufacturer=$record.manufacturerName;Model=$record.modelName;AssociationState=[string]$record.associationState
                PreassociationDateTime=$record.preassociationDateTime;AssociationDateTime=$record.associationDateTime;EnrolledDateTime=$record.enrolledDateTime;LastContactedDateTime=$record.lastContactedDateTime
                PreassociatedByUserPrincipalName=$record.preassociatedByUserPrincipalName;AssignedToUserPrincipalName=$record.assignedToUserPrincipalName
                DevicePreparationPolicyId=$devicePreparationPolicyId;DevicePreparationPolicyAssignedDateTime=$record.devicePreparationPolicyAssignedDateTime
            }
        }
    } catch {
        $statusCode=$null;try{$statusCode=[int]$_.Exception.Response.StatusCode}catch{}
        if($null -eq $statusCode -and $_.Exception.Message -match '(?<!\d)404(?!\d)'){$statusCode=404}
        if($AssociationId -and $statusCode -eq 404){Write-Information -InformationAction Continue -MessageData 'No Device Association record was found.';return}
        throw
    } finally {$nativeAccessToken=$null}
}
