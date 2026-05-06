#!/bin/bash
# setup.sh - Infrastructure Provisioner
# This script sets up the Systemd Timer for native GitOps.

# 1. Check for root privileges
if [ "$EUID" -ne 0 ]; then
  echo "Please run as root: sudo ./setup.sh"
  exit 1
fi

echo "Starting automated GitOps pipeline setup..."

# 2. Define Explicit Paths (Aligning with Terraform and deploy.sh)
TARGET_DIR="/opt/portfolio"
SERVICE_FILE="/etc/systemd/system/portfolio-updater.service"
TIMER_FILE="/etc/systemd/system/portfolio-updater.timer"

# 3. Ensure deploy.sh is executable
chmod +x "$TARGET_DIR/deploy.sh"

# 4. Create the Service File
# Note: We run as 'root' to ensure seamless Docker and Git access
echo "Creating Systemd Service..."
cat <<EOF > $SERVICE_FILE
[Unit]
Description=Portfolio GitOps Native Poller
After=network.target

[Service]
Type=oneshot
WorkingDirectory=$TARGET_DIR
ExecStart=$TARGET_DIR/deploy.sh

[Install]
WantedBy=multi-user.target
EOF

# 5. Create the Timer File (2-minute intervals)
echo "Creating Systemd Timer..."
cat <<EOF > $TIMER_FILE
[Unit]
Description=Run Portfolio GitOps Poller every 2 mins

[Timer]
OnBootSec=1min
OnUnitActiveSec=2min

[Install]
WantedBy=timers.target
EOF

# 6. Finalize and Enable
echo "Reloading systemd and enabling timer..."
systemctl daemon-reload
systemctl enable --now portfolio-updater.timer

echo "Setup Complete. Portfolio is now self-updating."