#!/bin/bash
# maintenance.sh — one monthly pass for the whole box (cron, 5th at 03:05).
#
# Order: OS, then opc's nvm/Node/npm, then DSH, then Hermes, then reboot.
# Failures are logged and skipped so a bad step never blocks a later one or the
# reboot. Idempotent; safe to run by hand from the browser terminal.
set -uo pipefail

log() { printf '[maint] %s\n' "$*"; }

# --- 1. OS + system packages (cloudflared, ttyd, ripgrep, gh, kernel) ------
# Deliberately no nodejs: Node is nvm's job for opc and Hermes' managed tree.
dnf -y upgrade

# --- 2. nvm + Node LTS + npm, as opc ---------------------------------------
# cron has no nvm or login shell, so source nvm.sh explicitly.
runuser -u opc -- env HOME=/home/opc bash -c '
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

# --- 3. DeepSeek Harness (on-demand; keep the installed package current) ---
runuser -u opc -- env HOME=/home/opc bash -c '
  set -e
  export NVM_DIR="$HOME/.nvm"; . "$NVM_DIR/nvm.sh"
  candidate="$(npm view @deepseek-ai/dsh versions --json | jq -r "last")"
  echo "[maint] installing @deepseek-ai/dsh@$candidate"
  npm install -g "@deepseek-ai/dsh@$candidate"
' || log "DSH update failed"

# --- 4. Hermes: repo, Python deps and its own managed Node tree ------------
runuser -u opc -- env HOME=/home/opc XDG_RUNTIME_DIR="/run/user/$(id -u opc)" \
  bash -c '"$HOME/.local/bin/hermes" update' || log "hermes update failed"

# --- 5. Reboot: new kernel, and every supervised/lingered unit back up -----
systemctl reboot
