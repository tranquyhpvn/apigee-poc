#!/usr/bin/env bash
# restore.sh — Re-deploy a recorded revision + restore KVM entries + target servers
# Usage: ./restore.sh <MANIFEST_FILE>
set -euo pipefail

MANIFEST="$1"
ORG=$(jq -r '.org' "${MANIFEST}")
ENV=$(jq -r '.env' "${MANIFEST}")
PROXY=$(jq -r '.proxy' "${MANIFEST}")
REVISION=$(jq -r '.revision' "${MANIFEST}")
TOKEN=$(gcloud auth print-access-token)
BASE="https://apigee.googleapis.com/v1/organizations/${ORG}"

echo "==> Restoring ${PROXY} rev ${REVISION} to ${ENV}..."
curl -sf -X POST \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json" \
  "${BASE}/environments/${ENV}/apis/${PROXY}/revisions/${REVISION}/deployments?override=true" \
  | jq '{state: .state, revision: .revision}'

echo "==> Restoring KVM entries..."
jq -r '.kvms | to_entries[] | "\(.key) \(.value | @json)"' "${MANIFEST}" | \
while IFS=" " read -r KVM_NAME ENTRIES; do
  echo "    KVM: ${KVM_NAME}"
  echo "${ENTRIES}" | jq -c '.[]' | while read -r ENTRY; do
    KEY=$(echo "${ENTRY}" | jq -r '.name')
    VAL=$(echo "${ENTRY}" | jq -r '.value')
    curl -sf -X PUT \
      -H "Authorization: Bearer ${TOKEN}" \
      -H "Content-Type: application/json" \
      -d "{\"name\": \"${KEY}\", \"value\": \"${VAL}\"}" \
      "${BASE}/environments/${ENV}/keyvaluemaps/${KVM_NAME}/entries/${KEY}" > /dev/null || \
    curl -sf -X POST \
      -H "Authorization: Bearer ${TOKEN}" \
      -H "Content-Type: application/json" \
      -d "{\"name\": \"${KEY}\", \"value\": \"${VAL}\"}" \
      "${BASE}/environments/${ENV}/keyvaluemaps/${KVM_NAME}/entries" > /dev/null
  done
done

echo "==> Restoring target servers..."
jq -c '.target_servers | to_entries[]' "${MANIFEST}" | while read -r TS; do
  TS_NAME=$(echo "${TS}" | jq -r '.key')
  TS_BODY=$(echo "${TS}" | jq '.value')
  # PUT to update existing target server; fallback POST to create if it was manually deleted
  curl -sf -X PUT \
    -H "Authorization: Bearer ${TOKEN}" \
    -H "Content-Type: application/json" \
    -d "${TS_BODY}" \
    "${BASE}/environments/${ENV}/targetservers/${TS_NAME}" > /dev/null || \
  curl -sf -X POST \
    -H "Authorization: Bearer ${TOKEN}" \
    -H "Content-Type: application/json" \
    -d "${TS_BODY}" \
    "${BASE}/environments/${ENV}/targetservers" > /dev/null
  echo "    Restored: ${TS_NAME}"
done

echo "==> Restore complete."
