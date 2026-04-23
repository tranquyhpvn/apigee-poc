#!/usr/bin/env bash
# health-check.sh — Verify the proxy is deployed and in READY state
# Usage: ./health-check.sh <APIGEE_ORG> <APIGEE_ENV> <PROXY_NAME>
set -euo pipefail

ORG="$1"; ENV="$2"; PROXY="$3"
TOKEN=$(gcloud auth print-access-token)

echo "==> Health check: ${PROXY} in ${ENV}..."
STATE=$(curl -sf \
  -H "Authorization: Bearer ${TOKEN}" \
  "https://apigee.googleapis.com/v1/organizations/${ORG}/environments/${ENV}/apis/${PROXY}/deployments" | \
  jq -r '.deployments[0].state // "UNKNOWN"')

echo "    Deployment state: ${STATE}"
[[ "${STATE}" == "READY" ]] || { echo "ERROR: Not READY (got: ${STATE})" >&2; exit 1; }
echo "==> Health check passed."
