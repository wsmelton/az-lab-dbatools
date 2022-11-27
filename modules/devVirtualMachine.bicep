@description('The base value to use for generating the Virtual Machine.')
param baseName string

@description('The location to deploy the Virtual Machine. Defaults to Resource Group location')
param location string = resourceGroup().location

@description('The resourceId of teh subnet the NIC will join.')
param subnetId string

@description('Azure Sku name for the Virtual Machine. Defaults to Standard_D8s_v3')
param size string = 'Standard_D8s_v3'

@description('Username for the Virtual Machine local administrator account. Defaults to dbatools')
param adminUser string = 'dbatools'

@description('Provide the password for the local admin account')
@secure()
param adminPassword string

@description('Select the Timezone for the Virtual Machine.')
param vmTimezone string = ''

@description('Tags to assign to the resource')
param tags object

@description('File URI to script that will be executed on the Virtual Machine. Defaults to GitHub script of author.')
param cseFileUri string = 'https://raw.githubusercontent.com/wsmelton/az-lab-dbatools/main/scripts/devSetup.ps1'

var scriptFileName = last(split(cseFileUri, '/'))

var allTags = union({
  type: 'dev-vm'
  osType: 'Windows'
  osVersion: 'win11'
}, tags)

var imageReference = {
  offer: 'windows-11'
  publisher: 'microsoftwindowsdesktop'
  sku: 'win11-22h2-pro'
  version: 'latest'
}

var vmName = '${baseName}01'
var nicName = '${baseName}01-nic'
var osDiskName = '${baseName}01-osdisk'

resource networkInterface 'Microsoft.Network/networkInterfaces@2022-05-01' = {
  name: nicName
  location: location
  tags: allTags
  properties: {
    enableIPForwarding: false
    nicType: 'Standard'
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          primary: true
          subnet: {
            id: subnetId
          }
          privateIPAllocationMethod: 'Dynamic'
          privateIPAddressVersion: 'IPv4'
        }
      }
    ]
  }
}

resource virtualMachine 'Microsoft.Compute/virtualMachines@2022-08-01' = {
  name: vmName
  location: location
  tags: allTags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    hardwareProfile: {
      vmSize: size
    }
    licenseType: 'Windows_Client'
    storageProfile: {
      osDisk: {
        osType: 'Windows'
        name: osDiskName
        createOption: 'FromImage'
        caching: 'ReadWrite'
        deleteOption: 'Delete'
      }
      imageReference: imageReference
      dataDisks: []
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: resourceId('Microsoft.Network/networkInterfaces', nicName)
          properties: {
            deleteOption: 'Delete'
          }
        }
      ]
    }
    osProfile: {
      computerName: vmName
      adminPassword: adminPassword
      adminUsername: adminUser
      windowsConfiguration: {
        provisionVMAgent: true
        enableAutomaticUpdates: true
        patchSettings: {
          patchMode: 'AutomaticByOS'
          assessmentMode: 'ImageDefault'
          enableHotpatching: false
          automaticByPlatformSettings: {}
        }
        timeZone: empty(vmTimezone) ? null : vmTimezone
      }
    }
    diagnosticsProfile: {
      bootDiagnostics: {
        enabled: false
      }
    }
  }
  zones: [
    '1'
  ]
  dependsOn: [
    networkInterface
  ]
}

resource windowsVMExtensions 'Microsoft.Compute/virtualMachines/extensions@2022-08-01' = {
  parent: virtualMachine
  name: 'devScriptSetup'
  location: location
  properties: {
    publisher: 'Microsoft.Compute'
    type: 'CustomScriptExtension'
    typeHandlerVersion: '1.10'
    autoUpgradeMinorVersion: true
    settings: {
      fileUris: [
        cseFileUri
      ]
    }
    protectedSettings: {
      commandToExecute: 'powershell -ExecutionPolicy Bypass -file ${scriptFileName}'
    }
  }
}
