# Azure Function infrastructure

This folder contains the infrastructure-as-code for the WindowsDeviceLink Azure Function receiver.

## Files

- `main.bicep` - source infrastructure definition.
- `azuredeploy.json` - committed ARM template used by the Deploy to Azure button.
- `parameters.example.json` - non-secret example parameter structure.

The Bicep deployment uses `loadTextContent()` to embed the committed Function receiver files at deployment time.

## Deploy to Azure

[![Deploy to Azure](https://aka.ms/deploytoazurebutton)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Froryvossepoel%2FWindowsDeviceLink-Public%2Fmain%2Finfrastructure%2Ffunction-app%2Fazuredeploy.json)

## Regenerate ARM JSON

When `main.bicep` or the embedded Function source changes, regenerate and review `azuredeploy.json` before merging.

Example with Azure CLI/Bicep:

```powershell
az bicep build `
    --file .\infrastructure\function-app\main.bicep `
    --outfile .\infrastructure\function-app\azuredeploy.json
```

The committed JSON must remain suitable for the public Deploy to Azure button.

## Secrets

Do not place real values in a parameter file committed to the repository.

Secure deployment inputs are:

- `webhookApiKey`;
- `graphCredential`;
- `graphCertificatePassword`.

The deployment stores them in Key Vault and configures the Function App through Key Vault references.
