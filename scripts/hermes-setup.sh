#!/usr/bin/env bash
# hermes-setup.sh — native Hermes Agent install for a dedicated service user.
#
# Oracle Linux 10 notes:
#   * Hermes' installer branches on the distro ID from /etc/os-release and has
#     no case for `ol`, so it never installs Chromium system libraries on RPM
#     hosts. provision.sh installs that exact list, and we pin the Playwright
#     platform to the Ubuntu 24.04 arm64 build (OL10 is glibc 2.39, same).
#   * --skip-computer-use: the cua-driver drives a GUI desktop; this box is
#     headless, so it is a 660-second download with nothing to control.
#   * Secrets and config arrive from cloud-init (/etc/hermes/*), never here.
#
# Idempotent; safe to re-run.
set -euo pipefail

HERMES_USER=hermes
HERMES_HOME=/home/hermes
HERMES_DIR="${HERMES_HOME}/.hermes"
ENV_SRC=/etc/hermes/hermes.env
CFG_SRC=/etc/hermes/config.yaml
HERMES_BIN="${HERMES_HOME}/.local/bin/hermes"

log() { printf "[hermes] %s\n" "$*"; }

id -u "${HERMES_USER}" >/dev/null 2>&1 || useradd -m -s /bin/bash "${HERMES_USER}"

# --- 1. Install (idempotent) ------------------------------------------------
if [ ! -x "${HERMES_DIR}/hermes-agent/venv/bin/python3" ]; then
  log "installing..."
  sudo -u "${HERMES_USER}" env HOME="${HERMES_HOME}" \
    PLAYWRIGHT_HOST_PLATFORM_OVERRIDE=ubuntu24.04-arm64 \
    bash -c 'cd "$HOME" && curl -fsSL https://hermes-agent.nousresearch.com/install.sh | bash -s -- --skip-setup --skip-computer-use --non-interactive'
fi

# --- 2. Secrets + model config ---------------------------------------------
# 0600 before the keys land on disk, as the docs recommend.
install -d -m 0700 -o "${HERMES_USER}" -g "${HERMES_USER}" "${HERMES_DIR}"
install -m 0600 -o "${HERMES_USER}" -g "${HERMES_USER}" "${ENV_SRC}" "${HERMES_DIR}/.env"
install -m 0644 -o "${HERMES_USER}" -g "${HERMES_USER}" "${CFG_SRC}" "${HERMES_DIR}/config.yaml"

# --- 3. Gateway as a user service that survives reboots --------------------
loginctl enable-linger "${HERMES_USER}"
HERMES_UID="$(id -u "${HERMES_USER}")"

# Bring the per-user systemd manager up NOW. enable-linger only covers future
# boots; a cloud-init run has no login session, so /run/user/$UID and its
# sockets do not exist yet and `hermes gateway install` aborts with
# UserSystemdUnavailableError. Starting the user@ template as root is the
# supported way to launch the manager immediately.
# Do NOT create /run/user/$UID by hand: that races logind, leaves the manager
# down, and can leave the directory with the wrong SELinux label.
systemctl start "user@${HERMES_UID}.service" 2>/dev/null || true
for _ in $(seq 1 30); do
  if [ -S "/run/user/${HERMES_UID}/bus" ] || [ -S "/run/user/${HERMES_UID}/systemd/private" ]; then
    break
  fi
  sleep 1
done

run_as_hermes() {
  if [ -S "/run/user/${HERMES_UID}/bus" ]; then
    sudo -u "${HERMES_USER}" env HOME="${HERMES_HOME}" \
      XDG_RUNTIME_DIR="/run/user/${HERMES_UID}" \
      DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/${HERMES_UID}/bus" "$@"
  else
    sudo -u "${HERMES_USER}" env HOME="${HERMES_HOME}" \
      XDG_RUNTIME_DIR="/run/user/${HERMES_UID}" "$@"
  fi
}

run_as_hermes "${HERMES_BIN}" gateway install
# restart (not start): a running service must pick up the rewritten .env
run_as_hermes "${HERMES_BIN}" gateway restart || run_as_hermes "${HERMES_BIN}" gateway start

# Stable path for root and cron. Use the venv launcher: the repo's `hermes`
# script with system Python raises ModuleNotFoundError: dotenv.
ln -sfn "${HERMES_DIR}/hermes-agent/venv/bin/hermes" /usr/local/bin/hermes

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

if run_as_hermes systemctl --user is-active --quiet hermes-gateway; then
  log "hermes-gateway is active"
else
  log "WARNING: hermes-gateway is not active — journalctl --user -u hermes-gateway"
fi
run_as_hermes journalctl --user -u hermes-gateway -n 80 --no-pager 2>/dev/null \
  | grep -iE "telegram|polling|conflict|error" | tail -10 || true
run_as_hermes "${HERMES_BIN}" doctor 2>&1 | tail -20 || true
log "setup complete"
