#!/usr/bin/env bash
# oci-ssh.sh — SSH into the Oracle VM through the Cloudflare tunnel.
#
# The VM exposes NO public ports: its NSG has zero ingress rules and cloudflared
# connects outbound to Cloudflare. ssh.sreeramkr.com is only reachable via the
# tunnel, and (if you added a Zero Trust Access app) only after your CF login.
#
# Usage:
#   ./scripts/oci-ssh.sh [--key PATH] [--user NAME]
#   SSH_KEY=~/.ssh/portfolio SSH_USER=ubuntu ./scripts/oci-ssh.sh
#
# Prereqs:
#   - cloudflared installed locally (brew install cloudflared / apt / choco)
#   - first run: browser opens for Cloudflare Access login (one-time)
set -euo pipefail

HOSTNAME="${SSH_HOSTNAME:-ssh.sreeramkr.com}"
VM_USER="${SSH_USER:-ubuntu}"
VM_KEY="${SSH_KEY:-}"

KEY_ARGS=()
if [ -n "$VM_KEY" ]; then
  KEY_ARGS=(-i "$VM_KEY")
fi

echo ">> ssh ${VM_USER}@${HOSTNAME} via cloudflared tunnel (ProxyCommand)"
exec ssh "${KEY_ARGS[@]}" \
  -o ProxyCommand="cloudflared access ssh --hostname %h" \
  -o ServerAliveInterval=30 \
  "${VM_USER}@${HOSTNAME}"
