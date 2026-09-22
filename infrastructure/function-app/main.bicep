@description('Short prefix used for generated Azure resource names.')
param namePrefix string = 'wdl'

@description('Azure region for all resources.')
param location string = resourceGroup().location

@description('Optional explicit Function App name. When empty, a name is generated from namePrefix.')
param functionAppName string = ''

@description('Optional explicit App Service Plan name. When empty, a name is generated from namePrefix.')
param appServicePlanName string = ''

@description('Optional explicit Storage Account name. When empty, a name is generated from namePrefix.')
param storageAccountName string = ''

@description('Optional explicit Key Vault name. When empty, a name is generated from namePrefix.')
param keyVaultResourceName string = ''

@description('Optional explicit Application Insights name. When empty, a name is generated from namePrefix.')
param applicationInsightsName string = ''

@description('Client ID of the multitenant Microsoft Entra application used for Microsoft Graph app-only authentication.')
param graphClientId string

@description('Allowed target tenant IDs, separated by commas or semicolons. Requests for all other tenants are rejected.')
param allowedTenantIds string

@description('Optional default tenant ID when the webhook request does not include tenantId.')
param defaultTenantId string = ''

@description('Optional JSON object mapping tenant IDs to friendly names used by the multitenant lookup endpoint.')
param tenantNamesJson string = '{}'

@description('Credential type used by the Function App for Microsoft Graph app-only authentication.')
@allowed([
  'Certificate'
  'ClientSecret'
])
param graphCredentialType string = 'Certificate'

@secure()
@description('Certificate: base64-encoded PFX. ClientSecret: application client secret. Stored in Key Vault.')
param graphCredential string

@secure()
@description('PFX password when graphCredentialType is Certificate. Leave empty for an unprotected PFX.')
param graphCertificatePassword string = ''

@secure()
@description('Shared webhook API key expected in X-WindowsDeviceLink-Key. Stored in Key Vault.')
param webhookApiKey string

var suffix = uniqueString(resourceGroup().id)
var generatedStorageName = take(toLower(replace('${namePrefix}${suffix}', '-', '')), 24)
var generatedFunctionAppName = take('${namePrefix}-func-${suffix}', 60)
var generatedPlanName = take('${namePrefix}-plan-${suffix}', 40)
var generatedAppInsightsName = take('${namePrefix}-appi-${suffix}', 260)
var generatedKeyVaultName = take(toLower(replace('${namePrefix}-kv-${suffix}', '_', '-')), 24)

var effectiveStorageName = empty(storageAccountName) ? generatedStorageName : storageAccountName
var effectiveFunctionAppName = empty(functionAppName) ? generatedFunctionAppName : functionAppName
var effectivePlanName = empty(appServicePlanName) ? generatedPlanName : appServicePlanName
var effectiveAppInsightsName = empty(applicationInsightsName) ? generatedAppInsightsName : applicationInsightsName
var effectiveKeyVaultName = empty(keyVaultResourceName) ? generatedKeyVaultName : keyVaultResourceName

var apiKeySecretName = 'windowsdevicelink-api-key'
var graphCredentialSecretName = graphCredentialType == 'Certificate'
  ? 'windowsdevicelink-graph-certificate-pfx'
  : 'windowsdevicelink-graph-client-secret'
var graphCertificatePasswordSecretName = 'windowsdevicelink-graph-certificate-password'

var functionScript = loadTextContent('../../function-app/Register-WindowsDeviceLink/run.ps1')
var functionConfigText = loadTextContent('../../function-app/Register-WindowsDeviceLink/function.json')
var lookupFunctionScript = loadTextContent('../../function-app/Lookup-WindowsDeviceLink/run.ps1')
var lookupFunctionConfigText = loadTextContent('../../function-app/Lookup-WindowsDeviceLink/function.json')
var backendAuthScript = loadTextContent('../../function-app/shared/BackendAuth.ps1')
var associationOperationsScript = loadTextContent('../../function-app/shared/AssociationOperations.ps1')
var reconcileFunctionScript = loadTextContent('../../function-app/Reconcile-WindowsDeviceLink/run.ps1')
var reconcileFunctionConfigText = loadTextContent('../../function-app/Reconcile-WindowsDeviceLink/function.json')

resource storage 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: effectiveStorageName
  location: location
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
    allowBlobPublicAccess: false
  }
}

resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: effectiveAppInsightsName
  location: location
  kind: 'web'
  properties: {
    Application_Type: 'web'
  }
}

resource plan 'Microsoft.Web/serverfarms@2024-04-01' = {
  name: effectivePlanName
  location: location
  sku: {
    name: 'Y1'
    tier: 'Dynamic'
  }
  properties: {
    reserved: false
  }
}

resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: effectiveKeyVaultName
  location: location
  properties: {
    tenantId: subscription().tenantId
    sku: {
      family: 'A'
      name: 'standard'
    }
    enableRbacAuthorization: true
    enableSoftDelete: true
    softDeleteRetentionInDays: 7
    publicNetworkAccess: 'Enabled'
  }
}

resource apiKeySecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: apiKeySecretName
  properties: {
    value: webhookApiKey
  }
}

resource graphCredentialSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: graphCredentialSecretName
  properties: {
    value: graphCredential
  }
}

resource graphCertificatePasswordSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = if (graphCredentialType == 'Certificate' && !empty(graphCertificatePassword)) {
  parent: keyVault
  name: graphCertificatePasswordSecretName
  properties: {
    value: graphCertificatePassword
  }
}

var storageConnectionString = 'DefaultEndpointsProtocol=https;AccountName=${storage.name};EndpointSuffix=${environment().suffixes.storage};AccountKey=${storage.listKeys().keys[0].value}'

resource functionApp 'Microsoft.Web/sites@2024-04-01' = {
  name: effectiveFunctionAppName
  location: location
  kind: 'functionapp'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    serverFarmId: plan.id
    httpsOnly: true
    siteConfig: {
      powerShellVersion: '7.4'
      minTlsVersion: '1.2'
      ftpsState: 'Disabled'
      appSettings: [
        {
          name: 'FUNCTIONS_EXTENSION_VERSION'
          value: '~4'
        }
        {
          name: 'FUNCTIONS_WORKER_RUNTIME'
          value: 'powershell'
        }
        {
          name: 'FUNCTIONS_WORKER_RUNTIME_VERSION'
          value: '7.4'
        }
        {
          name: 'AzureWebJobsStorage'
          value: storageConnectionString
        }
        {
          name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
          value: appInsights.properties.ConnectionString
        }
        {
          name: 'WINDOWSDEVICELINK_CLIENT_ID'
          value: graphClientId
        }
        {
          name: 'WINDOWSDEVICELINK_ALLOWED_TENANTS'
          value: allowedTenantIds
        }
        {
          name: 'WINDOWSDEVICELINK_DEFAULT_TENANT_ID'
          value: defaultTenantId
        }
        {
          name: 'WINDOWSDEVICELINK_TENANT_NAMES_JSON'
          value: tenantNamesJson
        }
        {
          name: 'WINDOWSDEVICELINK_API_KEY'
          value: '@Microsoft.KeyVault(SecretUri=${apiKeySecret.properties.secretUriWithVersion})'
        }
        {
          name: 'WINDOWSDEVICELINK_CERTIFICATE_PFX_BASE64'
          value: graphCredentialType == 'Certificate'
            ? '@Microsoft.KeyVault(SecretUri=${graphCredentialSecret.properties.secretUriWithVersion})'
            : ''
        }
        {
          name: 'WINDOWSDEVICELINK_CERTIFICATE_PASSWORD'
          value: graphCredentialType == 'Certificate' && !empty(graphCertificatePassword)
            ? '@Microsoft.KeyVault(SecretUri=${graphCertificatePasswordSecret.properties.secretUriWithVersion})'
            : ''
        }
        {
          name: 'WINDOWSDEVICELINK_CLIENT_SECRET'
          value: graphCredentialType == 'ClientSecret'
            ? '@Microsoft.KeyVault(SecretUri=${graphCredentialSecret.properties.secretUriWithVersion})'
            : ''
        }
      ]
    }
  }
}

resource keyVaultSecretsUser 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(keyVault.id, functionApp.id, 'Key Vault Secrets User')
  scope: keyVault
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '4633458b-17de-408a-b874-0445c86b69e6')
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

resource preassociateFunction 'Microsoft.Web/sites/functions@2024-04-01' = {
  parent: functionApp
  name: 'Register-WindowsDeviceLink'
  properties: {
    language: 'powershell'
    isDisabled: false
    config: json(functionConfigText)
    files: {
      'function.json': functionConfigText
      'run.ps1': functionScript
      'BackendAuth.ps1': backendAuthScript
      'AssociationOperations.ps1': associationOperationsScript
    }
  }
  dependsOn: [
    keyVaultSecretsUser
  ]
}



resource reconcileFunction 'Microsoft.Web/sites/functions@2024-04-01' = {
  parent: functionApp
  name: 'Reconcile-WindowsDeviceLink'
  properties: {
    language: 'powershell'
    isDisabled: false
    config: json(reconcileFunctionConfigText)
    files: {
      'function.json': reconcileFunctionConfigText
      'run.ps1': reconcileFunctionScript
      'BackendAuth.ps1': backendAuthScript
      'AssociationOperations.ps1': associationOperationsScript
    }
  }
  dependsOn: [
    keyVaultSecretsUser
  ]
}

resource lookupFunction 'Microsoft.Web/sites/functions@2024-04-01' = {
  parent: functionApp
  name: 'Lookup-WindowsDeviceLink'
  properties: {
    language: 'powershell'
    isDisabled: false
    config: json(lookupFunctionConfigText)
    files: {
      'function.json': lookupFunctionConfigText
      'run.ps1': lookupFunctionScript
      'BackendAuth.ps1': backendAuthScript
    }
  }
  dependsOn: [
    keyVaultSecretsUser
  ]
}

output functionAppName string = functionApp.name
output functionEndpoint string = 'https://${functionApp.properties.defaultHostName}/api/devicelink/preassociate'
output lookupEndpoint string = 'https://${functionApp.properties.defaultHostName}/api/devicelink/lookup'
output reconcileEndpoint string = 'https://${functionApp.properties.defaultHostName}/api/devicelink/reconcile'
output keyVaultName string = keyVault.name
output applicationInsightsName string = appInsights.name
