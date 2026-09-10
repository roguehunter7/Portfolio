#!/bin/bash
# provision.sh — first-boot provisioning for the Oracle Linux 10 dev box.
#
# Order matters: cloudflared first (it is the only way in), then the browser
# terminal (the admin path for debugging the workloads), then the workloads,
# then hardening LAST so a failure never locks us out (backdoor: OCI serial
# console).
#
# SELinux: cloud-init writes unit/script files without a restorecon pass, so a
# file can land with a type systemd will not exec (status=203/EXEC). Relabel
# everything cloud-init wrote before using it.
#
# Workload setup is best-effort: a broken DSH or Hermes must never take the
# browser terminal down with it.
set -euo pipefail

log() { printf '[provision] %s\n' "$*"; }

# --- 0. SELinux: relabel the files cloud-init wrote ------------------------
restorecon -RF /usr/local/sbin /etc/systemd/system /etc/cron.d /etc/cloudflared /etc/hermes 2>/dev/null || true

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

# --- 4. Browser terminal FIRST (it is the debug path for the workloads) ----
# The unit is written by cloud-init; enable it before DSH/Hermes so a failed
# workload cannot cost us the only interactive way in.
systemctl daemon-reload
systemctl enable --now ttyd

# --- 5. git identity + repo checkout ---------------------------------------
sudo -u opc git config --global user.name "roguehunter7"
sudo -u opc git config --global user.email "krsreeram007@gmail.com"
if [ ! -d /home/opc/Portfolio/.git ]; then
  sudo -u opc git clone --depth=1 https://github.com/roguehunter7/Portfolio.git /home/opc/Portfolio || true
fi

# --- 6. Workloads (best-effort; never fail the whole provision) ------------
# Each setup script logs to its own file. A failure is reported and skipped so
# the terminal, cloudflared and the other workload stay up.
for setup in dsh-setup hermes-setup; do
  if bash "/usr/local/sbin/${setup}.sh" >>"/var/log/${setup}.log" 2>&1; then
    log "${setup} ok"
  else
    log "WARNING: ${setup} failed; see /var/log/${setup}.log"
  fi
done

# --- 7. Services + host firewall -------------------------------------------
systemctl enable --now cron firewalld
# Nothing inbound: the NSG already denies everything; this is the host-side belt.
# ttyd, dsh-web and the Hermes gateway all listen on loopback only.
firewall-cmd --permanent --remove-service=ssh >/dev/null 2>&1 || true
firewall-cmd --permanent --remove-service=dhcpv6-client >/dev/null 2>&1 || true
firewall-cmd --reload >/dev/null 2>&1 || true

# --- 8. Network tuning -----------------------------------------------------
# BBR only: the box has no swap, so swappiness/vfs_cache tuning is a no-op.
sysctl --system

# --- 9. Verify the tunnel registered (wait up to 120s) ---------------------
for _ in $(seq 1 24); do
  if journalctl -u cloudflared --no-pager -n 200 2>/dev/null | grep -q "Registered tunnel connection"; then
    echo "cloudflared registered with Cloudflare"
    break
  fi
  sleep 5
done

# --- 10. HARDEN LAST: sshd off (admin is the browser terminal) -------------
systemctl disable --now sshd || true

touch /var/log/cloud_init_complete   # provision.sh reached the end
