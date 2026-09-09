#!/bin/bash
# dsh-update.sh — weekly DeepSeek Harness refresh + restart.
#
# Installs the newest PUBLISHED version, whatever channel it landed on: npm's
# `versions` list is publish-ordered, so `last` is the most recent publish
# regardless of dist-tags (DSH publishes alphas ahead of `latest` today).
# npm must run as the service user (its dependency tree builds node-pty/koffi
# from source); the plugin refresh keeps the auth proxy compatible with a moving
# core; the restart needs root.
set -euo pipefail

DSH_USER=opc
sudo -u "${DSH_USER}" env HOME="/home/${DSH_USER}" \
  PATH="/home/${DSH_USER}/.npm-global/bin:/usr/bin:/bin" bash -c '
  set -euo pipefail
  candidate="$(npm view @deepseek-ai/dsh versions --json | jq -r "last")"
  echo "[dsh-update] installing ${candidate}"
  npm install -g "@deepseek-ai/dsh@${candidate}"
  dsh plugin --profile web add dsh-full-remote
'

systemctl restart dsh-web
printf "[dsh-update] %s now at %s\n" "$(date -Is)" "$(/home/opc/.npm-global/bin/dsh --version)"