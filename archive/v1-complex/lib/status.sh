#!/usr/bin/env bash
# status.sh — Show pipeline run status
# Dispatched from bin/reqdrive as: reqdrive status [run-id]

set -e

source "${REQDRIVE_ROOT}/lib/config.sh"
reqdrive_load_config

STATE_DIR="$(reqdrive_resolve_path "$REQDRIVE_ORCH_STATE_DIR")/runs"

RUN_ID="${1:-}"

if [ -z "$RUN_ID" ]; then
  # Show latest run
  if [ ! -d "$STATE_DIR" ]; then
    echo "No pipeline runs found."
    exit 0
  fi
  RUN_ID=$(ls -t "$STATE_DIR" 2>/dev/null | head -1)
fi

if [ -z "$RUN_ID" ] || [ ! -d "$STATE_DIR/$RUN_ID" ]; then
  echo "No pipeline runs found."
  exit 0
fi

echo "Pipeline run: $RUN_ID"
echo "─────────────────────────────────────"
for status_file in "$STATE_DIR/$RUN_ID"/*-status.json; do
  [ -f "$status_file" ] || continue
  REQ=$(jq -r '.req' "$status_file")
  STATUS=$(jq -r '.status' "$status_file")
  BRANCH=$(jq -r '.branch // ""' "$status_file")
  ATTEMPTS=$(jq -r '.verifyAttempts // "N/A"' "$status_file")
  printf "  %-10s %-20s branch: %-25s verify-attempts: %s\n" "$REQ" "[$STATUS]" "$BRANCH" "$ATTEMPTS"
done
