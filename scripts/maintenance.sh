#!/bin/bash
# maintenance.sh — one monthly pass for the whole box (cron, 5th at 03:05).
#
# Order: OS, then ubuntu's nvm/Node/npm, then the Hermes image, then
# reboot. Failures are logged and skipped so a bad step never blocks a later
# one or the reboot. Idempotent; safe to run by hand from the browser terminal.
set -uo pipefail

log() { printf '[maint] %s\n' "$*"; }

# --- 1. OS + system packages (cloudflared, ttyd, ripgrep, gh, kernel) ------
# Deliberately no nodejs: Node is nvm's job for ubuntu.
DEBIAN_FRONTEND=noninteractive apt-get update -y
DEBIAN_FRONTEND=noninteractive apt-get upgrade -y

# --- 2. nvm + Node LTS + npm, as ubuntu ------------------------------------
# cron has no nvm or login shell, so source nvm.sh explicitly.
runuser -u ubuntu -- env HOME=/home/ubuntu bash -c '
  set -e
  export NVM_DIR="$HOME/.nvm"
  . "$NVM_DIR/nvm.sh"
  # Re-running the installer refreshes nvm to its newest tag.
  curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.7/install.sh | bash
  . "$NVM_DIR/nvm.sh"
  nvm install --lts
  nvm alias default "lts/*"
  nvm install-latest-npm
' || log "nvm/Node/npm update failed"

# --- 3. Hermes (Docker): pull the newest image and recreate ----------------
docker compose -f /opt/hermes/docker-compose.yml pull --quiet || log "Hermes image pull failed"
docker compose -f /opt/hermes/docker-compose.yml up -d || log "Hermes recreate failed"

# --- 4. Reboot: new kernel, every supervised service and the container back -
systemctl reboot
