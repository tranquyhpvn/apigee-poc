#!/usr/bin/env bash
# rollback.sh — Interactive helper to dispatch the Apigee Rollback workflow.
# Lists available backup artifacts for an environment, prompts selection,
# and dispatches the rollback workflow with the right inputs.
#
# Usage: ./scripts/rollback.sh <env>
#   env: uat | preprod | prod
#
# Requires: gh CLI (authenticated), jq

set -euo pipefail

ENV="${1:-}"
if [[ -z "${ENV}" || ! "${ENV}" =~ ^(uat|preprod|prod)$ ]]; then
  echo "Usage: $0 <uat|preprod|prod>" >&2
  exit 1
fi

REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner)
PATTERN="^backup-manifest-${ENV}-rev[0-9]+-[0-9]+$"

echo "==> Fetching backup artifacts for ${ENV} from ${REPO}..."

# Fetch artifacts, filter to our env's pattern, sort by created_at desc, take 20
ARTIFACTS=$(gh api "repos/${REPO}/actions/artifacts" --paginate \
  --jq ".artifacts[] | select(.name | test(\"${PATTERN}\")) | select(.expired == false) | {name, created_at, size_in_bytes, expires_at}" \
  | jq -s 'sort_by(.created_at) | reverse | .[0:20]')

COUNT=$(echo "${ARTIFACTS}" | jq 'length')
if [[ "${COUNT}" == "0" ]]; then
  echo "No backup artifacts found for env=${ENV}." >&2
  echo "Pattern searched: ${PATTERN}" >&2
  exit 1
fi

# Display table
echo ""
printf "  %-3s %-6s %-20s %-14s %s\n" "#" "REV" "DATE" "RUN_ID" "ARTIFACT"
printf "  %-3s %-6s %-20s %-14s %s\n" "---" "------" "--------------------" "--------------" "-------------------------------------------"

i=1
echo "${ARTIFACTS}" | jq -r '.[] | .name + "|" + .created_at' | while IFS="|" read -r NAME CREATED; do
  REV=$(echo "${NAME}" | sed -E 's/.*-rev([0-9]+)-[0-9]+$/\1/')
  RUNID=$(echo "${NAME}" | sed -E 's/.*-rev[0-9]+-([0-9]+)$/\1/')
  DATE=$(echo "${CREATED}" | sed 's/T/ /' | sed 's/\..*//')
  printf "  %-3d %-6s %-20s %-14s %s\n" "${i}" "${REV}" "${DATE}" "${RUNID}" "${NAME}"
  i=$((i + 1))
done

echo ""
read -rp "Pick a number (1-${COUNT}) or 'q' to quit: " CHOICE
[[ "${CHOICE}" == "q" ]] && { echo "Aborted."; exit 0; }
if ! [[ "${CHOICE}" =~ ^[0-9]+$ ]] || (( CHOICE < 1 || CHOICE > COUNT )); then
  echo "Invalid choice." >&2
  exit 1
fi

PICKED=$(echo "${ARTIFACTS}" | jq -r ".[$((CHOICE - 1))].name")
PICKED_REV=$(echo "${PICKED}" | sed -E 's/.*-rev([0-9]+)-[0-9]+$/\1/')
PICKED_RUNID=$(echo "${PICKED}" | sed -E 's/.*-rev[0-9]+-([0-9]+)$/\1/')

echo ""
echo "Selected: rev ${PICKED_REV}, run_id ${PICKED_RUNID}"
echo ""
echo "Restore type:"
echo "  [1] Proxy only — re-deploy rev ${PICKED_REV}, leave KVMs/target servers as-is"
echo "  [2] Full       — proxy + KVMs + target servers from this artifact"
read -rp "Choice (1/2): " TYPE

case "${TYPE}" in
  1) USE_RUNID=false ;;
  2) USE_RUNID=true ;;
  *) echo "Invalid choice." >&2; exit 1 ;;
esac

echo ""
echo "Dry-run first?"
read -rp "  [y] preview only  [N] execute now  > " DRY
DRY_RUN=false
[[ "${DRY,,}" == "y" ]] && DRY_RUN=true

# Build dispatch command
ARGS=(-f "environment=${ENV}" -f "revision=${PICKED_REV}" -f "dry_run=${DRY_RUN}")
${USE_RUNID} && ARGS+=(-f "run_id=${PICKED_RUNID}")

echo ""
echo "Will dispatch:"
echo "  gh workflow run \"Apigee Rollback\" ${ARGS[*]}"
echo ""
read -rp "Confirm? [y/N] " OK
[[ "${OK,,}" != "y" ]] && { echo "Aborted."; exit 0; }

gh workflow run "Apigee Rollback" "${ARGS[@]}"
echo ""
echo "==> Dispatched. Watch progress:"
echo "    gh run watch \$(gh run list --workflow='Apigee Rollback' --limit 1 --json databaseId -q '.[0].databaseId')"
