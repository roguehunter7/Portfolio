#!/usr/bin/env bash
# hermes-backup.sh — snapshot the Hermes state directory to OCI Object Storage.
#
# Keyless: the instance authenticates with its instance principal (dynamic group
# + bucket-scoped policy, both in infra/oci/main.tf), so no key file lives on
# the box. The services stop for the tar so a half-written state file can never
# be captured. Retention: the newest $KEEP objects, which sort chronologically
# because every name carries a UTC timestamp.
set -euo pipefail

. /etc/hermes/backup.conf

DATA="/home/hermes/.hermes"
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT

log() { printf '[hermes-backup] %s\n' "$*"; }

[ -d "${DATA}" ] || { log "no ${DATA} yet — skipping"; exit 0; }

# Stop both units for a consistent snapshot; "not running" is not an error.
systemctl stop hermes-gateway.service hermes-dashboard.service || true
# The installer re-clones its checkout, so only state is worth storing.
tar -czf "${TMP}/hermes-${STAMP}.tar.gz" \
  --exclude='.hermes/hermes-agent' \
  --exclude='.hermes/hermes-agent/*' \
  -C /home/hermes .hermes
systemctl start hermes-gateway.service hermes-dashboard.service || true

oci --auth instance_principal --region "${REGION}" os object put \
  --namespace "${OCI_NAMESPACE}" --bucket-name "${BUCKET}" \
  --name "hermes-${STAMP}.tar.gz" --file "${TMP}/hermes-${STAMP}.tar.gz" --force >/dev/null

# Prune everything older than the newest $KEEP. ls prints names one per line.
oci --auth instance_principal --region "${REGION}" os object list \
  --namespace "${OCI_NAMESPACE}" --bucket-name "${BUCKET}" \
  --query 'data[].name' --raw-output \
  | LC_ALL=C sort | head -n -"${KEEP}" | while read -r old; do
    [ -n "${old}" ] || continue
    oci --auth instance_principal --region "${REGION}" os object delete \
      --namespace "${OCI_NAMESPACE}" --bucket-name "${BUCKET}" \
      --object-name "${old}" --force >/dev/null </dev/null
    log "pruned ${old}"
  done

log "uploaded hermes-${STAMP}.tar.gz"
