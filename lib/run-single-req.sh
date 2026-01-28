#!/usr/bin/env bash
# run-single-req.sh — Full pipeline for one requirement:
#   worktree setup → PRD generation → agent → verification → PR
# Usage: run-single-req.sh <REQ-XX> <run-dir>

set -e

source "${REQDRIVE_ROOT}/lib/config.sh"
reqdrive_load_config

REQ="$1"
RUN_DIR="$2"

if [ -z "$REQ" ] || [ -z "$RUN_DIR" ]; then
  echo "Usage: $0 <REQ-XX> <run-dir>" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Derive paths from config
FEATURE_SLUG=$(echo "$REQ" | tr '[:upper:]' '[:lower:]')
WORKTREE_ROOT="$(reqdrive_resolve_path "$REQDRIVE_ORCH_WORKTREE_ROOT")"
WORKTREE_PATH="$WORKTREE_ROOT/$REQDRIVE_AGENT_WORKTREE_PREFIX-$FEATURE_SLUG"
BRANCH="$REQDRIVE_AGENT_BRANCH_PREFIX/$FEATURE_SLUG"
MAX_VERIFY_RETRIES="$REQDRIVE_VERIFY_MAX_RETRIES"
MAX_AGENT_ITERS="$REQDRIVE_AGENT_MAX_ITERATIONS"
MODEL="$REQDRIVE_AGENT_MODEL"
BASE_BRANCH="$REQDRIVE_ORCH_BASE_BRANCH"

# Find the requirements file
REQ_FILE=$(reqdrive_get_req_file "$REQ") || {
  echo "[$REQ] ERROR: No requirements file found matching ${REQ}*.md"
  echo "{\"req\": \"$REQ\", \"status\": \"error\", \"error\": \"requirements file not found\"}" \
    > "$RUN_DIR/$REQ-status.json"
  exit 1
}

echo "[$REQ] Starting pipeline"
echo "[$REQ] Requirements: $REQ_FILE"
echo "[$REQ] Branch: $BRANCH"
echo "[$REQ] Worktree: $WORKTREE_PATH"

# Record initial state
echo "{\"req\": \"$REQ\", \"branch\": \"$BRANCH\", \"status\": \"started\", \"startTime\": \"$(reqdrive_timestamp)\"}" \
  > "$RUN_DIR/$REQ-status.json"

# --- STAGE 1: Worktree Setup ---
echo ""
echo "[$REQ] ══════ Stage 1: Setting up worktree ══════"
source "$SCRIPT_DIR/worktree.sh"
setup_worktree "$REQDRIVE_PROJECT_ROOT" "$WORKTREE_PATH" "$BRANCH" "$BASE_BRANCH"

# Install dependencies in worktree
if [ -n "$REQDRIVE_CMD_INSTALL" ] && [ "$REQDRIVE_CMD_INSTALL" != "null" ]; then
  echo "[$REQ] Installing dependencies..."
  local_app_dir="$WORKTREE_PATH/$REQDRIVE_PATHS_APP_DIR"
  cd "$local_app_dir" && eval "$REQDRIVE_CMD_INSTALL" 2>&1 | tail -5
  cd "$REQDRIVE_PROJECT_ROOT"
fi

# --- STAGE 2: PRD Generation ---
echo ""
echo "[$REQ] ══════ Stage 2: Generating PRD ══════"
source "$SCRIPT_DIR/prd-gen.sh"
if ! generate_prd "$REQ_FILE" "$WORKTREE_PATH" "$MODEL"; then
  echo "[$REQ] PRD generation failed. Aborting."
  echo "{\"req\": \"$REQ\", \"branch\": \"$BRANCH\", \"status\": \"failed\", \"stage\": \"prd-gen\", \"endTime\": \"$(reqdrive_timestamp)\"}" \
    > "$RUN_DIR/$REQ-status.json"
  teardown_worktree "$REQDRIVE_PROJECT_ROOT" "$WORKTREE_PATH"
  exit 1
fi

# --- STAGE 3+4: Agent + Verification Loop ---
DRAFT_FLAG=""
VERIFY_ATTEMPT=0

while [ "$VERIFY_ATTEMPT" -lt "$MAX_VERIFY_RETRIES" ]; do
  VERIFY_ATTEMPT=$((VERIFY_ATTEMPT + 1))

  echo ""
  echo "[$REQ] ══════ Stage 3: Running agent (verification attempt $VERIFY_ATTEMPT/$MAX_VERIFY_RETRIES) ══════"

  # Update state
  echo "{\"req\": \"$REQ\", \"branch\": \"$BRANCH\", \"status\": \"agent-running\", \"verifyAttempt\": $VERIFY_ATTEMPT}" \
    > "$RUN_DIR/$REQ-status.json"

  # Run agent
  source "$SCRIPT_DIR/agent-run.sh"
  run_agent "$WORKTREE_PATH" "$MAX_AGENT_ITERS" "$MODEL" || true

  # Verify
  echo ""
  echo "[$REQ] ══════ Stage 4: Running verification (attempt $VERIFY_ATTEMPT/$MAX_VERIFY_RETRIES) ══════"

  echo "{\"req\": \"$REQ\", \"branch\": \"$BRANCH\", \"status\": \"verifying\", \"verifyAttempt\": $VERIFY_ATTEMPT}" \
    > "$RUN_DIR/$REQ-status.json"

  source "$SCRIPT_DIR/verify.sh"
  if run_verification "$WORKTREE_PATH" "$MODEL"; then
    echo "[$REQ] Verification PASSED"
    break
  else
    echo "[$REQ] Verification FAILED (attempt $VERIFY_ATTEMPT/$MAX_VERIFY_RETRIES)"
    if [ "$VERIFY_ATTEMPT" -ge "$MAX_VERIFY_RETRIES" ]; then
      echo "[$REQ] Max retries reached. Creating draft PR for human review."
      DRAFT_FLAG="--draft"
    fi
  fi
done

# --- STAGE 5: PR Creation ---
echo ""
echo "[$REQ] ══════ Stage 5: Creating PR ══════"

echo "{\"req\": \"$REQ\", \"branch\": \"$BRANCH\", \"status\": \"creating-pr\", \"verifyAttempts\": $VERIFY_ATTEMPT}" \
  > "$RUN_DIR/$REQ-status.json"

source "$SCRIPT_DIR/pr-create.sh"
if create_pr "$WORKTREE_PATH" "$REQ" "$BRANCH" "$BASE_BRANCH" "$DRAFT_FLAG"; then
  FINAL_STATUS="pr-created"
else
  echo "[$REQ] Warning: PR creation failed. Branch is still available at $BRANCH"
  FINAL_STATUS="pr-failed"
fi

# Record final state
DRAFT_BOOL="false"
[ -n "$DRAFT_FLAG" ] && DRAFT_BOOL="true"
echo "{\"req\": \"$REQ\", \"branch\": \"$BRANCH\", \"status\": \"$FINAL_STATUS\", \"verifyAttempts\": $VERIFY_ATTEMPT, \"draft\": $DRAFT_BOOL, \"endTime\": \"$(reqdrive_timestamp)\"}" \
  > "$RUN_DIR/$REQ-status.json"

echo ""
echo "[$REQ] Pipeline complete. Status: $FINAL_STATUS"
