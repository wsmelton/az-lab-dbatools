@description('The base value to use for generating the Virtual Machine.')
param baseName string

@description('Number of Virtual Machines to create. Defaults to 1')
param count int = 1

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

@description('Enable accelerated networking feature on the Virtual Machine NIC. Defaults to false.')
param acceleratedNetworking bool = false

@description('Azure Sku name for the Virtual Machine. Defaults to Standard_B4ms')
param size string = 'Standard_B4ms'

@description('Username for the Virtual Machine local administrator account. Defaults to dbatools')
param adminUser string = 'dbatools'

@description('Provide the password for the local admin account')
@secure()
param adminPassword string

@description('Provide the storage account type to use for the OS disk. Defaults to StandardSSD_LRS')
@allowed([
  'Premium_LRS'
  'Premium_ZRS'
  'StandardSSD_LRS'
  'StandardSSD_ZRS'
  'Standard_LRS'
])
param osDiskType string = 'StandardSSD_LRS'

@description('Provide the storage account type to use for any data disk added. Defaults to StandardSSD_LRS')
@allowed([
  'Premium_LRS'
  'Premium_ZRS'
  'StandardSSD_LRS'
  'StandardSSD_ZRS'
  'Standard_LRS'
])
param dataDiskType string = 'StandardSSD_LRS'

@description('Select the offer of the marketplace image to create a SQL Server Virtual Machine. Will deploy SQL Server Developer Edition')
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

@description('Select the Timezone for the Virtual Machine.')
param vmTimezone string = ''

@description('Tags to assign to the resource')
param tags object

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

resource sqlVirtualMachine 'Microsoft.SqlVirtualMachine/sqlVirtualMachines@2022-07-01-preview' = [for (v,index) in names: {
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
