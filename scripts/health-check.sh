#!/usr/bin/env bash
# health-check.sh — Verify the proxy is deployed and in READY state
# Usage: ./health-check.sh <APIGEE_ORG> <APIGEE_ENV> <PROXY_NAME>
set -euo pipefail

ORG="$1"; ENV="$2"; PROXY="$3"
TOKEN=$(gcloud auth print-access-token)

echo "==> Health check: ${PROXY} in ${ENV}..."

for attempt in 1 2 3 4 5; do
  RESPONSE=$(curl -sf \
    -H "Authorization: Bearer ${TOKEN}" \
    "https://apigee.googleapis.com/v1/organizations/${ORG}/environments/${ENV}/apis/${PROXY}/deployments")
  REVISION=$(echo "${RESPONSE}" | jq -r '.deployments[0].revision // empty')
  STATE=$(echo "${RESPONSE}" | jq -r '.deployments[0].state // empty')

  if [[ -n "${REVISION}" && ( -z "${STATE}" || "${STATE}" == "READY" ) ]]; then
    echo "    Revision ${REVISION} deployed${STATE:+ (state: ${STATE})}"
    echo "==> Health check passed."
    exit 0
  fi

  echo "    Attempt ${attempt}: revision=${REVISION:-none} state=${STATE:-<none>} — retrying..."
  sleep 10
done

echo "ERROR: Deployment not healthy after 5 attempts" >&2
echo "${RESPONSE}" | jq '.' >&2
exit 1
