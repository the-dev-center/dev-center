#!/bin/bash

# SSH Agent Setup Script for Linux
# This script installs dependencies if needed and configures automatic ssh-agent startup
# using keychain for passphrase persistence. It targets common distros like Ubuntu/Debian and Fedora.
# Run as a regular user; it will prompt for sudo where necessary.

set -e  # Exit on error

echo "=== SSH Agent Setup for Linux ==="
echo "This script will:"
echo "- Check and install openssh-client if missing"
echo "- Install keychain for persistent agent management"
echo "- Configure ~/.bashrc for automatic startup with keychain"
echo ""
echo "Default SSH key assumed: ~/.ssh/id_rsa"
read -p "Enter path to your private key (or press Enter for default): " SSH_KEY
SSH_KEY=${SSH_KEY:-~/.ssh/id_rsa}

if [[ ! -f "$SSH_KEY" ]]; then
    echo "Warning: SSH key at $SSH_KEY does not exist. Proceeding anyway."
fi

# Detect distro for package manager
if [[ -f /etc/os-release ]]; then
    . /etc/os-release
    DISTRO=$ID
    VERSION=$VERSION_ID
else
    echo "Could not detect distro. Assuming Debian/Ubuntu for package installation."
    DISTRO="ubuntu"
fi

# Function to install packages idempotently
install_package() {
    local package=$1
    local manager=$2
    local install_cmd=$3

    if ! command -v "${package%%-client}" &> /dev/null && ! command -v "$package" &> /dev/null; then
        echo "Installing $package..."
        if [[ $EUID -eq 0 ]]; then
            $install_cmd
        else
            sudo $install_cmd
        fi
    else
        echo "$package is already installed."
    fi
}

# Install openssh-client
case "$DISTRO" in
    ubuntu|debian)
        install_package "openssh-client" "apt" "apt update && apt install -y openssh-client"
        ;;
    fedora|rhel|centos)
        install_package "ssh" "dnf" "dnf install -y openssh-clients"
        ;;
    *)
        echo "Unsupported distro: $DISTRO. Skipping openssh-client installation."
        ;;
esac

# Install keychain
case "$DISTRO" in
    ubuntu|debian)
        install_package "keychain" "apt" "apt install -y keychain"
        ;;
    fedora|rhel|centos)
        install_package "keychain" "dnf" "dnf install -y keychain"
        ;;
    *)
        echo "Unsupported distro: $DISTRO. Skipping keychain installation. Install manually with your package manager."
        exit 1
        ;;
esac

# Configure ~/.bashrc for automatic ssh-agent with keychain
BASHRC="$HOME/.bashrc"
KEYCHAIN_LINE="eval \$(keychain --eval --agents ssh $SSH_KEY)"

if ! grep -qF "$KEYCHAIN_LINE" "$BASHRC" 2>/dev/null; then
    echo "Adding keychain configuration to $BASHRC..."
    echo "" >> "$BASHRC"
    echo "# SSH Agent with keychain (added by setup-linux.sh)" >> "$BASHRC"
    echo "$KEYCHAIN_LINE" >> "$BASHRC"
    echo "Configuration added successfully!"
else
    echo "Keychain configuration already exists in $BASHRC. Skipping."
fi

# Start keychain now to add the key (will prompt for passphrase if needed)
echo "Starting ssh-agent with keychain now..."
eval "$(keychain --eval --agents ssh $SSH_KEY)"

echo ""
echo "=== Setup Complete! ==="
echo "To apply changes in your current session: source ~/.bashrc"
echo "In future logins, ssh-agent will start automatically."
echo "You may need to enter your key passphrase once per boot or session."
echo "Test with: ssh-add -l"
```
