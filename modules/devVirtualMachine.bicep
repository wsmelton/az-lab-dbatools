@description('The base value to use for generating the Virtual Machine.')
param baseName string

@description('Time to automatically shutdown the VM each day. Defaults to 7PM')
param autoShutdownTime string = '1900'

@description('Email address to use for shutdown notification. If not provided no notification will be sent prior to shutdown.')
param emailNotification string = ''

@description('The location to deploy the Virtual Machine. Defaults to Resource Group location')
param location string = resourceGroup().location

@description('The name of the Virtual Network.')
param vnetName string

@description('The name of the subnet for the Virtual Machine NIC.')
param subnetName string

@description('Azure Sku name for the Virtual Machine. If you want to use Docker, ensure you pick a sku that supports it. Defaults to Standard_D8s_v3')
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

@description('Get the script name')
var scriptFileName = last(split(cseFileUri, '/'))

@description('Adding some standard tags for VMs')
var allTags = union({
    type: 'dev-vm'
    osType: 'Windows'
    osVersion: 'win11'
  }, tags)

@description('Setting some default values for the image configuration')
var imageReference = {
  offer: 'windows-11'
  publisher: 'microsoftwindowsdesktop'
  sku: 'win11-22h2-pro'
  version: 'latest'
}

@description('Create the notification settings if emailNotification is provided')
var notifySettings = empty(emailNotification) ? {} : {
  timeInMinutes: 15
  status: 'Enabled'
  emailRecipient: emailNotification
  notificationLocale: 'en'
}

@description('Standardize name of VM')
var vmName = '${baseName}win1101'

@description('Standardize name of Network Interface')
var nicName = '${baseName}01-nic'

@description('Standardize name of OS Disk')
var osDiskName = '${baseName}01-osdisk'

resource network 'Microsoft.Network/virtualNetworks@2022-05-01' existing = {
  name: vnetName
}
resource subnet 'Microsoft.Network/virtualNetworks/subnets@2022-05-01' existing = {
  name: subnetName
  parent: network
}

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
            id: subnet.id
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

resource vmAutoShutdown 'Microsoft.DevTestLab/schedules@2018-09-15' = {
  name: any('shutdown-computevm-${vmName}')
  location: location
  tags: tags
  properties: {
    status: empty(autoShutdownTime) ? 'Disabled' : 'Enabled'
    taskType: 'ComputeVmShutdownTask'
    dailyRecurrence: {
      time: autoShutdownTime
    }
    timeZoneId: vmTimezone
    notificationSettings: notifySettings
    targetResourceId: virtualMachine.id
  }
}

@description('Name and IP Address of the Virtual Machine')
output vmDetails array = [
  {
    name: virtualMachine.name
    ipAddress: networkInterface.properties.ipConfigurations[0].properties.privateIPAddress
  }
]

metadata repository = {
  author: 'Shawn Melton'
  source: 'https://github.com/wsmelton/az-lab-dbatools'
  module: 'devVirtualMachine.bicep'
}
