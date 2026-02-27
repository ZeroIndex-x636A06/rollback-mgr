#!/bin/bash

echo "=== Installing Rollback Manager ==="

# Check if the main script exists in the current directory (without the .sh)
if [ ! -f "rollback-mgr" ]; then
    echo "Error: 'rollback-mgr' not found in this directory."
    echo "Please run this installer from the folder containing your script."
    exit 1
fi

echo "Moving executable to /usr/local/bin (requires sudo)..."
sudo cp rollback-mgr /usr/local/bin/rollback-mgr
sudo chmod +x /usr/local/bin/rollback-mgr

echo "Configuring background systemd timers..."
rollback-mgr check >/dev/null 2>&1

echo ""
echo "Installation complete!"
echo "You can now safely delete this folder. Just type 'rollback-mgr' from anywhere to launch the tool."
