#!/usr/bin/env bash
# hermes-restore.sh: install the newest Hermes state snapshot from OCI Object
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

# Newest object wins: names are hermes-<UTC timestamp>.zip, so sort ascending.
# The API answers in JSON (--raw-output only unquotes a single string value), so
# jq unrolls it first. The pattern also keeps a pre-zip .tar.gz object out of the
# running, since `hermes import` cannot read one.
LATEST="$(oci --auth instance_principal --region "${REGION}" os object list \
  --namespace "${OCI_NAMESPACE}" --bucket-name "${BUCKET}" \
  --query 'data[].name' 2>/dev/null \
  | jq -r '.[]?' | grep -E '^hermes-[0-9]{8}T[0-9]{6}Z\.zip$' | LC_ALL=C sort | tail -n1 || true)"

if [ -z "${LATEST}" ] || [ "${LATEST}" = "null" ]; then
  if [ "${REQUIRED}" = "true" ]; then
    log "rebuild requested but ${BUCKET} holds no snapshot — aborting" >&2
    exit 1
  fi
  install -d -m 0700 -o hermes -g hermes "${DATA}"
  printf 'started empty\n' > "${MARKER}"
  chown hermes:hermes "${MARKER}"
  log "no snapshot yet — starting empty"
  exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT
install -d -m 0700 -o hermes -g hermes "${TMP}"
oci --auth instance_principal --region "${REGION}" os object get \
  --namespace "${OCI_NAMESPACE}" --bucket-name "${BUCKET}" \
  --name "${LATEST}" --file "${TMP}/state.zip" >/dev/null

# `hermes import` replaces the previous tar extract: it is the inverse of the
# tool that wrote the archive, it restores owner-only modes for
# .env/auth.json/state.db (zipfile drops Unix mode bits), and it refuses to
# write a foreign gateway_state.json, pid or lock file over the fresh install,
# which is more than the path check below it used to do.
install -d -m 0700 -o hermes -g hermes "${DATA}"
sudo -u hermes env HOME=/home/hermes /home/hermes/.local/bin/hermes import \
  "${TMP}/state.zip" --force

# The archive carries a .env of its own, but the repo/CI copy stays
# authoritative on a rebuild: it is installed over whatever the snapshot held.
install -m 0600 -o hermes -g hermes /etc/hermes/hermes.env "${DATA}/.env"
printf 'restored %s\n' "${LATEST}" > "${MARKER}"
chown hermes:hermes "${MARKER}"
log "restored ${LATEST} into ${DATA}"
