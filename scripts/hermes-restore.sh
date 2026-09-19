#!/usr/bin/env bash
# hermes-restore.sh — install the newest Hermes state snapshot from OCI Object
# Storage. Run before the units start on a fresh instance. Safe to run on every
# deploy: a .restored marker makes it a no-op once state is in place.
#
# Usage: hermes-restore.sh [required]
#   required=true  fail when the bucket holds no snapshot (rebuild path)
set -euo pipefail

. /etc/hermes/backup.conf

REQUIRED="${1:-false}"
DATA="/home/hermes/.hermes"
MARKER="${DATA}/.restored"

log() { printf '[hermes-restore] %s\n' "$*"; }

if [ -e "${MARKER}" ]; then
  log "state already restored — skipping"
  exit 0
fi

# Newest object wins: names are hermes_<UTC timestamp>.tar.gz, so sort ascending.
LATEST="$(oci --auth instance_principal --region "${REGION}" os object list \
  --namespace "${OCI_NAMESPACE}" --bucket-name "${BUCKET}" \
  --query 'data[].name' --raw-output 2>/dev/null | LC_ALL=C sort | tail -n1 || true)"

if [ -z "${LATEST}" ] || [ "${LATEST}" = "null" ]; then
  if [ "${REQUIRED}" = "true" ]; then
    log "rebuild requested but ${BUCKET} holds no snapshot — aborting" >&2
    exit 1
  fi
  log "no snapshot yet — starting empty"
  exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT
oci --auth instance_principal --region "${REGION}" os object get \
  --namespace "${OCI_NAMESPACE}" --bucket-name "${BUCKET}" \
  --name "${LATEST}" --file "${TMP}/state.tar.gz" >/dev/null

# Validate before installing: a truncated upload or a hostile archive must never
# reach the live tree. The snapshot is extracted into /home/hermes, so absolute
# paths and parent traversal are refused outright.
tar -tzf "${TMP}/state.tar.gz" >/dev/null
if tar -tzf "${TMP}/state.tar.gz" | grep -qE '^/|(^|/)\.\.(/|$)'; then
  log "snapshot ${LATEST} contains unsafe paths — refusing" >&2
  exit 1
fi

install -d -m 0700 -o hermes -g hermes "${DATA}"
tar -xzf "${TMP}/state.tar.gz" -C /home/hermes
# Secrets are authoritative in the repo/CI chain, never in the snapshot.
install -m 0600 -o hermes -g hermes /etc/hermes/hermes.env "${DATA}/.env"
chown -R hermes:hermes "${DATA}"
touch "${MARKER}"
chown hermes:hermes "${MARKER}"
log "restored ${LATEST} into ${DATA}"
