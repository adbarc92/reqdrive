#!/usr/bin/env bash
# deps.sh — Print dependency graph
# Dispatched from bin/reqdrive as: reqdrive deps

set -e

source "${REQDRIVE_ROOT}/lib/config.sh"
reqdrive_load_config

echo "Dependency Graph"
echo "════════════════════════════════════"
echo ""

# Get all REQ IDs from the dependency map
ALL_REQS=$(jq -r '.requirements.dependencies // {} | keys[]' "$REQDRIVE_MANIFEST" | sort -t'-' -k2 -n)

if [ -z "$ALL_REQS" ]; then
  echo "No dependencies defined in manifest."
  exit 0
fi

for REQ in $ALL_REQS; do
  DEPS=$(jq -r --arg req "$REQ" '.requirements.dependencies[$req] // [] | join(", ")' "$REQDRIVE_MANIFEST")
  if [ -z "$DEPS" ]; then
    printf "  %-10s (no dependencies)\n" "$REQ"
  else
    printf "  %-10s ← %s\n" "$REQ" "$DEPS"
  fi
done

echo ""

# Show tiers (group by dependency depth)
echo "Execution Tiers"
echo "────────────────────────────────────"

# Tier 0: no dependencies
TIER=0
RESOLVED=""

while true; do
  TIER_REQS=""
  for REQ in $ALL_REQS; do
    # Skip already resolved
    if echo "$RESOLVED" | grep -qw "$REQ"; then
      continue
    fi
    # Check if all deps are resolved
    DEPS=$(jq -r --arg req "$REQ" '.requirements.dependencies[$req] // [] | .[]' "$REQDRIVE_MANIFEST")
    ALL_MET=true
    for DEP in $DEPS; do
      if ! echo "$RESOLVED" | grep -qw "$DEP"; then
        ALL_MET=false
        break
      fi
    done
    if [ "$ALL_MET" = true ]; then
      TIER_REQS+="$REQ "
    fi
  done

  if [ -z "$TIER_REQS" ]; then
    # Check for unresolvable (circular) deps
    REMAINING=""
    for REQ in $ALL_REQS; do
      if ! echo "$RESOLVED" | grep -qw "$REQ"; then
        REMAINING+="$REQ "
      fi
    done
    if [ -n "$REMAINING" ]; then
      echo "  WARNING: Circular dependencies detected: $REMAINING"
    fi
    break
  fi

  echo "  Tier $TIER: $TIER_REQS"
  RESOLVED+="$TIER_REQS"
  TIER=$((TIER + 1))
done
