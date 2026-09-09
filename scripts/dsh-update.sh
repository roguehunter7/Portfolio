#!/bin/bash
# dsh-update.sh — weekly DeepSeek Harness refresh (alpha channel) + restart.
#
# DSH is in developer preview and publishes alpha builds ahead of `latest`, so
# the box tracks @alpha. npm must run as the service user (its dependency tree
# builds node-pty/koffi from source); the plugin refresh keeps the auth proxy
# compatible with a moving core; the restart needs root.
set -euo pipefail

DSH_USER=opc
sudo -u "${DSH_USER}" env HOME="/home/${DSH_USER}" \
  PATH="/home/${DSH_USER}/.npm-global/bin:/usr/bin:/bin" bash -c '
  set -euo pipefail
  npm install -g @deepseek-ai/dsh@alpha
  dsh plugin --profile web add dsh-full-remote
'

systemctl restart dsh-web
printf "[dsh-update] %s now at %s\n" "$(date -Is)" "$(/home/opc/.npm-global/bin/dsh --version)"