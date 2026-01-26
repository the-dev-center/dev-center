# SSH Agent Setup Script for Windows
# This script installs OpenSSH Client if missing, configures the ssh-agent service for automatic startup,
# and starts it. Run in PowerShell (preferably as Administrator for installation).
# It is idempotent and will skip steps if already configured.

#Requires -Version 5.1
#Requires -RunAsAdministrator

param(
    [string]$SshKeyPath = "$env:USERPROFILE\.ssh\id_rsa"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Write-Host "=== SSH Agent Setup for Windows ===" -ForegroundColor Green
Write-Host "This script will:"
Write-Host "- Check and install OpenSSH Client if missing"
Write-Host "- Configure ssh-agent service for automatic startup"
Write-Host "- Start the service"
Write-Host ""
Write-Host "Default SSH key assumed: $SshKeyPath"
$SshKeyPath = Read-Host "Enter path to your private key (or press Enter for default)"

if (-not (Test-Path $SshKeyPath)) {
    Write-Warning "Warning: SSH key at $SshKeyPath does not exist. Proceeding anyway."
}

# Function to check if OpenSSH Client is installed
function Test-OpenSshClientInstalled {
    $capability = Get-WindowsCapability -Online -Name OpenSSH.Client* | Where-Object { $_.State -eq "Installed" }
    return $null -ne $capability
}

# Install OpenSSH Client if not installed
if (-not (Test-OpenSshClientInstalled)) {
    Write-Host "Installing OpenSSH Client..." -ForegroundColor Yellow
    try {
        Add-WindowsCapability -Online -Name OpenSSH.Client~~~~0.0.1.0 -ErrorAction Stop
        Write-Host "OpenSSH Client installed successfully." -ForegroundColor Green
    } catch {
        Write-Error "Failed to install OpenSSH Client: $($_.Exception.Message)"
        Write-Host "Please run PowerShell as Administrator and try again." -ForegroundColor Red
        exit 1
    }
} else {
    Write-Host "OpenSSH Client is already installed." -ForegroundColor Green
}

# Check and configure ssh-agent service
$serviceName = "ssh-agent"
$service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue

if ($null -eq $service) {
    Write-Error "ssh-agent service not found. Ensure OpenSSH Client is properly installed."
    exit 1
}

if ($service.StartType -ne "Automatic") {
    Write-Host "Configuring ssh-agent service for automatic startup..." -ForegroundColor Yellow
    Set-Service -Name $serviceName -StartupType Automatic
    Write-Host "ssh-agent service set to automatic startup." -ForegroundColor Green
} else {
    Write-Host "ssh-agent service is already set to automatic startup." -ForegroundColor Green
}

if ($service.Status -ne "Running") {
    Write-Host "Starting ssh-agent service..." -ForegroundColor Yellow
    Start-Service -Name $serviceName
    Write-Host "ssh-agent service started." -ForegroundColor Green
} else {
    Write-Host "ssh-agent service is already running." -ForegroundColor Green
}

# Configure Git to use Windows OpenSSH (critical for Git operations to work!)
Write-Host ""
Write-Host "Configuring Git to use Windows OpenSSH..." -ForegroundColor Yellow
$gitExists = Get-Command git -ErrorAction SilentlyContinue
if ($gitExists) {
    $currentSshCommand = git config --global --get core.sshCommand 2>$null
    $windowsSsh = "C:/Windows/System32/OpenSSH/ssh.exe"
    
    if ($currentSshCommand -ne $windowsSsh) {
        git config --global core.sshCommand $windowsSsh
        Write-Host "Git configured to use Windows OpenSSH." -ForegroundColor Green
        Write-Host "This ensures Git can access keys from the Windows ssh-agent." -ForegroundColor Gray
    } else {
        Write-Host "Git is already configured to use Windows OpenSSH." -ForegroundColor Green
    }
} else {
    Write-Host "Git not found. Install Git, then run:" -ForegroundColor Yellow
    Write-Host 'git config --global core.sshCommand "C:/Windows/System32/OpenSSH/ssh.exe"' -ForegroundColor Cyan
    Write-Host "This is CRITICAL - without it, Git will use its bundled SSH which cannot access the Windows ssh-agent!" -ForegroundColor Red
}

# Instructions for adding keys
Write-Host ""
Write-Host "=== Setup Complete! ===" -ForegroundColor Green
Write-Host "The ssh-agent service will now start automatically on boot."
Write-Host ""
Write-Host "To add your SSH key to the agent (run this once or add to your PowerShell profile):"
Write-Host "ssh-add $SshKeyPath"
Write-Host ""
Write-Host "For automatic key addition on login, add the following to your PowerShell profile (`$PROFILE`):"
Write-Host "# Load SSH Agent"
Write-Host "if (-not (Get-Process ssh-agent -ErrorAction SilentlyContinue)) { Start-Service ssh-agent }"
Write-Host "ssh-add $SshKeyPath"
Write-Host ""
Write-Host "Test with: ssh-add -l"
Write-Host "For Git Bash users, see the documentation for .bashrc configuration."
Write-Host ""
Write-Host "Note: For passphrase-protected keys, you'll need to enter the passphrase manually on first use or use Credential Manager integration."
Write-Host ""
Write-Host "=== IMPORTANT ===" -ForegroundColor Magenta
Write-Host "If 'ssh -T git@github.com' works but 'git push' fails with 'Permission denied'," -ForegroundColor White
Write-Host "ensure Git is using Windows OpenSSH:" -ForegroundColor White
Write-Host 'git config --global core.sshCommand "C:/Windows/System32/OpenSSH/ssh.exe"' -ForegroundColor Cyan
