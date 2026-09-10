#!/bin/bash
# provision.sh — first-boot provisioning for the Oracle Linux 10 dev box.
#
# Order matters: cloudflared first (it is the only way in), then the browser
# terminal (the admin path), then the workloads, then hardening LAST so a
# failure never locks us out (backdoor: OCI serial console).
# Idempotent — safe to re-run by hand from the browser terminal.
set -euo pipefail

log() { printf '[provision] %s\n' "$*"; }

# --- 1. Cloudflare Tunnel (outbound only; the only ingress path) -----------
# The token is written by cloud-init to a 0600 file, so this script (which is
# a repo file, embedded in user_data) never contains a credential.
if ! command -v cloudflared >/dev/null 2>&1; then
  curl -fsSL https://pkg.cloudflare.com/cloudflared.repo | tee /etc/yum.repos.d/cloudflared.repo >/dev/null
  dnf install -y cloudflared
fi
if [ ! -f /etc/cloudflared/token ]; then
  cloudflared service install "$(cat /etc/cloudflared/tunnel-token)"
fi
systemctl enable --now cloudflared

# --- 2. Base packages ------------------------------------------------------
# EPEL supplies ttyd, ripgrep, htop and gh (Oracle Linux has none of them).
# Deliberately no nodejs: Node is nvm's job for opc (step 5) and the Hermes
# gateway keeps its own managed tree, so a monthly Node bump cannot break it.
dnf install -y oracle-epel-release-el10
dnf install -y \
  ca-certificates curl git gnupg2 jq tmux cronie firewalld tar xz \
  python3 make gcc-c++ unzip dnf-plugins-core policycoreutils-python-utils \
  ttyd ripgrep htop gh

# --- 3. Chromium system libraries (Hermes browser toolset) -----------------
# Playwright does not install these on RPM hosts — the Hermes installer prints
# this exact list and expects an administrator to run it.
dnf install -y nss atk at-spi2-core cups-libs libdrm libxkbcommon mesa-libgbm pango cairo alsa-lib

# --- 4. Browser terminal FIRST (it is the debug path for the workloads) ----
# If a workload fails below, this is still how we get in to read its log.
systemctl daemon-reload
systemctl enable --now ttyd

# --- 5. nvm + Node LTS + npm, as opc ---------------------------------------
# nvm is per-user and has no dnf package; the official installer is the only
# supported path. It edits opc's shell profile, so the ttyd tmux shell gets
# node/npm on PATH. Non-interactive callers (the monthly script) source nvm.sh
# themselves.
sudo -u opc env HOME=/home/opc bash -c '
  set -euo pipefail
  curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.7/install.sh | bash
  export NVM_DIR="$HOME/.nvm"
  . "$NVM_DIR/nvm.sh"
  nvm install --lts
  nvm alias default "lts/*"
'

# --- 6. DeepSeek Harness, as opc (no service: run it from the terminal) ----
# No reverse-proxy plugin: plain `dsh web --trusted-host` on loopback :3080,
# which is the cloudflared target. npm 11+ gates install scripts behind
# allow-scripts, so seed the allowlist only when npm is new enough.
sudo -u opc env HOME=/home/opc bash -c '
  set -euo pipefail
  export NVM_DIR="$HOME/.nvm"; . "$NVM_DIR/nvm.sh"
  NPMRC="$HOME/.npmrc"
  touch "$NPMRC"
  if [ "$(npm --version | cut -d. -f1)" -ge 11 ]; then
    grep -q "^allow-scripts=" "$NPMRC" || echo \
      "allow-scripts=@deepseek-ai/dsh-subprocess-local,koffi,node-pty,@google/genai,protobufjs" >> "$NPMRC"
  fi
  candidate="$(npm view @deepseek-ai/dsh versions --json | jq -r "last")"
  echo "[provision] installing @deepseek-ai/dsh@$candidate"
  npm install -g "@deepseek-ai/dsh@$candidate"
'

# --- 7. DSH key for the interactive shell ----------------------------------
# No service means no EnvironmentFile: the key lives in opc's home and the
# login shell exports it, so `dsh web` picks it up from the environment.
install -d -m 0700 -o opc -g opc /home/opc/.dsh
install -m 0600 -o opc -g opc /etc/dsh/env /home/opc/.dsh/env
if ! grep -q 'dsh/env' /home/opc/.bashrc 2>/dev/null; then
  printf '\n[ -f "$HOME/.dsh/env" ] && set -a && . "$HOME/.dsh/env" && set +a\n' >> /home/opc/.bashrc
fi
chown opc:opc /home/opc/.bashrc

# --- 8. Hermes (native, as opc) --------------------------------------------
bash /usr/local/sbin/hermes-setup.sh >/var/log/hermes-setup.log 2>&1 || log "WARNING: hermes-setup failed; see /var/log/hermes-setup.log"

# --- 9. Services + host firewall -------------------------------------------
systemctl enable --now cron firewalld
# Nothing inbound: the NSG already denies everything; this is the host-side belt.
# ttyd, dsh web and the Hermes gateway all listen on loopback only.
firewall-cmd --permanent --remove-service=ssh >/dev/null 2>&1 || true
firewall-cmd --permanent --remove-service=dhcpv6-client >/dev/null 2>&1 || true
firewall-cmd --reload >/dev/null 2>&1 || true

# --- 10. Network tuning ----------------------------------------------------
# BBR only: this box has no swap, so swappiness/vfs_cache tuning is a no-op.
sysctl --system

# --- 11. Verify the tunnel registered (wait up to 120s) --------------------
for _ in $(seq 1 24); do
  if journalctl -u cloudflared --no-pager -n 200 2>/dev/null | grep -q "Registered tunnel connection"; then
    echo "cloudflared registered with Cloudflare"
    break
  fi
  sleep 5
done

# --- 12. HARDEN LAST: sshd off (admin is the browser terminal) -------------
systemctl disable --now sshd || true

touch /var/log/cloud_init_complete
