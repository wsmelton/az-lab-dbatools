@description('Required. The base value to use for generating the Virtual Machine.')
param baseName string

@description('Optional. Number of Virtual Machines to create. Defaults to 1')
param count int = 1

@description('Optional. Time to automatically shutdown the VM each day. Defaults to 7PM')
param autoShutdownTime string = '1900'

@description('Optional. Email address to use for shutdown notification. If not provided no notification will be sent prior to shutdown. Default: empty')
param emailNotification string = ''

@description('Optional. The location to deploy the Virtual Machine. Default: resourceGroup().location')
param location string = resourceGroup().location

@description('Required. The name of the Virtual Network.')
param vnetName string

@description('Required. The name of the subnet for the Virtual Machine NIC.')
param subnetName string

@description('Optional. Enable accelerated networking feature on the Virtual Machine NIC. Defaults to false.')
param acceleratedNetworking bool = false

@description('Optional. Azure Sku name for the Virtual Machine. Defaults to Standard_B4ms')
param size string = 'Standard_B4ms'

@description('Optional. Username for the Virtual Machine local administrator account. Defaults to dbatools')
param adminUser string = 'dbatools'

@description('Required. Provide the password for the local admin account')
@secure()
param adminPassword string

@description('Optional. Provide the storage account type to use for the OS disk. Defaults to StandardSSD_LRS')
@allowed([
  'Premium_LRS'
  'Premium_ZRS'
  'StandardSSD_LRS'
  'StandardSSD_ZRS'
  'Standard_LRS'
])
param osDiskType string = 'StandardSSD_LRS'

@description('Optional. Provide the storage account type to use for any data disk added. Defaults to StandardSSD_LRS')
@allowed([
  'Premium_LRS'
  'Premium_ZRS'
  'StandardSSD_LRS'
  'StandardSSD_ZRS'
  'Standard_LRS'
])
param dataDiskType string = 'StandardSSD_LRS'

@description('Required. Select the offer of the marketplace image to create a SQL Server Virtual Machine. Will deploy SQL Server Developer Edition')
@allowed([
  'sql2019-ws2022'
  'sql2022-ws2022'
  'sql2019-ws2019'
  'sql2017-ws2019'
  'SQL2017-WS2016'
  'SQL2016SP1-WS2016'
  'SQL2016SP2-WS2016'
  'SQL2014SP3-WS2012R2'
  'SQL2014SP2-WS2012R2'
])
param offer string

@description('Optional. Select the Timezone for the Virtual Machine. Default: empty')
param vmTimezone string = ''

@description('Required. Tags to assign to the resource')
param tags object

@description('Optional. Private DNS Zone. Default: [baseName].com')
param privateDnsZone string = '${baseName}.com'

@description('Optional. File URI to script that will be executed on the Virtual Machine. Defaults to GitHub script of author.')
param cseFileUri string = 'https://raw.githubusercontent.com/wsmelton/az-lab-dbatools/main/scripts/serverConfig.ps1'

@description('Get the script name')
var scriptFileName = last(split(cseFileUri, '/'))

@description('Adding some standard tags for VMs')
var allTags = union({
  type: 'sql-vm'
  osType: 'Windows'
  osVersion: '${last(split(offer,'-'))}'
  sqlVersion: '${first(split(offer,'-'))}'
}, tags)

@description('Setting some default values for the image configuration')
var imageReference = {
  offer: offer
  publisher: 'microsoftsqlserver'
  sku: 'sqldev-gen2'
  version: 'latest'
}

@description('Setting standard name for each VM name to create')
var names = [for index in range(1, count): {
  vmName: '${baseName}${first(split(offer,'-'))}0${index}'
}]

@description('Create the notification settings if emailNotification is provided')
var notifySettings = empty(emailNotification) ? {} : {
  timeInMinutes: 15
  status: 'Enabled'
  emailRecipient: emailNotification
  notificationLocale: 'en'
}

resource network 'Microsoft.Network/virtualNetworks@2022-05-01' existing = {
  name: vnetName
}
resource subnet 'Microsoft.Network/virtualNetworks/subnets@2022-05-01' existing = {
  name: subnetName
  parent: network
}

resource networkInterface 'Microsoft.Network/networkInterfaces@2022-05-01' = [for (v,index) in names: {
  name: '${v.vmName}-nic0${index}'
  location: location
  tags: allTags
  properties: {
    enableAcceleratedNetworking: acceleratedNetworking
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
}]

resource virtualMachine 'Microsoft.Compute/virtualMachines@2022-08-01' = [for (v,index) in names: {
  name: v.vmName
  location: location
  tags: allTags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    hardwareProfile: {
      vmSize: size
    }
    licenseType: 'Windows_Server'
    storageProfile: {
      osDisk: {
        osType: 'Windows'
        name: '${v.vmName}-osdisk'
        createOption: 'FromImage'
        caching: 'ReadWrite'
        deleteOption: 'Delete'
        managedDisk: {
          storageAccountType: osDiskType
        }
      }
      imageReference: imageReference
      dataDisks: [
        {
          name: '${v.vmName}-datadisk'
          lun: 0
          diskSizeGB: 25
          createOption: 'Empty'
          caching: 'ReadOnly'
          writeAcceleratorEnabled: false
          deleteOption: 'Delete'
          managedDisk: {
            storageAccountType: dataDiskType
          }
        }
      ]
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: networkInterface[index].id
          properties: {
            deleteOption: 'Delete'
          }
        }
      ]
    }
    osProfile: {
      computerName: v.vmName
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
    networkInterface[index]
  ]
}]

resource sqlVirtualMachine 'Microsoft.SqlVirtualMachine/sqlVirtualMachines@2022-02-01' = [for (v,index) in names: {
  name: v.vmName
  location: location
  tags: allTags
  properties: {
    virtualMachineResourceId: virtualMachine[index].id
    sqlManagement: 'Full'
    autoBackupSettings: {
      enable: false
    }
    storageConfigurationSettings: {
      diskConfigurationType: 'NEW'
      storageWorkloadType: 'GENERAL'
      sqlDataSettings: {
        luns: [
          0
        ]
        defaultFilePath: 'F:\\SqlData'
      }
      sqlLogSettings: {
        defaultFilePath: 'F:\\SqlLogs'
        luns: [
          0
        ]
      }
      sqlTempDbSettings: {
        defaultFilePath: 'D:\\SqlTemp'
      }
    }
  }
}]

resource windowsVMExtensions 'Microsoft.Compute/virtualMachines/extensions@2022-08-01' = [for (v,index) in names: {
  name: '${v.vmName}-configScript'
  parent: virtualMachine[index]
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
}]

resource vmAutoShutdown 'Microsoft.DevTestLab/schedules@2018-09-15' = [for (v,index) in names: {
  name: any('shutdown-computevm-${v.vmName}')
  location: location
  properties: {
    status: empty(autoShutdownTime) ? 'Disabled' : 'Enabled'
    taskType: 'ComputeVmShutdownTask'
    dailyRecurrence: {
      time: autoShutdownTime
    }
    timeZoneId: vmTimezone
    notificationSettings: notifySettings
    targetResourceId: virtualMachine[index].id
  }
}]

@description('Name and IP Address of each deployed Virtual Machine')
output vmDetails array = [for (v,index) in names: {
  name: virtualMachine[index].name
  ipAddress: networkInterface[index].properties.ipConfigurations[0].properties.privateIPAddress
}]

metadata repository = {
  author: 'Shawn Melton'
  source: 'https://github.com/wsmelton/az-lab-dbatools'
  module: 'sqlVirtualMachine.bicep'
}
