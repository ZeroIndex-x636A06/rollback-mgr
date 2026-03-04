#!/bin/bash

echo "Installing Rollback Manager..."

if [ ! -f "rollback-mgr" ]; then
    echo "Error: 'rollback-mgr' executable not found in the current directory."
    exit 1
fi

# Check for fzf and install if missing
if ! command -v fzf &> /dev/null; then
    echo "Dependency 'fzf' not found. Installing..."
    if command -v pacman &> /dev/null; then
        sudo pacman -S --noconfirm fzf
    elif command -v apt-get &> /dev/null; then
        sudo apt-get update >/dev/null 2>&1
        sudo apt-get install -y fzf
    elif command -v dnf &> /dev/null; then
        sudo dnf install -y fzf
    else
        echo "Error: Could not determine package manager."
        echo "Please install fzf manually and re-run this script."
        exit 1
    fi
fi

echo "Copying executable to /usr/local/bin..."
sudo cp rollback-mgr /usr/local/bin/rollback-mgr
sudo chmod +x /usr/local/bin/rollback-mgr

echo "Configuring systemd background timers..."
rollback-mgr check >/dev/null 2>&1

echo "Installation complete."
echo "You can now safely delete this folder. Just type 'rollback-mgr' from anywhere to launch the tool."
