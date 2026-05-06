#!/bin/bash
# Setup.sh
# 1. Check if the script is run with sudo (required to create systemd files)
if [ "$EUID" -ne 0 ]; then
  echo "Please run this script with sudo: sudo ./setup.sh"
  exit 1
fi

echo "Starting automated GitOps pipeline setup..."

# 2. Dynamically grab the current directory and the real user
# (Even if run with sudo, SUDO_USER knows your actual username)
CURRENT_DIR="$(cd "$(dirname "$0")" && pwd)"
REAL_USER=${SUDO_USER:-$(whoami)}
# Get the actual home directory of that user dynamically
USER_HOME=$(getent passwd "$REAL_USER" | cut -d: -f6)

echo "Detected User: $REAL_USER"
echo "Detected Directory: $CURRENT_DIR"

# 3. Ensure deploy.sh is executable
chmod +x "$CURRENT_DIR/deploy.sh"

# 4. Create the Service File dynamically
SERVICE_FILE="/etc/systemd/system/portfolio-updater.service"
echo "Creating Systemd Service at $SERVICE_FILE..."

cat <<EOF > $SERVICE_FILE
[Unit]
Description=Portfolio GitOps Puller Service

[Service]
Type=oneshot
ExecStart=$CURRENT_DIR/deploy.sh
User=$REAL_USER
Environment=GH_CONFIG_DIR=$USER_HOME/.config/gh
EOF

# 5. Create the Timer File dynamically
TIMER_FILE="/etc/systemd/system/portfolio-updater.timer"
echo "Creating Systemd Timer at $TIMER_FILE..."

cat <<EOF > $TIMER_FILE
[Unit]
Description=Run Portfolio Updater every 2 mins

[Timer]
OnBootSec=1min
OnUnitActiveSec=2min

[Install]
WantedBy=timers.target
EOF

# 6. Reload Systemd and Enable the Timer
echo "Reloading systemd daemon..."
systemctl daemon-reload

echo "Enabling and starting the timer..."
systemctl enable --now portfolio-updater.timer

echo "Setup Complete! The server is now actively polling GitHub for changes."
echo "Check status with: sudo systemctl status portfolio-updater.timer"