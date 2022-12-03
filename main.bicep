@description('The base value to use for generating the Virtual Machine.')
param baseName string

@description('Email address to use for auto-shutdown notification')
param emailAddress string = ''

@description('Number of Virtual Machines to create for SQL 2022 and 2019. These will be created on Windows Server 2022. Defaults to 1')
param vmCount int = 1

@description('The location to deploy the Virtual Machine. Defaults to Resource Group location')
param location string = resourceGroup().location

@description('Select the Timezone for the Virtual Machines.')
param timezone string = 'Central Standard Time'

@description('User ObjectID to grant Key Vault Administrator role on the Key Vault deployed')
param userId string

@description('Tags to assign to the resource')
param tags object

@description('Username for the Virtual Machine local administrator account. Defaults to dbatools')
param adminUser string

@description('Provide the password for the local admin account')
@secure()
param adminPassword string

var deploymentName = take(deployment().name, 34)

module kv 'modules/keyvault.bicep' = {
  name: '${deploymentName}_keyvault'
  params: {
    location: location
    tags: tags
    baseName: baseName
    adminPassword: adminPassword
    adminUser: adminUser
    userId: userId
  }
}

module network 'modules/virtualNetwork.bicep' = {
  name: '${deploymentName}_network'
  params: {
    location: location
    tags: tags
    baseName: baseName
  }
}

resource secrets 'Microsoft.KeyVault/vaults@2022-07-01' existing = {
  name: kv.outputs.name
  scope: resourceGroup()
}

module devVm 'modules/devVirtualMachine.bicep' = {
  name: '${deploymentName}_dev-vm'
  params: {
    location: location
    tags: tags
    vmTimezone: timezone
    adminUser: adminUser
    adminPassword: secrets.getSecret(kv.outputs.secretName)
    baseName: baseName
    vnetName: network.outputs.name
    subnetName: 'default'
  }
  dependsOn: [
    network
  ]
}

module sql2022OS22Vm 'modules/sqlVirtualMachine.bicep' = {
  name: '${deploymentName}_sql22vms'
  params: {
    location: location
    tags: tags
    vmTimezone: timezone
    emailNotification: emailAddress
    adminUser: adminUser
    adminPassword: secrets.getSecret(kv.outputs.secretName)
    baseName: baseName
    offer: 'sql2022-ws2022'
    count: vmCount
    vnetName: network.outputs.name
    subnetName: 'default'
  }
  dependsOn: [
    network
  ]
}

module sql2019OS22Vm 'modules/sqlVirtualMachine.bicep' = {
  name: '${deploymentName}_sql19vms'
  params: {
    location: location
    tags: tags
    vmTimezone: timezone
    emailNotification: emailAddress
    adminUser: adminUser
    adminPassword: secrets.getSecret(kv.outputs.secretName)
    baseName: baseName
    offer: 'sql2019-ws2022'
    count: vmCount
    vnetName: network.outputs.name
    subnetName: 'default'
  }
  dependsOn: [
    network
  ]
}

metadata repository = {
  author: 'Shawn Melton'
  source: 'https://github.com/wsmelton/az-lab-dbatools'
  module: 'main.bicep'
}

@description('Developer VM name')
output devVmName string = devVm.outputs.name

@description('Array of the SQL Server 2019 VMs')
output sqlVm2022 array = sql2022OS22Vm.outputs.vmDetails

@description('Array of the SQL Server 2022 VMs')
output sqlVm2019 array = sql2019OS22Vm.outputs.vmDetails

@description('Key Vault name')
output keyVaultName string = kv.outputs.name

@description('VNET name')
output vnetName string = network.outputs.name

@description('Bastion name')
output bastionHost string = network.outputs.bastionHostName
