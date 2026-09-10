#!/usr/bin/env bash
# hermes-setup.sh — native Hermes Agent install for user opc, the box's user.
#
# Oracle Linux 10 notes:
#   * The installer has no case for the `ol` distro ID, so it never installs
#     Chromium system libraries on RPM hosts. provision.sh installs that list,
#     and we pin the Playwright platform to the Ubuntu 24.04 arm64 build
#     (OL10 is glibc 2.39, the same).
#   * --skip-computer-use: the cua-driver drives a GUI desktop; headless box.
#   * No system Node is installed, so the installer provisions its own managed
#     Node under ~/.hermes/node. That is deliberate: the gateway unit then does
#     not depend on nvm's Node, so a monthly Node bump cannot break it.
#   * Secrets and config arrive from cloud-init (/etc/hermes/*), never here.
#
# Idempotent; safe to re-run.
set -euo pipefail

HERMES_USER=opc
HERMES_HOME=/home/opc
HERMES_DIR="${HERMES_HOME}/.hermes"
ENV_SRC=/etc/hermes/hermes.env
CFG_SRC=/etc/hermes/config.yaml
HERMES_BIN="${HERMES_HOME}/.local/bin/hermes"

log() { printf "[hermes] %s\n" "$*"; }

# --- 1. Install (idempotent) ------------------------------------------------
# PATH is /usr/bin:/bin on purpose: with nvm off PATH the installer cannot pick
# up opc's shell Node and provisions its own managed tree instead.
if [ ! -x "${HERMES_DIR}/hermes-agent/venv/bin/python3" ]; then
  log "installing..."
  sudo -u "${HERMES_USER}" env HOME="${HERMES_HOME}" PATH=/usr/bin:/bin \
    PLAYWRIGHT_HOST_PLATFORM_OVERRIDE=ubuntu24.04-arm64 \
    bash -c 'cd "$HOME" && curl -fsSL https://hermes-agent.nousresearch.com/install.sh | bash -s -- --skip-setup --skip-computer-use --non-interactive'
fi

# --- 2. Secrets + model config ---------------------------------------------
# 0600 before the keys land on disk.
install -d -m 0700 -o "${HERMES_USER}" -g "${HERMES_USER}" "${HERMES_DIR}"
install -m 0600 -o "${HERMES_USER}" -g "${HERMES_USER}" "${ENV_SRC}" "${HERMES_DIR}/.env"
install -m 0644 -o "${HERMES_USER}" -g "${HERMES_USER}" "${CFG_SRC}" "${HERMES_DIR}/config.yaml"

# --- 3. Gateway as a user service that survives reboots --------------------
loginctl enable-linger "${HERMES_USER}"
HERMES_UID="$(id -u "${HERMES_USER}")"
# Start the per-user systemd manager now. A cloud-init run has no login session,
# so the manager (and its /run/user/$UID sockets) are not up yet and
# `hermes gateway install` aborts with UserSystemdUnavailableError.
systemctl start "user@${HERMES_UID}.service" 2>/dev/null || true
for _ in $(seq 1 30); do
  [ -S "/run/user/${HERMES_UID}/bus" ] && break
  sleep 1
done

run_as_user() {
  sudo -u "${HERMES_USER}" env HOME="${HERMES_HOME}" \
    XDG_RUNTIME_DIR="/run/user/${HERMES_UID}" \
    DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/${HERMES_UID}/bus" "$@"
}

run_as_user "${HERMES_BIN}" gateway install
# restart (not start): a running service must pick up the rewritten .env
run_as_user "${HERMES_BIN}" gateway restart || run_as_user "${HERMES_BIN}" gateway start

# --- 4. Prove Telegram is connected ----------------------------------------
# A bot cannot message a user first, so "working from start" means: token
# valid, no webhook stealing the long poll, gateway active. The user still has
# to open the bot once and send /start.
TG_TOKEN="$(sed -n "s/^TELEGRAM_BOT_TOKEN=//p" "${ENV_SRC}" | head -1)"
if [ -z "${TG_TOKEN}" ]; then
  log "WARNING: TELEGRAM_BOT_TOKEN is empty — Telegram will not connect"
else
  tg_api() { curl -fsS -m 10 "https://api.telegram.org/bot${TG_TOKEN}/$1" 2>/dev/null; }
  if tg_api getMe | grep -q '"ok":true'; then
    bot="$(tg_api getMe | sed -n 's/.*"username":"\([^"]*\)".*/\1/p')"
    log "token valid — open https://t.me/${bot} once and send /start"
  else
    log "WARNING: Telegram getMe failed — check TELEGRAM_BOT_TOKEN"
  fi
  if tg_api getWebhookInfo | grep -q '"url":""'; then
    log "no webhook set (long polling is free to run)"
  else
    log "a webhook was set — removing it so long polling can run"
    tg_api deleteWebhook >/dev/null || true
  fi
fi

if run_as_user systemctl --user is-active --quiet hermes-gateway; then
  log "hermes-gateway is active"
else
  log "WARNING: hermes-gateway is not active — journalctl --user -u hermes-gateway"
fi
run_as_user journalctl --user -u hermes-gateway -n 80 --no-pager 2>/dev/null \
  | grep -iE "telegram|polling|conflict|error" | tail -10 || true
run_as_user "${HERMES_BIN}" doctor 2>&1 | tail -20 || true
log "setup complete"
