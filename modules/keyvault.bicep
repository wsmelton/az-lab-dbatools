@description('Provide the name of the Key Vault. Defaults to kv-dbatools-lab')
param baseName string

@description('The location to deploy the Virtual Machine. Defaults to Resource Group location')
param location string = resourceGroup().location

@description('Tags to assign to the resource')
param tags object

@description('Adding some standard tags')
var allTags = union({
  type: 'secrets'
}, tags)

resource keyVault 'Microsoft.KeyVault/vaults@2022-07-01' = {
  name: '${baseName}${take(uniqueString(resourceGroup().name),5)}'
  location: location
  tags: allTags
  properties: {
    tenantId: subscription().tenantId
    createMode: 'default'
    enabledForDeployment: true
    enabledForTemplateDeployment: true
    enableRbacAuthorization: true
    accessPolicies: []
    sku: {
      name: 'standard'
      family: 'A'
    }
  }
}

@description('Key Vault name')
output name string = keyVault.name

metadata repository = {
  author: 'Shawn Melton'
  source: 'https://github.com/wsmelton/az-lab-dbatools'
  module: 'keyVault.bicep'
}
