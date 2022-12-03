#requires -version 7 -modules Az.Accounts, Az.Resources
[cmdletbinding()]
param(
    # PSD1 parameter file
    [string]$PSDataFile = '.\deploy-parameters.psd1',

    # Additional parameters to pass to the deployment
    [hashtable]$Parameters
)

begin {
    <# if we don't have a data file throw a pretty error #>
    if (Test-Path $PSDataFile) {
        $paramData = Import-PowerShellDataFile $PSDataFile
    } else {
        throw "No PSDataFile provided or found: $($_)"
    }
    <# default parmeters that are required #>
    switch ($paramData.Keys) {
        'baseName' { $baseNameValue = $paramData['baseName'] }
        'location' { $locationValue = $paramData['location'] }
        'tenantId' { $tenantIdValue = $paramData['tenantId'] }
        'subscriptionId' { $subscriptionIdValue = $paramData['subscriptionId'] }
        'tags' { $tags = $paramData['tags'] }
    }
}

process {
    if ($baseNameValue -and $locationValue -and $tenantIdValue -and $subscriptionIdValue) {
        Write-Verbose ("baseName: $baseNameValue")
        Write-Verbose ("location: $locationValue")
        Write-Verbose ("tenantId: $tenantIdValue")
        Write-Verbose ("subscriptionId: $subscriptionIdValue")

        <# if parameter file does not include a base tags object, default to this one #>
        $tags ??= @{
            purpose = 'dbatools-lab'
            author  = 'Shawn Melton'
            source  = 'https://github.com/wsmelton/az-lab-dbatools'
        }

        <# if we cannot set Az context there is no point in going forward #>
        try {
            Write-Verbose 'Validating Az PowerShell context'
            $azContext = Get-AzContext -ErrorAction Stop

            if ($azContext.Subscription.Id -ne $subscriptionIdValue) {
                Write-Verbose "Setting Az PowerShell context: TenantId: $tenantIdValue | SubscriptionId: $subscriptionIdValue"
                Set-AzContext -Tenant $tenantIdValue -Subscription $subscriptionIdValue
            }
        } catch {
            throw "Unable to determine Azure context for connection: $($_)"
        }

        <# prepare deployment #>
        <#  1. Create Resource Group #>
        $resourceGroupName = 'rg-dbatools-lab'
        if (-not ($resourceGroup = Get-AzResourceGroup -Name $resourceGroupName -ErrorAction SilentlyContinue)) {
            try {
                $resourceGroup = New-AzResourceGroup -Name $resourceGroupName -Location $locationValue -Tag $tags -ErrorAction Stop
            } catch {
                throw "Unable to create a Resource Group for deployment: $($_)"
            }
        }
        <#  2. Create deployment parameter object #>
        if ($resourceGroup) {
            $bicepTemplateParams = $paramData
            <# trim params not used in the Bicep templates #>
            $bicepTemplateParams.Remove('subscriptionId')
            $bicepTemplateParams.Remove('tenantId')

            <# add tags param value from param data or set a default value #>
            $paramData['tags'] ? $bicepTemplateParams.Add('tags',$paramData['tags']) : $bicepTemplateParams.Add('tags',$tags)

            <# deploy the Bicep template #>
            $resourceGroupDeployParams = @{
                Name                    = "dbatools-lab-$(Get-Date -Format FileDateTime)"
                ResourceGroupName       = $resourceGroupName
                TemplateParameterObject = $bicepTemplateParams
                TemplateFile            = '.\main.bicep'
            }
            $resourceDeployment = New-AzResourceGroupDeployment @resourceGroupDeployParams -Verbose
        }
    } else {
        <# if we are missing the required values, throw a pretty error #>
        $missingMsg = 'One of the required values were not found in the data file: baseName: {0} | location: {1} | tenantId: {2} | subscriptionId: {3}' -f $baseNameValue, $locationValue, $tenantIdValue, $subscriptionIdValue
        throw $missingMsg
    }
}
end {
    <# if deployment was successful output proper PS object of the template output values #>
    $resourceDeployment.ProvisioningState -eq 'Succeeded' ? ($resourceDeployment.Outputs | ConvertTo-Json | ConvertFrom-Json) : $null
}
<#
.SYNOPSIS
Deploys the Bicep to an Azure subscription for use as development or playing with dbatools module and SQL Server
#>