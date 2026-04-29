#!/usr/bin/env bash
# restore.sh — Re-deploy a recorded revision + restore KVM entries + target servers
# Usage: ./restore.sh [--dry-run] <MANIFEST_FILE>
set -euo pipefail

DRY_RUN=false
if [[ "${1:-}" == "--dry-run" ]]; then DRY_RUN=true; shift; fi

MANIFEST="$1"
ORG=$(jq -r '.org' "${MANIFEST}")
ENV=$(jq -r '.env' "${MANIFEST}")
PROXY=$(jq -r '.proxy' "${MANIFEST}")
REVISION=$(jq -r '.revision' "${MANIFEST}")
TOKEN=$(gcloud auth print-access-token)
BASE="https://apigee.googleapis.com/v1/organizations/${ORG}"

if $DRY_RUN; then
  echo "════════════════════════════════════════════════════════════"
  echo "  DRY RUN — no changes will be applied"
  echo "════════════════════════════════════════════════════════════"
fi

# ── Proxy revision ─────────────────────────────────────────────────────
echo "── Proxy ──────────────────────────────────────────────"
if [[ -n "${REVISION}" ]]; then
  CURRENT=$(curl -s -H "Authorization: Bearer ${TOKEN}" \
    "${BASE}/environments/${ENV}/apis/${PROXY}/deployments" | \
    jq -r '.deployments[0].revision // empty')
  if [[ "${CURRENT}" == "${REVISION}" ]]; then
    echo "  rev ${REVISION} already deployed — no-op"
  else
    if $DRY_RUN; then
      echo "  WOULD re-deploy: rev ${REVISION} (current: ${CURRENT:-none})"
    else
      echo "  Re-deploying rev ${REVISION} (current: ${CURRENT:-none})..."
      curl -sf -X POST \
        -H "Authorization: Bearer ${TOKEN}" \
        -H "Content-Type: application/json" \
        "${BASE}/environments/${ENV}/apis/${PROXY}/revisions/${REVISION}/deployments?override=true" \
        | jq '{state: .state, revision: .revision}'
    fi
  fi
else
  echo "  no prior revision in manifest — skipping proxy section"
fi

# ── KVM entries ────────────────────────────────────────────────────────
echo "── KVM entries ────────────────────────────────────────"
jq -r '.kvms | to_entries[] | "\(.key) \(.value | @json)"' "${MANIFEST}" | \
while IFS=" " read -r KVM_NAME ENTRIES; do
  echo "  KVM: ${KVM_NAME}"
  echo "${ENTRIES}" | jq -c '.[]' | while read -r ENTRY; do
    KEY=$(echo "${ENTRY}" | jq -r '.name')
    VAL=$(echo "${ENTRY}" | jq -r '.value')
    if $DRY_RUN; then
      CUR=$(curl -s -H "Authorization: Bearer ${TOKEN}" \
        "${BASE}/environments/${ENV}/keyvaluemaps/${KVM_NAME}/entries/${KEY}" | \
        jq -r '.value // "<missing>"')
      if [[ "${CUR}" == "${VAL}" ]]; then
        echo "    ${KEY}: \"${VAL}\" (no change)"
      else
        echo "    ${KEY}: \"${CUR}\" → \"${VAL}\""
      fi
    else
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
      echo "    ${KEY}: restored to \"${VAL}\""
    fi
  done
done

# ── Target servers ─────────────────────────────────────────────────────
echo "── Target servers ─────────────────────────────────────"
jq -c '.target_servers | to_entries[]' "${MANIFEST}" | while read -r TS; do
  TS_NAME=$(echo "${TS}" | jq -r '.key')
  TS_BODY=$(echo "${TS}" | jq '.value')
  if $DRY_RUN; then
    CUR=$(curl -s -H "Authorization: Bearer ${TOKEN}" \
      "${BASE}/environments/${ENV}/targetservers/${TS_NAME}")
    DIFF=$(jq -n --argjson cur "${CUR}" --argjson tgt "${TS_BODY}" \
      '{host: {cur: $cur.host, tgt: $tgt.host},
        port: {cur: $cur.port, tgt: $tgt.port},
        isEnabled: {cur: ($cur.isEnabled // true), tgt: ($tgt.isEnabled // true)}} |
       to_entries | map(select(.value.cur != .value.tgt))')
    if [[ "${DIFF}" == "[]" ]]; then
      echo "  ${TS_NAME}: no change"
    else
      echo "  ${TS_NAME}: changes →"
      echo "${DIFF}" | jq -r '.[] | "    \(.key): \(.value.cur) → \(.value.tgt)"'
    fi
  else
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
    echo "  ${TS_NAME}: restored"
  fi
done

if $DRY_RUN; then
  echo "════════════════════════════════════════════════════════════"
  echo "  DRY RUN complete (no changes applied)"
  echo "════════════════════════════════════════════════════════════"
else
  echo "==> Restore complete."
fi
