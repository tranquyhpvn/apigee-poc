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

  # During sequenced rollouts there can be >1 deployment briefly. Require ALL READY.
  ALL_READY=$(echo "${RESPONSE}" | jq '[.deployments[]?.state // "READY"] | all(. == "READY")')
  LATEST_REV=$(echo "${RESPONSE}" | jq -r '[.deployments[]?.revision | tonumber] | max // empty')
  REV_STATES=$(echo "${RESPONSE}" | jq -r '[.deployments[]? | "rev\(.revision)=\(.state // "READY")"] | join(",")')

  if [[ "${ALL_READY}" == "true" && -n "${LATEST_REV}" ]]; then
    echo "    Latest revision: ${LATEST_REV} (deployments: ${REV_STATES:-none})"
    echo "==> Health check passed."
    exit 0
  fi

  echo "    Attempt ${attempt}: deployments=[${REV_STATES:-none}] — retrying..."
  sleep 10
done

echo "ERROR: Deployment not healthy after 5 attempts" >&2
echo "${RESPONSE}" | jq '.' >&2
exit 1
