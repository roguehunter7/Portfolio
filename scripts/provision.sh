#!/bin/bash
# provision.sh — first-boot provisioning for the Ubuntu 24.04 dev box.
#
# Order matters: cloudflared first (it is the only way in), then the browser
# terminal, THEN the full OS upgrade and the workloads, then hardening LAST so
# a failure never locks us out (backdoor: OCI serial console).
# Idempotent — safe to re-run by hand from the browser terminal.
set -euo pipefail

log() { printf '[provision] %s\n' "$*"; }

# --- 1. Cloudflare Tunnel (outbound only; the only ingress path) -----------
# The token is written by cloud-init to a 0600 file, so this script (which is
# a repo file, embedded in user_data) never contains a credential.
install -d --mode=0755 /usr/share/keyrings
if [ ! -f /usr/share/keyrings/cloudflare-main.gpg ]; then
  curl -fsSL https://pkg.cloudflare.com/cloudflare-main.gpg \
    | tee /usr/share/keyrings/cloudflare-main.gpg >/dev/null
fi
echo 'deb [signed-by=/usr/share/keyrings/cloudflare-main.gpg] https://pkg.cloudflare.com/cloudflared any main' \
  > /etc/apt/sources.list.d/cloudflared.list
apt-get update -y
apt-get install -y cloudflared
if [ ! -f /etc/cloudflared/token ]; then
  cloudflared service install "$(cat /etc/cloudflared/tunnel-token)"
fi
systemctl enable --now cloudflared

# --- 2. Base packages ------------------------------------------------------
# No nodejs: Node is nvm's job for ubuntu (step 5). Hermes runs in Docker and
# carries its own toolchain, so nothing here serves it.
apt-get install -y \
  ca-certificates curl git gnupg jq tmux cron ufw tar xz-utils \
  build-essential python3 python3-venv unzip \
  ttyd ripgrep htop gh

# --- 3. Browser terminal FIRST (it is the admin path) ----------------------
# ttyd comes up before the OS upgrade and the workloads, so the tunnel is
# usable within minutes and a failed upgrade or workload cannot lock us out.
systemctl daemon-reload
systemctl enable --now ttyd

# --- 4. Full OS upgrade (after access is up) -------------------------------
# cloud-init runs with package_upgrade:false, so this no longer blocks ttyd.
# Non-fatal: a mirror hiccup must not skip the workloads or the hardening.
DEBIAN_FRONTEND=noninteractive apt-get upgrade -y || log "WARNING: apt upgrade failed"

# --- 5. nvm + Node LTS + npm, as ubuntu ------------------------------------
# nvm is per-user and has no apt package; the official installer is the only
# supported path. It edits ubuntu's shell profile, so the ttyd tmux shell gets
# node/npm on PATH. Non-interactive callers (the monthly script) source nvm.sh
# themselves.
sudo -u ubuntu env HOME=/home/ubuntu bash -c '
  set -euo pipefail
  curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.7/install.sh | bash
  export NVM_DIR="$HOME/.nvm"
  . "$NVM_DIR/nvm.sh"
  nvm install --lts
  nvm alias default "lts/*"
'

# --- 6. DSH key for the interactive shell ----------------------------------
# No service means no EnvironmentFile: the key lives in ubuntu's home and the
# login shell exports it, so `dsh web` picks it up from the environment.
install -d -m 0700 -o ubuntu -g ubuntu /home/ubuntu/.dsh
install -m 0600 -o ubuntu -g ubuntu /etc/dsh/env /home/ubuntu/.dsh/env
if ! grep -q 'dsh/env' /home/ubuntu/.bashrc 2>/dev/null; then
  printf '\n[ -f "$HOME/.dsh/env" ] && set -a && . "$HOME/.dsh/env" && set +a\n' >> /home/ubuntu/.bashrc
fi
chown ubuntu:ubuntu /home/ubuntu/.bashrc

# --- 7. Docker Engine + Compose plugin (official Ubuntu repo) --------------
# Hermes is the only container: the image replaces a host-wide Python/Node/
# Chromium toolchain and keeps the agent out of ubuntu's home.
install -m 0755 -d /etc/apt/keyrings
if [ ! -f /etc/apt/keyrings/docker.gpg ]; then
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
    | gpg --dearmor --yes -o /etc/apt/keyrings/docker.gpg
  chmod a+r /etc/apt/keyrings/docker.gpg
fi
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
  > /etc/apt/sources.list.d/docker.list
apt-get update -y
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
systemctl enable --now docker

# --- 8. Hermes (official image) --------------------------------------------
# cloud-init writes the compose file to /opt/hermes; stage the secrets/config
# beside it and let the image carry everything else. /opt/hermes is mounted at
# /opt/data, so sessions, skills and memories survive an image upgrade.
install -d -m 0755 /opt/hermes
install -m 0600 /etc/hermes/hermes.env /opt/hermes/.env
install -m 0644 /etc/hermes/config.yaml /opt/hermes/config.yaml
# Best-effort: a broken Hermes must not skip ufw, the tunnel check or hardening.
docker compose -f /opt/hermes/docker-compose.yml up -d || log "WARNING: Hermes compose up failed; see docker logs"

# --- 9. Services + host firewall -------------------------------------------
systemctl enable --now cron
# Nothing inbound: the NSG already denies everything; this is the host-side belt.
# ttyd, dsh web and the Hermes gateway all listen on loopback only.
ufw default deny incoming
ufw default allow outgoing
ufw allow in on lo
ufw --force enable

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
systemctl disable --now ssh || true

touch /var/log/cloud_init_complete
