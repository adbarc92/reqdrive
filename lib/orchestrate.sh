#!/usr/bin/env bash
# orchestrate.sh — Pipeline orchestrator
# Runs the full requirements-to-PR pipeline for one or more REQs.
# Dispatched from bin/reqdrive as: reqdrive run [args]

set -e

source "${REQDRIVE_ROOT}/lib/config.sh"
reqdrive_load_config

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

MAX_PARALLEL="$REQDRIVE_ORCH_MAX_PARALLEL"
BASE_BRANCH="$REQDRIVE_ORCH_BASE_BRANCH"
STATE_DIR="$(reqdrive_resolve_path "$REQDRIVE_ORCH_STATE_DIR")"
REQ_DIR="$(reqdrive_resolve_path "$REQDRIVE_PATHS_REQUIREMENTS_DIR")"

# ── Generate run ID and directory ─────────────────────────────────────

RUN_ID="$(reqdrive_run_id)"
RUN_DIR="$STATE_DIR/runs/$RUN_ID"
mkdir -p "$RUN_DIR/logs"

echo "═══════════════════════════════════════════════════════════"
echo "  reqdrive pipeline"
echo "  Project: $REQDRIVE_PROJECT_TITLE"
echo "  Run ID: $RUN_ID"
echo "  Max parallel worktrees: $MAX_PARALLEL"
echo "═══════════════════════════════════════════════════════════"
echo ""

# ── Determine which REQs to process ──────────────────────────────────

REQS=""

if [ "${1:-}" = "--all" ]; then
  echo "Mode: All REQs (respecting dependency order)"
  for f in "$REQ_DIR"/REQ-*.md; do
    [ -f "$f" ] || continue
    BASENAME=$(basename "$f" .md)
    REQ_ID=$(echo "$BASENAME" | grep -oE 'REQ-[0-9]+')
    REQS+="$REQ_ID "
  done
elif [ "${1:-}" = "--next" ]; then
  echo "Mode: Auto-detect next available REQs"
  REQS=$(bash "$SCRIPT_DIR/find-next-reqs.sh") || {
    echo "No REQs available to process."
    exit 0
  }
else
  REQS="$*"
fi

if [ -z "$REQS" ]; then
  echo "No REQs specified. Usage:"
  echo "  reqdrive run REQ-01 REQ-03    # Run specific REQs"
  echo "  reqdrive run --all            # Run all REQs"
  echo "  reqdrive run --next           # Auto-detect next available"
  exit 1
fi

echo "Processing: $REQS"
echo ""

# ── Run pipeline for each REQ ─────────────────────────────────────────

declare -a ACTIVE_PIDS
declare -a ACTIVE_REQS

cleanup() {
  echo ""
  echo "Interrupted. Stopping active pipelines..."
  for pid in "${ACTIVE_PIDS[@]}"; do
    kill "$pid" 2>/dev/null || true
  done
  wait 2>/dev/null || true
  echo "Cleanup complete."
  exit 1
}
trap cleanup INT TERM

# Portable wait-for-any: uses wait -n if available, else poll
wait_for_any() {
  if (wait -n 2>/dev/null; true) 2>/dev/null; then
    # bash 4.3+ supports wait -n
    wait -n "${ACTIVE_PIDS[@]}" 2>/dev/null || true
  else
    # Fallback: poll every second
    while true; do
      for i in "${!ACTIVE_PIDS[@]}"; do
        if ! kill -0 "${ACTIVE_PIDS[$i]}" 2>/dev/null; then
          return 0
        fi
      done
      sleep 1
    done
  fi
}

REQ_ID_REGEX="$REQDRIVE_REQ_ID_REGEX"

for REQ in $REQS; do
  # Validate REQ format
  if ! echo "$REQ" | grep -qE "^${REQ_ID_REGEX}$"; then
    echo "SKIP $REQ: Invalid format (expected pattern: $REQ_ID_REGEX)"
    continue
  fi

  # Wait if at max parallel
  while [ ${#ACTIVE_PIDS[@]} -ge "$MAX_PARALLEL" ]; do
    wait_for_any
    # Clean up finished PIDs
    NEW_PIDS=()
    NEW_REQS=()
    for i in "${!ACTIVE_PIDS[@]}"; do
      if kill -0 "${ACTIVE_PIDS[$i]}" 2>/dev/null; then
        NEW_PIDS+=("${ACTIVE_PIDS[$i]}")
        NEW_REQS+=("${ACTIVE_REQS[$i]}")
      else
        echo "  Finished: ${ACTIVE_REQS[$i]} (PID ${ACTIVE_PIDS[$i]})"
      fi
    done
    ACTIVE_PIDS=("${NEW_PIDS[@]}")
    ACTIVE_REQS=("${NEW_REQS[@]}")
  done

  # Check dependencies
  if ! bash "$SCRIPT_DIR/check-deps.sh" "$REQ"; then
    echo "SKIP $REQ: dependencies not met"
    echo "{\"req\": \"$REQ\", \"status\": \"skipped\", \"reason\": \"dependencies not met\"}" \
      > "$RUN_DIR/$REQ-status.json"
    continue
  fi

  # Launch pipeline for this REQ in background
  echo "LAUNCH $REQ (log: $RUN_DIR/logs/$REQ.log)"
  bash "$SCRIPT_DIR/run-single-req.sh" "$REQ" "$RUN_DIR" \
    > "$RUN_DIR/logs/$REQ.log" 2>&1 &

  ACTIVE_PIDS+=($!)
  ACTIVE_REQS+=("$REQ")

  # Small delay to avoid git lock contention on worktree creation
  sleep 2
done

# Wait for all remaining
echo ""
echo "Waiting for all pipelines to complete..."
wait

echo ""
echo "═══════════════════════════════════════════════════════════"
echo "  Pipeline run $RUN_ID complete."
echo "═══════════════════════════════════════════════════════════"
echo ""
echo "Results:"
for status_file in "$RUN_DIR"/*-status.json; do
  [ -f "$status_file" ] || continue
  REQ_NAME=$(jq -r '.req' "$status_file")
  STATUS=$(jq -r '.status' "$status_file")
  printf "  %-10s %s\n" "$REQ_NAME" "$STATUS"
done
echo ""
echo "Logs: $RUN_DIR/logs/"
echo "Status: reqdrive status $RUN_ID"
