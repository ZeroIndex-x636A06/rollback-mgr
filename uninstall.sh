#!/bin/bash

echo "=== Uninstalling Rollback Manager ==="

HOLD_FILE="$HOME/.config/rollback-mgr/holds.txt"

# 1. Safely release all active package holds before tearing down
if [ -s "$HOLD_FILE" ]; then
    echo "Releasing active package holds..."
    # Request sudo once upfront if there are holds to process
    sudo -v 
    
    while IFS='|' read -r pkg type exp_date; do
        if [ -n "$pkg" ]; then
            echo "   - Unholding: $pkg ($type)"
            case $type in
                flatpak) sudo flatpak mask --remove "$pkg" >/dev/null 2>&1 ;;
                apt) sudo apt-mark unhold "$pkg" >/dev/null 2>&1 ;;
                dnf) sudo dnf versionlock delete "$pkg" >/dev/null 2>&1 ;;
                pacman) sudo bash -c "sed -i 's/[[:space:]]*\b$pkg\b//g' /etc/pacman.conf" ;;
            esac
        fi
    done < "$HOLD_FILE"
    echo "All packages successfully unheld."
else
    echo "No active holds found. Proceeding with uninstallation..."
fi

echo "Stopping and disabling background timers..."
systemctl --user disable --now rollback-mgr.timer 2>/dev/null

echo "Removing systemd service files..."
rm -f ~/.config/systemd/user/rollback-mgr.service
rm -f ~/.config/systemd/user/rollback-mgr.timer
systemctl --user daemon-reload

echo "Removing executable from /usr/local/bin (requires sudo)..."
sudo rm -f /usr/local/bin/rollback-mgr

echo ""
read -p "Do you also want to completely delete your saved config data directory? (y/N): " del_config
if [[ "$del_config" =~ ^[Yy]$ ]]; then
    rm -rf ~/.config/rollback-mgr
    echo "🧹 Configuration data wiped."
fi

echo ""
echo "Uninstallation complete. Rollback Manager has been completely removed from your system."
