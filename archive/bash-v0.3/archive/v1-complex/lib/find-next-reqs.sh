#!/usr/bin/env bash
# find-next-reqs.sh — Auto-detect available requirements
# Outputs space-separated list of REQ IDs that are ready to run

set -e

source "${REQDRIVE_ROOT}/lib/config.sh"
reqdrive_load_config

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Get all REQ IDs from the dependency map in the manifest
ALL_REQS=$(jq -r '.requirements.dependencies // {} | keys[]' "$REQDRIVE_MANIFEST")

if [ -z "$ALL_REQS" ]; then
  echo "No requirements defined in manifest dependencies." >&2
  exit 1
fi

READY_REQS=""

for REQ in $ALL_REQS; do
  REQ_SLUG=$(echo "$REQ" | tr '[:upper:]' '[:lower:]')
  BRANCH="$REQDRIVE_AGENT_BRANCH_PREFIX/$REQ_SLUG"

  # Skip if this REQ already has an open PR
  if command -v gh &>/dev/null; then
    OPEN_PR=$(gh pr list --state open --head "$BRANCH" --json number --jq 'length' 2>/dev/null || echo "0")
    if [ "$OPEN_PR" != "0" ]; then
      continue
    fi

    # Skip if this REQ already has a merged PR
    MERGED_PR=$(gh pr list --state merged --head "$BRANCH" --json number --jq 'length' 2>/dev/null || echo "0")
    if [ "$MERGED_PR" != "0" ]; then
      continue
    fi
  fi

  # Skip if branch already exists with work on it
  if git show-ref --verify --quiet "refs/heads/$BRANCH" 2>/dev/null; then
    continue
  fi

  # Check if dependencies are met
  if bash "$SCRIPT_DIR/check-deps.sh" "$REQ" >/dev/null 2>&1; then
    READY_REQS+="$REQ "
  fi
done

if [ -z "$READY_REQS" ]; then
  echo "No REQs ready to run (all blocked by dependencies or already processed)" >&2
  exit 1
fi

echo "$READY_REQS"
