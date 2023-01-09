@description('Required. Provide the name of the Key Vault. Defaults to kv-dbatools-lab')
param baseName string

@description('Optional. The location to deploy the Virtual Machine. Defaults to Resource Group location. Default: resourceGroup().location')
param location string = resourceGroup().location

@description('Required. Tags to assign to the resource')
param tags object

@description('Required. Local Admin username')
param adminUser string

@description('Required. Local Administrator password')
@secure()
param adminPassword string

@description('Required. User objectId to grant KV Administrator for Key Vault')
param userId string

@description('Adding some standard tags')
var allTags = union({
  type: 'secrets'
}, tags)

resource keyVault 'Microsoft.KeyVault/vaults@2022-07-01' = {
  name: '${baseName}${take(uniqueString(resourceGroup().name, baseName, subscription().displayName),5)}'
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

var roleDefinitionId = '00482a5a-887f-4fb3-b363-3b7fe8e74483'
var roleAssignmentName = guid(userId, roleDefinitionId, resourceGroup().id)

resource kvRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: roleAssignmentName
  scope: keyVault
  properties: {
    roleDefinitionId: resourceId('Microsoft.Authorization/roleDefinitions', roleDefinitionId)
    principalId: userId
  }
}

resource vmAdminSecret 'Microsoft.KeyVault/vaults/secrets@2022-07-01' = {
  name: adminUser
  parent: keyVault
  properties: {
    value: adminPassword
  }
  tags: union({
    purpose: 'admin account'
  },tags)
}

@description('Key Vault name')
output name string = keyVault.name

@description('Key Vault Resource ID')
output id string = keyVault.id

@description('Local Administrator Account Secret name')
output secretName string = vmAdminSecret.name

metadata repository = {
  author: 'Shawn Melton'
  source: 'https://github.com/wsmelton/az-lab-dbatools'
  module: 'keyVault.bicep'
}
