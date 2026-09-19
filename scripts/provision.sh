#!/bin/bash
# provision.sh — first-boot provisioning for the Ubuntu 24.04 Hermes host.
#
# Order matters: SSH and the tunnel are the only ways in, so both come up before
# the OS upgrade and the workload; the firewall posture is set last. Hermes is
# installed natively as its own user and is deliberately root-equivalent
# (sudoers drop-in) — this box is the control surface, not a hardened multi-tenant
# host. Idempotent: safe to re-run by hand over SSH.
set -euo pipefail

log() { printf '[provision] %s\n' "$*"; }

# --- 0. Guard: a broken sudoers drop-in must fail loudly, not silently ------
if [ -f /etc/sudoers.d/hermes ]; then
  visudo -cf /etc/sudoers.d/hermes
fi

# --- 1. SSH first (the admin path; loopback-only behind the tunnel) --------
systemctl enable --now ssh

# --- 2. Cloudflare Tunnel (outbound only; the only ingress path) -----------
# The token is written by cloud-init to a 0600 file, so this script (which is a
# repo file, embedded in user_data) never contains a credential.
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

# --- 3. Base packages ------------------------------------------------------
# The Hermes installer needs git, curl and xz-utils (it fetches Node as a
# .tar.xz); everything else it brings itself. No distro Python/Node packages
# are in the dependency path.
apt-get install -y ca-certificates curl git gnupg jq cron ufw tar xz-utils python3 python3-venv

# --- 4. Full OS upgrade (access is up; harmless for the agent) -------------
# Non-fatal: a mirror hiccup must not skip the workload or the hardening.
DEBIAN_FRONTEND=noninteractive apt-get upgrade -y || log "WARNING: apt upgrade failed"

# --- 5. OCI CLI (pinned venv) ----------------------------------------------
# Used by the six-hourly snapshot and the rebuild restore, authenticated with
# the instance principal: no API key is stored on the box.
python3 -m venv /opt/oci-cli
/opt/oci-cli/bin/pip install --quiet --upgrade pip
/opt/oci-cli/bin/pip install --quiet "oci-cli==3.90.2"
ln -sf /opt/oci-cli/bin/oci /usr/local/bin/oci

# --- 6. Hermes: native per-user install ------------------------------------
# A dedicated user keeps the agent's files in one home directory; the sudoers
# drop-in from cloud-init grants it full access by design (see the runbook).
if ! id -u hermes >/dev/null 2>&1; then
  useradd --create-home --shell /bin/bash hermes
fi
if [ ! -x /home/hermes/.local/bin/hermes ]; then
  # --non-interactive is install.sh's own flag for this case (its stages use
  # read -p, which fails with EOF when stdin is not a terminal); stdin stays
  # closed so a stray prompt can never hang cloud-init.
  sudo -u hermes env HOME=/home/hermes bash -c \
    'curl -fsSL https://hermes-agent.nousresearch.com/install.sh | bash -s -- --non-interactive' </dev/null
fi
install -d -m 0700 -o hermes -g hermes /home/hermes/.hermes
install -m 0600 -o hermes -g hermes /etc/hermes/hermes.env /home/hermes/.hermes/.env
install -m 0644 -o hermes -g hermes /etc/hermes/config.yaml /home/hermes/.hermes/config.yaml

# --- 7. Hermes services ----------------------------------------------------
# Enabled, not started: state is restored first, then the workflow (or the two
# commands in the runbook) starts them, so the agent never writes state into a
# directory that is about to be replaced by a snapshot.
systemctl daemon-reload
systemctl enable hermes-gateway.service hermes-dashboard.service

# --- 8. Host firewall ------------------------------------------------------
systemctl enable --now cron
# Nothing inbound: ufw denies by default and every listener binds loopback.
ufw default deny incoming
ufw default allow outgoing
ufw allow in on lo
ufw --force enable

# --- 9. Network tuning -----------------------------------------------------
sysctl --system

# --- 10. Verify the tunnel registered (wait up to 120s) --------------------
for _ in $(seq 1 24); do
  if journalctl -u cloudflared --no-pager -n 200 2>/dev/null | grep -q "Registered tunnel connection"; then
    echo "cloudflared registered with Cloudflare"
    break
  fi
  sleep 5
done

touch /var/log/cloud_init_complete
