# Azure Function infrastructure

This folder contains the infrastructure-as-code for the WindowsDeviceLink Azure Function receiver.

## Files

- `main.bicep` - source infrastructure definition.
- `azuredeploy.json` - generated ARM template retained for infrastructure development.
- `parameters.example.json` - non-secret example parameter structure.

The Bicep deployment uses `loadTextContent()` to embed the committed Function receiver files at deployment time.

## Experimental status

The Bicep/ARM route is not a supported deployment method for `0.10.0-preview1`. Use the
supplied Function App package and documented manual Azure configuration for the preview.
Clean deployment, safe redeployment, secret preservation and the public Deploy to Azure
experience are tracked in
[issue #43](https://github.com/roryvossepoel/WindowsDeviceLink-Public/issues/43).

## Resource naming

By default, the public deployment can generate resource names from `namePrefix`.

Organizations with strict naming standards can instead provide explicit names for each resource:

- `functionAppName`
- `appServicePlanName`
- `storageAccountName`
- `keyVaultResourceName`
- `applicationInsightsName`

When an explicit name is supplied, it takes precedence over the generated `namePrefix` value for that resource.

Example enterprise naming:

```text
Resource Group         mgtnl80rg01osd
Function App           mgtnl80fa01osd
App Service Plan       mgtnl80asp01osd
Storage Account        mgtnl80sa01osd
Key Vault              mgtnl80kv01osd
Application Insights   mgtnl80ai01osd
```

The Resource Group is selected/created outside the template. The other five names are deployment parameters.

## Regenerate ARM JSON

When `main.bicep` or the embedded Function source changes, regenerate and review `azuredeploy.json` before merging.

Example with Azure CLI/Bicep:

```powershell
az bicep build `
    --file .\infrastructure\function-app\main.bicep `
    --outfile .\infrastructure\function-app\azuredeploy.json
```

The committed JSON must remain synchronized with the reviewed Bicep source. Suitability
for a public Deploy to Azure button requires the end-to-end validation tracked in issue
#43.

## Secrets

Do not place real values in a parameter file committed to the repository.

Secure deployment inputs are:

- `webhookApiKey`;
- `graphCredential`;
- `graphCertificatePassword`.

The deployment stores them in Key Vault and configures the Function App through Key Vault references.
