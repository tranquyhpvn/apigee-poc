#!/usr/bin/env bash
# list-backups.sh — Print a markdown table of recent backup-manifest artifacts.
# Usage: ./list-backups.sh <env> [limit]
#   env:   uat | preprod | prod
#   limit: max rows (default 10)
#
# Reads from gh api repos/<owner>/<repo>/actions/artifacts; output is markdown
# suitable for piping into $GITHUB_STEP_SUMMARY.
#
# Requires: gh CLI authenticated (GH_TOKEN env var in CI), jq

set -euo pipefail

ENV="${1:-}"
LIMIT="${2:-10}"

if [[ -z "${ENV}" || ! "${ENV}" =~ ^(uat|preprod|prod)$ ]]; then
  echo "Usage: $0 <uat|preprod|prod> [limit]" >&2
  exit 1
fi

REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner)
PATTERN="^backup-manifest-${ENV}-rev[0-9]+-[0-9]+$"

ARTIFACTS=$(gh api "repos/${REPO}/actions/artifacts" --paginate \
  --jq ".artifacts[] | select(.name | test(\"${PATTERN}\")) | select(.expired == false) | {name, created_at}" \
  | jq -s "sort_by(.created_at) | reverse | .[0:${LIMIT}]")

COUNT=$(echo "${ARTIFACTS}" | jq 'length')

echo ""
echo "## Recent backups — \`${ENV}\` (${COUNT} most recent)"
echo ""

if [[ "${COUNT}" == "0" ]]; then
  echo "_No backup artifacts found for \`${ENV}\`._"
  exit 0
fi

echo "| # | REV | DATE (UTC) | RUN_ID | ARTIFACT |"
echo "|---|-----|------------|--------|----------|"
echo "${ARTIFACTS}" | jq -r '
  to_entries[] |
  [(.key + 1 | tostring),
   (.value.name | capture("rev(?<r>[0-9]+)").r),
   (.value.created_at | sub("T"; " ") | sub("Z"; "")),
   (.value.name | capture("rev[0-9]+-(?<i>[0-9]+)").i),
   ("`" + .value.name + "`")]
  | "| " + join(" | ") + " |"'
