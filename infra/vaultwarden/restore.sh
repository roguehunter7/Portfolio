#!/usr/bin/env bash
# restore.sh — install the newest db_*.sqlite3 backup from GCS as the live
# Vaultwarden database. Run on a fresh VM (after a rebuild) before docker
# compose up. No-op if a database already exists, so it is safe to call on
# every deploy. Uses the instance's backup service account via gcloud.
#
# Usage: restore.sh [required]
#   required=true  fail if the bucket holds no usable backup (rebuild path)
set -euo pipefail

BUCKET="gs://main-project-402906-vaultwarden-backups/vaultwarden-backups"
DATA_DIR="/opt/vaultwarden/vw-data"
DATA_FILE="${DATA_DIR}/db.sqlite3"
REQUIRED="${1:-false}"

# Guard: never clobber an existing vault (makes deploy-time invocation idempotent).
if [ -s "${DATA_FILE}" ]; then
  echo "existing ${DATA_FILE} — skipping restore"
  exit 0
fi

# Newest object wins: names are db_YYYYmmdd_HHMMSS.sqlite3, so sort ascending.
# ls exits 1 when the prefix is empty, hence "|| true".
LATEST="$(gcloud storage ls "${BUCKET}/" 2>/dev/null | LC_ALL=C sort | tail -n1 || true)"
if [ -z "${LATEST}" ]; then
  if [ "${REQUIRED}" = "true" ]; then
    echo "rebuild requested but no backup exists in ${BUCKET} — aborting" >&2
    exit 1
  fi
  echo "no backup yet — starting empty"
  exit 0
fi

# Download and validate BEFORE installing. A pre-fix raw copy can be an empty
# or torn SQLite file; refuse to install garbage over a fresh rebuild.
TMP="$(mktemp /tmp/vw-restore-XXXXXX.sqlite3)"
trap 'rm -f "${TMP}"' EXIT
gcloud storage cp --quiet "${LATEST}" "${TMP}" >/dev/null

python3 - "${TMP}" <<'PY'
import sqlite3, sys
con = sqlite3.connect(sys.argv[1])
assert con.execute("PRAGMA integrity_check").fetchone()[0] == "ok", "integrity_check failed"
assert con.execute("SELECT 1 FROM sqlite_master WHERE type='table' AND name='users'").fetchone(), "no users table"
PY

# Install: drop stale WAL/SHM, then put the snapshot in place.
mkdir -p "${DATA_DIR}"
rm -f "${DATA_FILE}-wal" "${DATA_FILE}-shm"
install -m 0600 -o root -g root "${TMP}" "${DATA_FILE}"
echo "restored ${LATEST} -> ${DATA_FILE}"
