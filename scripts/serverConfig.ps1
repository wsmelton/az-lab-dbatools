#requires -Version 5
[CmdletBinding()]
param(
    [string]
    $dnsName
)

<# Disable firewall #>
Get-NetFirewallProfile | Set-NetFirewallProfile -Enabled false

<# Set the #>
Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters' -Name 'NV Domain' -Value $dnsName