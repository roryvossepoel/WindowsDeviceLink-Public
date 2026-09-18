@description('Azure region for the Automation Account.')
param location string = resourceGroup().location

@description('Azure Automation Account name.')
param automationAccountName string = 'wdl-automation'

@description('Runtime Environment name.')
param runtimeEnvironmentName string = 'WindowsDeviceLink-PS74'

@description('Runbook name.')
param runbookName string = 'Register-WindowsDeviceLinkWebhook'

@description('Microsoft.Graph.Authentication version to import into the Runtime Environment.')
param graphAuthenticationVersion string = '2.39.0'

@description('Optional default tenant ID used when the webhook request omits tenantId.')
param defaultTenantId string = ''

@secure()
@description('Shared webhook API key stored as an encrypted Automation Variable.')
param webhookApiKey string

@description('JSON mapping of tenant IDs to runbook authentication configuration. Leave {} for a single-tenant Managed Identity deployment.')
param tenantConfigurationJson string = '{}'

@description('Optional base64 PFX to upload as an Automation certificate asset for cross-tenant certificate authentication.')
@secure()
param certificateBase64 string = ''

@description('Automation certificate asset name used by WindowsDeviceLinkTenantConfiguration.')
param certificateAssetName string = 'WindowsDeviceLinkBackend'

@description('Certificate thumbprint. Required when certificateBase64 is supplied.')
param certificateThumbprint string = ''

var graphPackageUri = 'https://www.powershellgallery.com/api/v2/package/Microsoft.Graph.Authentication/${graphAuthenticationVersion}'
var runbookUri = 'https://raw.githubusercontent.com/roryvossepoel/WindowsDeviceLink-Public/main/runbooks/Register-WindowsDeviceLinkWebhook.ps1'

resource automation 'Microsoft.Automation/automationAccounts@2024-10-23' = {
  name: automationAccountName
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    publicNetworkAccess: true
    sku: {
      name: 'Basic'
    }
  }
}

resource runtime 'Microsoft.Automation/automationAccounts/runtimeEnvironments@2024-10-23' = {
  parent: automation
  name: runtimeEnvironmentName
  location: location
  properties: {
    description: 'WindowsDeviceLink PowerShell 7.4 runtime'
    runtime: {
      language: 'PowerShell'
      version: '7.4'
    }
    defaultPackages: {}
  }
}

resource graphAuthPackage 'Microsoft.Automation/automationAccounts/runtimeEnvironments/packages@2024-10-23' = {
  parent: runtime
  name: 'Microsoft.Graph.Authentication'
  allOf: {
    location: location
    tags: {}
  }
  properties: {
    contentLink: {
      uri: graphPackageUri
      version: graphAuthenticationVersion
    }
  }
}

resource runbook 'Microsoft.Automation/automationAccounts/runbooks@2024-10-23' = {
  parent: automation
  name: runbookName
  location: location
  properties: {
    description: 'WindowsDeviceLink webhook receiver for Device Association pre-association.'
    logProgress: false
    logVerbose: false
    runbookType: 'PowerShell'
    runtimeEnvironment: runtime.name
    publishContentLink: {
      uri: runbookUri
      version: '1.0'
    }
  }
  dependsOn: [
    graphAuthPackage
  ]
}

resource defaultTenantVariable 'Microsoft.Automation/automationAccounts/variables@2024-10-23' = {
  parent: automation
  name: 'WindowsDeviceLinkDefaultTenantId'
  properties: {
    description: 'Optional default target tenant ID.'
    isEncrypted: false
    value: defaultTenantId
  }
}

resource apiKeyVariable 'Microsoft.Automation/automationAccounts/variables@2024-10-23' = {
  parent: automation
  name: 'WindowsDeviceLinkWebhookApiKey'
  properties: {
    description: 'Shared webhook API key expected in X-WindowsDeviceLink-Key.'
    isEncrypted: true
    value: webhookApiKey
  }
}

resource tenantConfigurationVariable 'Microsoft.Automation/automationAccounts/variables@2024-10-23' = {
  parent: automation
  name: 'WindowsDeviceLinkTenantConfiguration'
  properties: {
    description: 'Tenant routing/authentication JSON used by the WindowsDeviceLink webhook runbook.'
    isEncrypted: false
    value: tenantConfigurationJson
  }
}

resource certificate 'Microsoft.Automation/automationAccounts/certificates@2024-10-23' = if (!empty(certificateBase64)) {
  parent: automation
  name: certificateAssetName
  properties: {
    base64Value: certificateBase64
    description: 'WindowsDeviceLink backend certificate for cross-tenant Graph authentication.'
    isExportable: false
    thumbprint: certificateThumbprint
  }
}

output automationAccountName string = automation.name
output runtimeEnvironmentName string = runtime.name
output runbookName string = runbook.name
output managedIdentityPrincipalId string = automation.identity.principalId
output webhookCreationRequired bool = true
