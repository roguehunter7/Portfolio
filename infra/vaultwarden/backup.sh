#!/usr/bin/env bash
# backup.sh — nightly Vaultwarden SQLite backup to GCS using the instance's
# metadata service-account token. No keys on the host; uses the same bucket IAM
# as `gcloud` would (roles/storage.objectUser). Retention: keeps the 5 newest
# db-*.sqlite3 objects under vaultwarden-backups/.
set -euo pipefail

BUCKET="main-project-402906-vaultwarden-backups"
PREFIX="vaultwarden-backups"
DATA_FILE="/opt/vaultwarden/vw-data/db.sqlite3"
MBASE="https://storage.googleapis.com"

# Guard: nothing to do before the stack is deployed.
[ -f "${DATA_FILE}" ] || { echo "no ${DATA_FILE} yet — skipping"; exit 0; }

# 1. Service-account access token from the metadata server (credential-free).
TOKEN=$(curl -fsS -H "Metadata-Flavor: Google" \
  "http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/token" \
  | python3 -c "import sys,json;print(json.load(sys.stdin)['access_token'])")
AUTH="Authorization: Bearer ${TOKEN}"

# 2. Media upload of the SQLite database.
OBJECT="${PREFIX}/db-$(date +%F).sqlite3"
curl -fsS -X POST \
  -H "${AUTH}" \
  -H "Content-Type: application/octet-stream" \
  --data-binary @"${DATA_FILE}" \
  "${MBASE}/upload/storage/v1/b/${BUCKET}/o?uploadType=media&name=${OBJECT}" >/dev/null

# 3. Prune to the newest 5. Object names sort ascending == chronological for
#    YYYY-MM-DD, so dropping the last 5 (head -n -5) deletes the oldest.
names=$(curl -fsS -H "${AUTH}" \
  "${MBASE}/storage/v1/b/${BUCKET}/o?prefix=${PREFIX}/db-&fields=items(name)" \
  | python3 -c "import sys,json;d=json.load(sys.stdin);print('\n'.join(sorted(i['name'] for i in d.get('items',[]))))")

echo "${names}" | head -n -5 | while IFS= read -r name; do
  [ -n "${name}" ] || continue
  enc=$(python3 -c "import sys,urllib.parse;print(urllib.parse.quote(sys.argv[1],safe=''))" "${name}")
  curl -fsS -X DELETE -H "${AUTH}" "${MBASE}/storage/v1/b/${BUCKET}/o/${enc}" >/dev/null
  echo "pruned ${name}"
done

echo "backup complete: ${OBJECT}"
