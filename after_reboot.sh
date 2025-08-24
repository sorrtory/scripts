#!/bin/bash

MARKER="/var/tmp/hello_after_reboot"

if [ ! -f "$MARKER" ]; then
    echo "[Step 1] First run: Hello, world!"
    echo "Creating marker and scheduling continuation after reboot..."

    # Create marker to detect next boot
    sudo touch "$MARKER"

    # Create a one-time systemd service to run this script again after reboot
    SERVICE_PATH="/etc/systemd/system/hello-after-reboot.service"
    sudo bash -c "cat > $SERVICE_PATH" <<EOF
[Unit]
Description=Hello World Resume Script
After=multi-user.target

[Service]
Type=oneshot
ExecStart=/bin/bash $(realpath $0)
RemainAfterExit=no

[Install]
WantedBy=multi-user.target
EOF

    # Enable the service so it runs next boot
    sudo systemctl enable hello-after-reboot.service

    echo "Rebooting now..."
    sudo reboot
    exit
fi

# Second run (after reboot)
echo "[Step 2] After reboot: Hello again!"
echo "Cleaning up marker and disabling service..."

# Remove marker and disable service so it won't run again
sudo rm -f "$MARKER"
sudo systemctl disable hello-after-reboot.service
sudo rm -f /etc/systemd/system/hello-after-reboot.service
sudo systemctl daemon-reload

echo "Done. Script will not run again automatically."
