#!/usr/bin/env bash
# hermes-backup.sh: snapshot the Hermes state directory to OCI Object Storage.
#
# Keyless: the instance authenticates with its instance principal (dynamic group
# + bucket-scoped policy, both in infra/oci/main.tf), so no key file lives on
# the box.
#
# The snapshot is `hermes backup`, which copies every SQLite database through
# SQLite's own backup API (correct while the gateway keeps serving writers),
# leaves out the reinstallable trees (the checkout, node, the runtimes, plugin
# venvs, the tool caches), and exits non-zero if the archive came out
# incomplete. Nothing is stopped, so a run cannot interrupt a session; `set -e`
# then aborts this script before the upload, so the bucket only ever receives a
# complete archive.
#
# Retention: the newest $KEEP objects, which sort chronologically because every
# name carries a UTC timestamp.
set -euo pipefail

. /etc/hermes/backup.conf

STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT
# The snapshot runs as the home's owner, so hand it a directory it can write
# into; the upload below still runs as whoever cron or systemd invoked us.
install -d -m 0700 -o hermes -g hermes "${TMP}"

log() { printf '[hermes-backup] %s\n' "$*"; }

# HOME, not just HERMES_HOME: the CLI resolves its home from it.
sudo -u hermes env HOME=/home/hermes /home/hermes/.local/bin/hermes backup \
  -o "${TMP}/hermes-${STAMP}.zip"

oci --auth instance_principal --region "${REGION}" os object put \
  --namespace "${OCI_NAMESPACE}" --bucket-name "${BUCKET}" \
  --name "hermes-${STAMP}.zip" --file "${TMP}/hermes-${STAMP}.zip" --force >/dev/null

# Prune everything older than the newest $KEEP. The API answers in JSON and
# --raw-output only unquotes a single string value, so jq unrolls the list into
# one name per line; the grep keeps the prune off anything this script did not
# write. A list failure must not fail an otherwise good backup, hence the
# `|| true` on the list only: a failed delete below is still an error.
oci --auth instance_principal --region "${REGION}" os object list \
  --namespace "${OCI_NAMESPACE}" --bucket-name "${BUCKET}" \
  --query 'data[].name' \
  | jq -r '.[]?' \
  | grep -E '^hermes-[0-9]{8}T[0-9]{6}Z\.(zip|tar\.gz)$' \
  | LC_ALL=C sort | head -n -"${KEEP}" > "${TMP}/prune.txt" || true
while read -r old; do
  [ -n "${old}" ] || continue
  oci --auth instance_principal --region "${REGION}" os object delete \
    --namespace "${OCI_NAMESPACE}" --bucket-name "${BUCKET}" \
    --object-name "${old}" --force >/dev/null </dev/null
  log "pruned ${old}"
done < "${TMP}/prune.txt"

log "uploaded hermes-${STAMP}.zip"
