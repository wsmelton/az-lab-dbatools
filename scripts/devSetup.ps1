#requires -Version 5
Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))

Start-Sleep -Seconds 15

if (Get-Command choco -CommandType Application) {
    choco install git.install --yes --no-progress
    choco install pwsh --yes --no-progress
    choco install vscode-insiders --yes --no-progress
    choco install discord.install --yes --no-progress
}

if (Get-Command code-insiders -CommandType Application) {
    code-insiders --install-extension 'streetsidesoftware.code-spell-checker'
    code-insiders --install-extension 'usernamehw.errorlens'
    code-insiders --install-extension 'DavidAnson.vscode-markdownlint'
    code-insiders --install-extension 'sdras.night-owl'
    code-insiders --install-extension 'TylerLeonhardt.vscode-pester-test-adapter'
    code-insiders --install-extension 'ms-dotnettools.dotnet-interactive-vscode'
    code-insiders --install-extension 'ms-vscode.powershell-preview'
}