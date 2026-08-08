#!/usr/bin/env bash
# hermes-install.sh — install Hermes Agent on the VM and configure:
#   - Gemini backend (main model gemini-flash-latest)
#   - Delegation/sub-agent model gemini-flash-lite-latest
#   - Telegram gateway on :8644 (systemd hermes.service)
# Secrets arrive via environment variables ONLY (GitHub Actions secrets ->
# IAP SSH env). They are never echoed, logged, or committed.
set -euo pipefail

: "${GEMINI_API_KEY:?GEMINI_API_KEY env var required}"
: "${TELEGRAM_BOT_TOKEN:?TELEGRAM_BOT_TOKEN env var required}"

HERMES_USER="hermes"
HERMES_HOME="/home/${HERMES_USER}"
HERMES_DIR="${HERMES_HOME}/.hermes"

id -u "${HERMES_USER}" >/dev/null 2>&1 || useradd -m -s /bin/bash "${HERMES_USER}"

# ---- 1. Install Hermes (per-user layout: ~/.hermes/) ----
if [ ! -x "${HERMES_DIR}/hermes-agent/venv/bin/python3" ]; then
  echo "[hermes] installing Hermes Agent..."
  sudo -u "${HERMES_USER}" bash -c "cd '${HERMES_HOME}' && curl -fsSL https://hermes-agent.nousresearch.com/install.sh | bash"
else
  echo "[hermes] already installed, skipping"
fi

# ---- 2. Secrets file (600, hermes-owned) ----
umask 077
mkdir -p "${HERMES_DIR}"
cat > "${HERMES_DIR}/.env" <<EOF
GEMINI_API_KEY=${GEMINI_API_KEY}
TELEGRAM_BOT_TOKEN=${TELEGRAM_BOT_TOKEN}
EOF
# Optional allowlist: comma-separated Telegram numeric IDs (falls back to DM pairing)
if [ -n "${TELEGRAM_ALLOWED_USERS:-}" ]; then
  echo "TELEGRAM_ALLOWED_USERS=${TELEGRAM_ALLOWED_USERS}" >> "${HERMES_DIR}/.env"
fi
chmod 600 "${HERMES_DIR}/.env"

# ---- 3. Model config: Gemini main + Gemini Lite delegation ----
cat > "${HERMES_DIR}/config.yaml" <<'YAML'
model:
  provider: gemini
  default: gemini-flash-latest
delegation:
  provider: gemini
  model: gemini-flash-lite-latest
YAML

chown -R "${HERMES_USER}:${HERMES_USER}" "${HERMES_DIR}"

# ---- 4. Gateway: official user service (per Hermes docs) ----
# Remove the earlier hand-rolled system unit if present.
if [ -f /etc/systemd/system/hermes.service ]; then
  systemctl disable --now hermes 2>/dev/null || true
  rm -f /etc/systemd/system/hermes.service
  systemctl daemon-reload
fi

# Linger first: starts the user systemd manager and creates /run/user/<uid>
# (headless box — no login session, so the user bus must be brought up manually).
loginctl enable-linger "${HERMES_USER}"
HERMES_UID="$(id -u "${HERMES_USER}")"
install -d -m 700 -o "${HERMES_USER}" -g "${HERMES_USER}" "/run/user/${HERMES_UID}"
sleep 2

run_as_hermes() {
  sudo -u "${HERMES_USER}" env \
    XDG_RUNTIME_DIR="/run/user/${HERMES_UID}" \
    DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/${HERMES_UID}/bus" \
    "$@"
}

# `hermes gateway install` creates the user service (hermes-gateway);
# linger makes it start at boot.
run_as_hermes "${HERMES_HOME}/.local/bin/hermes" gateway install
run_as_hermes "${HERMES_HOME}/.local/bin/hermes" gateway start

echo "[hermes] setup complete"
echo "[hermes] verify: journalctl --user -u hermes-gateway -n 50"

