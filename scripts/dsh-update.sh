#!/usr/bin/env bash
# dsh-update.sh — weekly DeepSeek Harness refresh (alpha channel) with rollback.
#
# DSH is in developer preview and breaks compatibility often, so an unattended
# update must be able to undo itself. This job:
#   1. remembers the installed version
#   2. runs dsh-setup.sh (npm install -g @deepseek-ai/dsh@alpha + plugin + unit)
#   3. waits for the authenticated proxy's health endpoint
#   4. reinstalls the previous version and restarts if that fails
#
# The proxy is the only way in from the internet and it fails closed, so
# "updated but proxy down" must never survive the night. ttyd/tmux is the
# manual escape hatch if even the rollback fails.
set -uo pipefail   # no -e: the health check below is the real gate

LOG=/var/log/dsh-update.log
exec >>"$LOG" 2>&1
echo "=== $(date -Is) dsh update start ==="

DSH_BIN=/home/ubuntu/.npm-global/bin/dsh
HEALTH=http://127.0.0.1:3080/_dsh_reverse_proxy/healthz

previous="$("${DSH_BIN}" --version 2>/dev/null || true)"
echo "installed: ${previous:-unknown}"

# Update. Failure here is not fatal on its own — the health check decides, and
# a half-finished install is exactly the case rollback exists for.
bash /usr/local/sbin/dsh-setup.sh || echo "dsh-setup.sh exited $?"

healthy() {
  systemctl is-active --quiet dsh-web || return 1
  for _ in $(seq 1 24); do
    curl -fsS -m 5 "${HEALTH}" >/dev/null 2>&1 && return 0
    sleep 5
  done
  return 1
}

if healthy; then
  echo "=== $(date -Is) ok, running $("${DSH_BIN}" --version 2>/dev/null) ==="
  exit 0
fi

echo "health check failed; rolling back to ${previous:-unknown}"
if [ -n "${previous}" ]; then
  sudo -u ubuntu bash -c '
    export NVM_DIR="$HOME/.nvm"
    [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
    export PATH="$HOME/.npm-global/bin:$PATH"
    npm install -g "@deepseek-ai/dsh@'"${previous}"'"
  ' && systemctl restart dsh-web
fi

if healthy; then
  echo "=== $(date -Is) rolled back to ${previous:-unknown} ==="
else
  echo "=== $(date -Is) STILL UNHEALTHY — needs manual attention (use ttyd) ==="
fi
