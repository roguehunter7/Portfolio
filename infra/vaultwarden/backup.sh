#!/usr/bin/env bash
# backup.sh — nightly Vaultwarden SQLite backup to GCS.
#
# Uses Vaultwarden's built-in backup command (VACUUM INTO, safe while the app is
# live) and the instance's backup service account via the image's gcloud, so no
# key file lives on the host. Retention: the 5 newest db_*.sqlite3 objects.
set -euo pipefail

BUCKET="gs://main-project-402906-vaultwarden-backups/vaultwarden-backups"
DATA_DIR="/opt/vaultwarden/vw-data"
DATA_FILE="${DATA_DIR}/db.sqlite3"

# Guard: nothing to do before the stack is deployed.
[ -f "${DATA_FILE}" ] || { echo "no ${DATA_FILE} yet — skipping"; exit 0; }

# 1. In-container backup -> ${DATA_DIR}/db_<UTC timestamp>.sqlite3.
#    VACUUM INTO on a read-only connection; requires the container to be up.
docker exec vaultwarden /vaultwarden backup

# 2. Upload the newest local snapshot. Timestamp names sort chronologically.
LATEST="$(printf '%s\n' "${DATA_DIR}"/db_*.sqlite3 | LC_ALL=C sort | tail -n1)"
[ -f "${LATEST}" ] || { echo "no local db_*.sqlite3 snapshot found" >&2; exit 1; }
gcloud storage cp --quiet "${LATEST}" "${BUCKET}/" >/dev/null

# 3. Prune to the newest 5 (ls prints full gs:// URIs, one per line).
gcloud storage ls "${BUCKET}/" | LC_ALL=C sort | head -n -5 | while read -r old; do
  [ -n "${old}" ] || continue
  gcloud storage rm --quiet "${old}" >/dev/null </dev/null
  echo "pruned ${old}"
done

echo "backup complete: ${BUCKET}/$(basename "${LATEST}")"
