#!/usr/bin/env bash
# sync-kvms.sh — Upsert KVM entries from versioned JSON files to Apigee
# Usage: ./sync-kvms.sh <APIGEE_ORG> <APIGEE_ENV> <KVMS_DIR>
set -euo pipefail

ORG="$1"; ENV="$2"; DIR="$3"
TOKEN=$(gcloud auth print-access-token)
BASE="https://apigee.googleapis.com/v1/organizations/${ORG}"

if [[ ! -d "${DIR}" ]] || ! ls "${DIR}"/*.json >/dev/null 2>&1; then
  echo "==> No KVM files in ${DIR}, skipping sync."
  exit 0
fi

for FILE in "${DIR}"/*.json; do
  KVM_NAME=$(jq -r '.name' "${FILE}")
  ENCRYPTED=$(jq -r '.encrypted // false' "${FILE}")
  echo "==> Syncing KVM: ${KVM_NAME} (encrypted=${ENCRYPTED})"

  # Ensure the KVM container exists (409 if already there — ignore)
  curl -s -X POST \
    -H "Authorization: Bearer ${TOKEN}" \
    -H "Content-Type: application/json" \
    -d "{\"name\":\"${KVM_NAME}\",\"encrypted\":${ENCRYPTED}}" \
    "${BASE}/environments/${ENV}/keyvaluemaps" > /dev/null

  # Upsert each entry: PUT first (update), POST fallback (create)
  jq -c '.entries[]' "${FILE}" | while read -r ENTRY; do
    KEY=$(echo "${ENTRY}" | jq -r '.name')
    VAL=$(echo "${ENTRY}" | jq -r '.value')
    curl -sf -X PUT \
      -H "Authorization: Bearer ${TOKEN}" \
      -H "Content-Type: application/json" \
      -d "{\"name\":\"${KEY}\",\"value\":\"${VAL}\"}" \
      "${BASE}/environments/${ENV}/keyvaluemaps/${KVM_NAME}/entries/${KEY}" > /dev/null 2>&1 || \
    curl -sf -X POST \
      -H "Authorization: Bearer ${TOKEN}" \
      -H "Content-Type: application/json" \
      -d "{\"name\":\"${KEY}\",\"value\":\"${VAL}\"}" \
      "${BASE}/environments/${ENV}/keyvaluemaps/${KVM_NAME}/entries" > /dev/null
    echo "    ${KEY} = ${VAL}"
  done
done

echo "==> KVM sync complete."
