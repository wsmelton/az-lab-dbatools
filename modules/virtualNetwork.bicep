@description('Required. Provide the name of the Key Vault. Defaults to kv-dbatools-lab')
param baseName string

@description('Optional. The location to deploy the Virtual Machine. Default: resourceGroup().location')
param location string = resourceGroup().location

@description('Required. Tags to assign to the resource')
param tags object

@description('Adding some standard tags')
var allTags = union({
  type: 'networking'
}, tags)

resource nsgDefault 'Microsoft.Network/networkSecurityGroups@2022-05-01' = {
  name: 'default'
  location: location
  tags: tags
  properties: {}
}

resource virtualNetwork 'Microsoft.Network/virtualNetworks@2022-05-01' = {
  name: baseName
  location: location
  tags: allTags
  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.0.0.0/16'
      ]
    }
    subnets: [
      {
        name: 'default'
        properties: {
          addressPrefix: '10.0.1.0/24'
          networkSecurityGroup: {
            id: nsgDefault.id
          }
        }
      }
      {
        name: 'AzureBastionSubnet'
        properties: {
          addressPrefix: '10.0.0.0/26'
          privateEndpointNetworkPolicies: 'Disabled'
          privateLinkServiceNetworkPolicies: 'Enabled'
        }
      }
    ]
  }
}

resource bastionPip 'Microsoft.Network/publicIPAddresses@2022-05-01' = {
  name: 'pip-bastion-dbatools'
  location: location
  tags: tags
  sku: {
    name: 'Standard'
    tier: 'Regional'
  }
  properties: {
    publicIPAddressVersion: 'IPv4'
    publicIPAllocationMethod: 'Static'
  }
}

resource bastionService 'Microsoft.Network/bastionHosts@2022-05-01' = {
  name: baseName
  location: location
  tags: tags
  sku: {
    name: 'Basic'
  }
  properties: {
    disableCopyPaste: false
    ipConfigurations: [
      {
        name: 'ipconfig'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          publicIPAddress: {
            id: bastionPip.id
          }
          subnet: {
            id: resourceId('Microsoft.Network/virtualNetworks/subnets', virtualNetwork.name, 'AzureBastionSubnet')
          }
        }
      }
    ]
  }
}

@description('Virtual Network name')
output name string = virtualNetwork.name

@description('Bastion Host name')
output bastionHostName string = bastionService.name

metadata repository = {
  author: 'Shawn Melton'
  source: 'https://github.com/wsmelton/az-lab-dbatools'
  module: 'virtualNetwork.bicep'
}
