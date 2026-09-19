#!/bin/bash
# maintenance.sh — one monthly pass for the whole box (cron, 5th at 03:05).
#
# Order: OS packages, then Hermes, then reboot. Failures are logged and skipped
# so a bad step never blocks a later one or the reboot. Idempotent; safe to run
# by hand over SSH.
set -uo pipefail

log() { printf '[maint] %s\n' "$*"; }

# --- 1. OS + system packages (cloudflared, kernel) -------------------------
# Deliberately no python3/nodejs in the dependency path: Hermes' installer
# manages its own uv Python and Node under /home/hermes.
DEBIAN_FRONTEND=noninteractive apt-get update -y
DEBIAN_FRONTEND=noninteractive apt-get upgrade -y

# --- 2. Hermes: update in place as hermes ----------------------------------
# The updater brings Python, Node and the checkout forward together and rolls
# the checkout back if the pull does not parse. It prompts about new config
# options, so stdin is closed; a failure is logged, never fatal.
sudo -u hermes env HOME=/home/hermes /home/hermes/.local/bin/hermes update </dev/null \
  || log "hermes update failed or needs attention"

# --- 3. Reboot: new kernel, both units and the tunnel back -----------------
systemctl reboot
