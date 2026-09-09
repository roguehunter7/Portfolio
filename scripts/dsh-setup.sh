#!/usr/bin/env bash
# dsh-setup.sh — install DeepSeek Harness and serve it behind the auth proxy.
#
# Oracle Linux 10 specifics: Node comes from dnf (appstream, 22.x) so there is
# no nvm and no NodeSource; the service user is `opc` (the OCI default).
#
# Idempotent; safe to re-run. What it does:
#   1. installs/updates the newest PUBLISHED @deepseek-ai/dsh, whatever channel
#      it landed on (npm's `versions` list is publish-ordered; DSH ships alphas
#      ahead of `latest` today)
#   2. adds the dsh-full-remote reverse proxy to the web profile
#   3. seeds ~/.dsh/reverse-proxy.json so the proxy auto-starts on :3080 while
#      the harness itself stays on loopback :3082
#   4. installs and restarts dsh-web.service (Restart=always, survives reboots)
#
# Why the proxy: `dsh web --trusted-host dsh.sreeramkr.com` opens the harness
# Host/Origin fence to a public hostname and leaves the per-process startup
# token as the only credential (pasted into the URL after every restart).
# dsh-full-remote sits in front instead: one login per device (30-day cookie),
# 192-bit token in a 0600 state file, audit log, login lockout, and Host/Origin
# rewritten to loopback so settings/credentials APIs keep working remotely.
# cloudflared keeps pointing at :3080, so the tunnel route never changes, and
# :3082 is never exposed — fail-closed if the proxy is down.
set -euo pipefail

DSH_USER="${DSH_USER:-opc}"
DSH_USER_HOME="/home/${DSH_USER}"
DSH_HOME_DIR="${DSH_USER_HOME}/.dsh"
STATE_FILE="${DSH_HOME_DIR}/reverse-proxy.json"
HARNESS_PORT="${HARNESS_PORT:-3082}"   # dsh web itself — loopback only
PROXY_PORT="${PROXY_PORT:-3080}"       # cloudflared target: auth + audit here
UNIT=/etc/systemd/system/dsh-web.service
DSH_BIN="${DSH_USER_HOME}/.npm-global/bin/dsh"

log() { printf "[dsh] %s\n" "$*"; }

# --- 1 + 2. DSH, pnpm and the reverse-proxy plugin, as the unprivileged user -
# npm runs as the service user, never as root: DSH's dependency tree builds
# node-pty and koffi from source, and running install scripts as root is the
# classic `sudo npm install` anti-pattern.
# npm 11+ gates install scripts behind `allow-scripts`; OL10's Node 22 ships
# npm 10, where they run by default. The allowlist is seeded only when npm is
# new enough to honour it, so a future npm upgrade cannot silently block the
# native builds.
sudo -u "${DSH_USER}" env HOME="${DSH_USER_HOME}" \
     PATH="${DSH_USER_HOME}/.npm-global/bin:/usr/bin:/bin" bash -c '
  set -euo pipefail
  NPMRC="$HOME/.npmrc"
  touch "$NPMRC"
  grep -q "^prefix=" "$NPMRC" || echo "prefix=$HOME/.npm-global" >> "$NPMRC"
  if [ "$(npm --version | cut -d. -f1)" -ge 11 ]; then
    grep -q "^allow-scripts=" "$NPMRC" || echo \
      "allow-scripts=@deepseek-ai/dsh-subprocess-local,koffi,node-pty,@google/genai,protobufjs" >> "$NPMRC"
  fi
  candidate="$(npm view @deepseek-ai/dsh versions --json | jq -r "last")"
  echo "[dsh] installing @deepseek-ai/dsh@${candidate}"
  npm install -g "@deepseek-ai/dsh@${candidate}"
  # `dsh plugin` is a thin pnpm forwarder and hard-fails without pnpm on PATH.
  npm install -g pnpm
  dsh plugin --profile web add dsh-full-remote
'

[ -x "${DSH_BIN}" ] || { log "dsh not found at ${DSH_BIN}"; exit 1; }

# --- 3. Reverse-proxy state: enabled on :3080, harness on :3082 -------------
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

# --- 4. systemd unit --------------------------------------------------------
# Node is a system package now, so PATH is stable — no resolved nvm dir, and no
# re-run needed after a Node upgrade.
cat > "${UNIT}" <<EOF
[Unit]
Description=DeepSeek Harness web UI (loopback ${HARNESS_PORT}; dsh-full-remote proxy on ${PROXY_PORT})
After=network-online.target
Wants=network-online.target

[Service]
User=${DSH_USER}
Group=${DSH_USER}
WorkingDirectory=${DSH_USER_HOME}/Portfolio
Environment=HOME=${DSH_USER_HOME}
Environment=PATH=/usr/bin:/bin:${DSH_USER_HOME}/.npm-global/bin
# Optional: the harness LLM credential. The credentials provider ranks the
# inherited environment above ~/.dsh/.credentials.yaml.
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