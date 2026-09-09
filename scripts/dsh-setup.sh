#!/usr/bin/env bash
# dsh-setup.sh — install DeepSeek Harness and serve it safely at the edge.
#
# Idempotent; safe to re-run. What it does:
#   1. installs/updates @deepseek-ai/dsh from the `alpha` channel for the
#      `ubuntu` user (nvm-managed Node). DSH is in developer preview and ships
#      faster than `latest`, which currently trails by two minor lines; the
#      weekly dsh-update.sh refreshes this and rolls back if it breaks.
#   2. adds the dsh-full-remote reverse proxy to the web profile
#   3. seeds ~/.dsh/reverse-proxy.json so the proxy auto-starts on :3080 while
#      the harness itself stays on loopback :3082
#   4. installs and starts dsh-web.service (Restart=always, survives reboots)
#
# Why the proxy. `dsh web --trusted-host dsh.sreeramkr.com` opens the harness's
# Host/Origin fence to a public hostname and leaves the per-process startup
# token as the only credential — which then has to be pasted into the URL after
# every restart. dsh-full-remote sits in front instead: one login per device
# (30-day session cookie), 192-bit access token in a 0600 state file, audit log,
# login lockout, optional CIDR allowlist, and Host/Origin rewritten back to
# loopback so settings/credentials/directory APIs keep working remotely.
# cloudflared keeps pointing at :3080, so the tunnel route does not change, and
# the harness port (:3082) is never exposed — fail-closed if the proxy is down.
#
# NOTE: this starts/restarts DSH. Stop any hand-run `dsh web` first (e.g. the one
# in a tmux pane): it and the service cannot both own the harness port.
set -euo pipefail

DSH_USER="${DSH_USER:-ubuntu}"
DSH_USER_HOME="/home/${DSH_USER}"
DSH_HOME_DIR="${DSH_USER_HOME}/.dsh"
STATE_FILE="${DSH_HOME_DIR}/reverse-proxy.json"
HARNESS_PORT="${HARNESS_PORT:-3082}"   # dsh web itself — loopback only
PROXY_PORT="${PROXY_PORT:-3080}"       # cloudflared target: auth + audit here
WORKSPACE="${WORKSPACE:-${DSH_USER_HOME}/Portfolio}"
UNIT=/etc/systemd/system/dsh-web.service
DSH_BIN="${DSH_USER_HOME}/.npm-global/bin/dsh"

log() { printf '[dsh] %s\n' "$*"; }

# --- 1 + 2. DSH and the reverse-proxy plugin, as the unprivileged user -------
# A separate script keeps the nested quoting out of this one; nvm is sourced
# explicitly because ~/.bashrc early-returns for non-interactive shells.
cat > /tmp/dsh-user-setup.sh <<'EOS'
#!/bin/bash
set -euo pipefail
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
export PATH="$HOME/.npm-global/bin:$PATH"

# npm 11 gates install-time lifecycle scripts on global installs behind
# `allow-scripts` (empty = blocked, warning only), and DSH's native deps build
# there — node-pty and dsh-subprocess-local. Without the allowlist a fresh box
# gets a DSH whose terminal/subprocess tools are dead. Bare names, not pins, so
# a version bump cannot silently re-block them.
# The prefix matters too: it is what puts `dsh` in ~/.npm-global/bin, where the
# systemd unit below expects it (nvm's default global prefix is the node dir).
NPMRC="$HOME/.npmrc"
touch "$NPMRC"
grep -q '^prefix=' "$NPMRC" || echo "prefix=$HOME/.npm-global" >> "$NPMRC"
grep -q '^allow-scripts=' "$NPMRC" || echo 'allow-scripts=@deepseek-ai/dsh-subprocess-local,koffi,node-pty,@google/genai,protobufjs' >> "$NPMRC"

npm install -g @deepseek-ai/dsh@alpha
# `dsh plugin` is a thin pnpm forwarder and hard-fails without pnpm on PATH.
npm install -g pnpm
dsh plugin --profile web add dsh-full-remote
EOS
chmod 0755 /tmp/dsh-user-setup.sh
sudo -u "${DSH_USER}" /tmp/dsh-user-setup.sh
rm -f /tmp/dsh-user-setup.sh

[ -x "${DSH_BIN}" ] || { log "dsh not found at ${DSH_BIN}"; exit 1; }

# --- 3. Reverse-proxy state: enabled on :3080, harness on :3082 --------------
install -d -m 0700 -o "${DSH_USER}" -g "${DSH_USER}" "${DSH_HOME_DIR}"
if [ -f "${STATE_FILE}" ]; then
  # Preserve an existing access token and device sessions; only ensure the
  # proxy is on and listening where cloudflared expects it.
  jq '.enabled = true
      | .listenHost = (.listenHost // "127.0.0.1")
      | .listenPort = (.listenPort // '"${PROXY_PORT}"')' "${STATE_FILE}" > "${STATE_FILE}.tmp"
else
  # Deliberately no token: the plugin generates a 192-bit one on first load.
  printf '{\n  "enabled": true,\n  "listenHost": "127.0.0.1",\n  "listenPort": %s\n}\n' "${PROXY_PORT}" > "${STATE_FILE}.tmp"
fi
install -m 0600 -o "${DSH_USER}" -g "${DSH_USER}" "${STATE_FILE}.tmp" "${STATE_FILE}"
rm -f "${STATE_FILE}.tmp"

# --- Workspace ---------------------------------------------------------------
# The dev box exists to work on this repo; clone it once if it is missing.
if [ ! -d "${WORKSPACE}/.git" ]; then
  sudo -u "${DSH_USER}" git clone --depth=1 \
    https://github.com/roguehunter7/Portfolio.git "${WORKSPACE}" || true
fi
[ -d "${WORKSPACE}" ] || WORKSPACE="${DSH_USER_HOME}"

# --- 4. systemd unit ---------------------------------------------------------
# PATH carries the nvm Node bin dir resolved right now: a login shell would not
# load nvm (non-interactive ~/.bashrc early-return), and hardcoding a version
# would break on `nvm install --lts`. Re-run this script after upgrading Node.
NODE_BIN_DIR="$(sudo -u "${DSH_USER}" bash -c '
  export NVM_DIR="$HOME/.nvm"
  [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh" >/dev/null 2>&1
  dirname "$(command -v node)"
')"
[ -x "${NODE_BIN_DIR}/node" ] || { log "cannot resolve the Node.js bin dir"; exit 1; }

cat > "${UNIT}" <<EOF
[Unit]
Description=DeepSeek Harness web UI (loopback ${HARNESS_PORT}; dsh-full-remote proxy on ${PROXY_PORT})
After=network-online.target
Wants=network-online.target

[Service]
User=${DSH_USER}
Group=${DSH_USER}
WorkingDirectory=${WORKSPACE}
Environment=HOME=${DSH_USER_HOME}
Environment=PATH=${NODE_BIN_DIR}:${DSH_USER_HOME}/.npm-global/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
# Optional: the harness's LLM credential. The inherited environment outranks
# ~/.dsh/.credentials.yaml, so a rebuilt box needs no manual key entry.
EnvironmentFile=-/etc/dsh-web.env
ExecStart=${DSH_BIN} web --port ${HARNESS_PORT} --no-open
Restart=always
RestartSec=5
StandardOutput=append:/var/log/dsh-web.log
StandardError=append:/var/log/dsh-web.log

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable dsh-web.service
# restart, not `enable --now`: an update must actually pick up the new code
systemctl restart dsh-web.service
log "dsh web on 127.0.0.1:${HARNESS_PORT}; authenticated proxy on 127.0.0.1:${PROXY_PORT}"
log "access token: jq -r .accessToken ${STATE_FILE}"
