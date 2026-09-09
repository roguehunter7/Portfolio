#!/bin/bash
# provision.sh — first-boot provisioning for the Oracle Linux 10 dev box.
#
# Order matters: cloudflared first (it is the only way in), workloads next,
# hardening LAST so a failure never locks us out (backdoor: OCI serial console).
# Idempotent — safe to re-run by hand from the browser terminal.
set -euo pipefail

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
# nodejs comes from OL10 appstream (22.23.2) — no nvm, no NodeSource.
# No container runtime: Hermes runs natively, so there is no Docker or podman.
dnf install -y oracle-epel-release-el10
dnf install -y \
  ca-certificates curl git gnupg2 jq tmux cronie firewalld \
  python3 make gcc-c++ unzip xz nodejs dnf-plugins-core policycoreutils-python-utils \
  ttyd ripgrep htop gh

# --- 3. Chromium system libraries (Hermes browser toolset) -----------------
# Playwright does not install these on RPM hosts — the Hermes installer prints
# this exact list and expects an administrator to run it.
dnf install -y nss atk at-spi2-core cups-libs libdrm libxkbcommon mesa-libgbm pango cairo alsa-lib

# --- 4. git identity + repo checkout ---------------------------------------
sudo -u opc git config --global user.name "roguehunter7"
sudo -u opc git config --global user.email "krsreeram007@gmail.com"
if [ ! -d /home/opc/Portfolio/.git ]; then
  sudo -u opc git clone --depth=1 https://github.com/roguehunter7/Portfolio.git /home/opc/Portfolio || true
fi

# --- 5. Workloads ----------------------------------------------------------
bash /usr/local/sbin/dsh-setup.sh
bash /usr/local/sbin/hermes-setup.sh

# --- 6. Services + host firewall -------------------------------------------
systemctl daemon-reload
systemctl enable --now cron firewalld ttyd
# Nothing inbound: the NSG already denies everything; this is the host-side belt.
# ttyd, dsh-web and the Hermes gateway all listen on loopback only.
firewall-cmd --permanent --remove-service=ssh >/dev/null 2>&1 || true
firewall-cmd --permanent --remove-service=dhcpv6-client >/dev/null 2>&1 || true
firewall-cmd --reload >/dev/null 2>&1 || true

# --- 7. Network tuning -----------------------------------------------------
# BBR only: the box has no swap, so swappiness/vfs_cache tuning would be a no-op.
sysctl --system

# --- 8. Verify the tunnel registered (wait up to 120s) ---------------------
for i in $(seq 1 24); do
  if journalctl -u cloudflared --no-pager -n 200 2>/dev/null | grep -q "Registered tunnel connection"; then
    echo "cloudflared registered with Cloudflare"
    break
  fi
  sleep 5
done

# --- 9. HARDEN LAST: sshd off (admin is the browser terminal) --------------
systemctl disable --now sshd || true

touch /var/log/cloud_init_complete   # sentinel only if we get here