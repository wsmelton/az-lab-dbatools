@description('Provide the name of the Key Vault. Defaults to kv-dbatools-lab')
param baseName string

@description('The location to deploy the Virtual Machine. Defaults to Resource Group location')
param location string = resourceGroup().location

@description('Tags to assign to the resource')
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

resource bastionSubnet 'Microsoft.Network/virtualnetworks/subnets@2015-06-15' existing = {
  name: 'AzureBastionSubnet'
  parent: virtualNetwork
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
    publicIPAllocationMethod: 'Dynamic'
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
            id: bastionSubnet.id
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
