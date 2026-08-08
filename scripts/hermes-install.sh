#!/usr/bin/env bash
# hermes-install.sh — install Hermes + configure DeepSeek/Telegram gateway (user service).
# Secrets arrive via env vars only (GitHub Actions -> IAP SSH); never logged or committed.
set -euo pipefail

: "${DEEPSEEK_API_KEY:?required}"
: "${TELEGRAM_BOT_TOKEN:?required}"

HERMES_USER="hermes"
HERMES_HOME="/home/${HERMES_USER}"
HERMES_DIR="${HERMES_HOME}/.hermes"

id -u "${HERMES_USER}" >/dev/null 2>&1 || useradd -m -s /bin/bash "${HERMES_USER}"

# 1. Install (idempotent)
if [ ! -x "${HERMES_DIR}/hermes-agent/venv/bin/python3" ]; then
  echo "[hermes] installing..."
  sudo -u "${HERMES_USER}" bash -c "cd '${HERMES_HOME}' && curl -fsSL https://hermes-agent.nousresearch.com/install.sh | bash"
fi

# 2. Secrets + model config
umask 077
mkdir -p "${HERMES_DIR}"
{
  echo "DEEPSEEK_API_KEY=${DEEPSEEK_API_KEY}"
  echo "TELEGRAM_BOT_TOKEN=${TELEGRAM_BOT_TOKEN}"
  # Official Telegram allowlist (docs: TELEGRAM_ALLOWED_USERS in ~/.hermes/.env)
  [ -n "${TELEGRAM_ALLOWED_USERS:-}" ] && echo "TELEGRAM_ALLOWED_USERS=${TELEGRAM_ALLOWED_USERS}"
} > "${HERMES_DIR}/.env"
chmod 600 "${HERMES_DIR}/.env"

cat > "${HERMES_DIR}/config.yaml" <<'YAML'
model:
  provider: deepseek
  default: deepseek-v4-flash
delegation:
  provider: deepseek
  model: deepseek-v4-flash
# All auxiliary tasks (titles, compression, web extract, vision, triage...)
# also use v4-flash: DeepSeek's budget tier — one rate limit + one billing,
# ~10x cheaper than the Gemini paid tier (which requires a ₹1000 top-up).
auxiliary:
  vision:
    provider: deepseek
    model: deepseek-v4-flash
  web_extract:
    provider: deepseek
    model: deepseek-v4-flash
  title_generation:
    provider: deepseek
    model: deepseek-v4-flash
  tts_audio_tags:
    provider: deepseek
    model: deepseek-v4-flash
  compression:
    provider: deepseek
    model: deepseek-v4-flash
  approval:
    provider: deepseek
    model: deepseek-v4-flash
  triage_specifier:
    provider: deepseek
    model: deepseek-v4-flash
  kanban_decomposer:
    provider: deepseek
    model: deepseek-v4-flash
  profile_describer:
    provider: deepseek
    model: deepseek-v4-flash
YAML
chown -R "${HERMES_USER}:${HERMES_USER}" "${HERMES_DIR}"

# 3. Gateway as user service (docs: hermes gateway install + linger for boot start)
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

run_as_hermes "${HERMES_HOME}/.local/bin/hermes" gateway install
# restart (not start): a running service must pick up the rewritten .env
run_as_hermes "${HERMES_HOME}/.local/bin/hermes" gateway restart || \
  run_as_hermes "${HERMES_HOME}/.local/bin/hermes" gateway start

echo "[hermes] setup complete"
