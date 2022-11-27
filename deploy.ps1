#requires -version 7 -modules Az.Accounts, Az.Resources
[cmdletbinding()]
param(
    # PSD1 parameter file
    [string]$PSDataFile = '.\deploy-parameters.psd1'
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
            author = 'Shawn Melton'
            source = 'https://github.com/wsmelton/az-lab-dbatools'
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

    } else {
        <# if we are missing the required values, throw a pretty error #>
        $missingMsg = 'One of the required values were not found in the data file: baseName: {0} | location: {1} | tenantId: {2} | subscriptionId: {3}' -f $baseNameValue, $locationValue, $tenantIdValue, $subscriptionIdValue
        throw $missingMsg
    }
}