#!/usr/bin/env bash
# check-deps.sh — Check if a REQ's dependencies are satisfied (merged to main)
# Usage: check-deps.sh <REQ-XX>
# Exit 0 = dependencies met, Exit 1 = dependencies not met

set -e

source "${REQDRIVE_ROOT}/lib/config.sh"
reqdrive_load_config

REQ="$1"

if [ -z "$REQ" ]; then
  echo "Usage: $0 <REQ-XX>" >&2
  exit 1
fi

# Get dependencies for this REQ from manifest
DEPS=$(reqdrive_get_deps "$REQ")

if [ -z "$DEPS" ]; then
  echo "  $REQ has no dependencies"
  exit 0
fi

echo "  $REQ depends on: $DEPS"

# Check each dependency has a merged PR or completed branch
ALL_MET=true
for DEP in $DEPS; do
  DEP_SLUG=$(echo "$DEP" | tr '[:upper:]' '[:lower:]')
  DEP_BRANCH="$REQDRIVE_AGENT_BRANCH_PREFIX/$DEP_SLUG"

  # Method 1: Check if dep branch has been merged to base branch
  if git branch --merged "$REQDRIVE_ORCH_BASE_BRANCH" 2>/dev/null | grep -q "$DEP_BRANCH"; then
    echo "  $DEP: merged to $REQDRIVE_ORCH_BASE_BRANCH"
    continue
  fi

  # Method 2: Check for closed+merged PR via gh CLI
  if command -v gh &>/dev/null; then
    MERGED=$(gh pr list --state merged --head "$DEP_BRANCH" --json number --jq 'length' 2>/dev/null || echo "0")
    if [ "$MERGED" != "0" ]; then
      echo "  $DEP: has merged PR"
      continue
    fi
  fi

  # Method 3: Check if the dep's commits are reachable from base branch
  if git merge-base --is-ancestor "$DEP_BRANCH" "$REQDRIVE_ORCH_BASE_BRANCH" 2>/dev/null; then
    echo "  $DEP: branch is ancestor of $REQDRIVE_ORCH_BASE_BRANCH"
    continue
  fi

  echo "  $DEP: NOT YET MERGED"
  ALL_MET=false
done

if [ "$ALL_MET" = true ]; then
  exit 0
else
  exit 1
fi
