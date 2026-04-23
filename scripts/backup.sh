#!/usr/bin/env bash
# backup.sh — Snapshot current deployed revision + KVM entries + target servers
# Usage: ./backup.sh <APIGEE_ORG> <APIGEE_ENV> <PROXY_NAME> [output_file]
set -euo pipefail

ORG="$1"
ENV="$2"
PROXY="$3"
OUTPUT_FILE="${4:-backup-manifest.json}"

TOKEN=$(gcloud auth print-access-token)
BASE="https://apigee.googleapis.com/v1/organizations/${ORG}"

echo "==> Fetching current deployed revision for ${PROXY} in ${ENV}..."
DEPLOYMENT_RESPONSE=$(curl -s -H "Authorization: Bearer ${TOKEN}" \
  "${BASE}/environments/${ENV}/apis/${PROXY}/deployments" || echo '{}')
DEPLOYED=$(echo "${DEPLOYMENT_RESPONSE}" | jq -r '.deployments[0].revision // empty' 2>/dev/null || echo "")

if [[ -z "${DEPLOYED}" ]]; then
  echo "    No prior deployment found — writing empty-revision manifest (first-deploy scenario)."
else
  echo "    Revision: ${DEPLOYED}"
fi

echo "==> Fetching KVM entries for env ${ENV}..."
KVM_NAMES=$(curl -sf -H "Authorization: Bearer ${TOKEN}" \
  "${BASE}/environments/${ENV}/keyvaluemaps" | jq -r '.[]' 2>/dev/null || echo "")

KVM_DATA="{}"
for KVM in ${KVM_NAMES}; do
  ENTRIES=$(curl -sf -H "Authorization: Bearer ${TOKEN}" \
    "${BASE}/environments/${ENV}/keyvaluemaps/${KVM}/entries?pageSize=100" | \
    jq '[.keyValueEntries[] | {name: .name, value: .value}]' 2>/dev/null || echo "[]")
  KVM_DATA=$(echo "${KVM_DATA}" | jq --arg k "${KVM}" --argjson v "${ENTRIES}" '. + {($k): $v}')
done

echo "==> Fetching target servers for env ${ENV}..."
TS_NAMES=$(curl -sf -H "Authorization: Bearer ${TOKEN}" \
  "${BASE}/environments/${ENV}/targetservers" | jq -r '.[]' 2>/dev/null || echo "")

TARGET_SERVERS="{}"
for TS in ${TS_NAMES}; do
  DETAIL=$(curl -sf -H "Authorization: Bearer ${TOKEN}" \
    "${BASE}/environments/${ENV}/targetservers/${TS}" 2>/dev/null || echo "{}")
  TARGET_SERVERS=$(echo "${TARGET_SERVERS}" | jq --arg k "${TS}" --argjson v "${DETAIL}" '. + {($k): $v}')
done

jq -S -n \
  --arg org "${ORG}" \
  --arg env "${ENV}" \
  --arg proxy "${PROXY}" \
  --arg revision "${DEPLOYED}" \
  --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --argjson kvms "${KVM_DATA}" \
  --argjson targets "${TARGET_SERVERS}" \
  '{org: $org, env: $env, proxy: $proxy, revision: $revision,
    timestamp: $timestamp, kvms: $kvms, target_servers: $targets}' \
  > "${OUTPUT_FILE}"

echo "==> Backup manifest written to ${OUTPUT_FILE} (revision: ${DEPLOYED})"
