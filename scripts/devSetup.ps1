#requires -Version 5
Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))

Start-Sleep -Seconds 15

if (Get-Command choco -CommandType Application) {
    choco install git.install --yes --no-progress
    choco install pwsh --yes --no-progress
    choco install vscode-insiders --yes --no-progress
    choco install discord.install --yes --no-progress
}
