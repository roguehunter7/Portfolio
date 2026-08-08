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
CLI="${HERMES_DIR}/hermes-agent/venv/bin/python3 ${HERMES_DIR}/hermes-agent/cli.py"

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

# ---- 4. systemd unit: Telegram gateway on :8644 ----
cat > /etc/systemd/system/hermes.service <<UNIT
[Unit]
Description=Hermes Agent (Telegram gateway)
After=network-online.target cloudflared.service
Wants=network-online.target

[Service]
User=${HERMES_USER}
WorkingDirectory=${HERMES_DIR}
EnvironmentFile=${HERMES_DIR}/.env
ExecStart=${CLI} gateway --host 0.0.0.0 --port 8644
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
UNIT

systemctl daemon-reload
systemctl enable --now hermes

echo "[hermes] setup complete"
echo "[hermes] verify: systemctl status hermes | journalctl -u hermes -n 50"
