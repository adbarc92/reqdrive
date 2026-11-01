#!/usr/bin/env bash
# run-single-req.sh — Full pipeline for one requirement:
#   worktree setup → PRD generation → agent → verification → PR
# Usage: run-single-req.sh <REQ-XX> <run-dir> [--resume]

set -e

source "${REQDRIVE_ROOT}/lib/config.sh"
source "${REQDRIVE_ROOT}/lib/errors.sh"

reqdrive_load_config

REQ="$1"
RUN_DIR="$2"
RESUME_FLAG="${3:-}"

if [ -z "$REQ" ] || [ -z "$RUN_DIR" ]; then
  echo "Usage: $0 <REQ-XX> <run-dir> [--resume]" >&2
  exit $ERR_CONFIG
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── Configuration ─────────────────────────────────────────────────────
FEATURE_SLUG=$(echo "$REQ" | tr '[:upper:]' '[:lower:]')
WORKTREE_ROOT="$(reqdrive_resolve_path "$REQDRIVE_ORCH_WORKTREE_ROOT")"
WORKTREE_PATH="$WORKTREE_ROOT/$REQDRIVE_AGENT_WORKTREE_PREFIX-$FEATURE_SLUG"
BRANCH="$REQDRIVE_AGENT_BRANCH_PREFIX/$FEATURE_SLUG"
MAX_VERIFY_RETRIES="$REQDRIVE_VERIFY_MAX_RETRIES"
MAX_AGENT_ITERS="$REQDRIVE_AGENT_MAX_ITERATIONS"
MODEL="$REQDRIVE_AGENT_MODEL"
BASE_BRANCH="$REQDRIVE_ORCH_BASE_BRANCH"
STATUS_FILE="$RUN_DIR/$REQ-status.json"

# Timeouts (configurable via env or manifest)
CLAUDE_TIMEOUT="${REQDRIVE_CLAUDE_TIMEOUT:-600}"  # 10 minutes default
INSTALL_TIMEOUT="${REQDRIVE_INSTALL_TIMEOUT:-300}"  # 5 minutes default

# ── Cleanup Handler ───────────────────────────────────────────────────
cleanup_on_failure() {
  local exit_code=$?
  if [ "$exit_code" -ne 0 ]; then
    log_warn "[$REQ] Pipeline failed with exit code $exit_code"

    # Save failure state
    update_status "$STATUS_FILE" "$REQ" "failed" \
      "stage=$CURRENT_STAGE" \
      "exitCode=$exit_code" \
      "error=$(error_name $exit_code)" \
      "endTime=$(reqdrive_timestamp)"

    # Don't remove worktree on failure - preserve for debugging
    log_info "[$REQ] Worktree preserved at $WORKTREE_PATH for debugging"
  fi
}

setup_cleanup_trap
push_cleanup "cleanup_on_failure"

# ── Find Requirements File ────────────────────────────────────────────
REQ_FILE=$(reqdrive_get_req_file "$REQ") || {
  log_error "[$REQ] No requirements file found matching ${REQ}*.md"
  update_status "$STATUS_FILE" "$REQ" "error" \
    "error=requirements_file_not_found"
  exit $ERR_CONFIG
}

# ── Resume Logic ──────────────────────────────────────────────────────
START_STAGE="worktree"
if [ "$RESUME_FLAG" = "--resume" ]; then
  LAST_STAGE=$(get_last_stage "$RUN_DIR" "$REQ")
  case "$LAST_STAGE" in
    worktree)  START_STAGE="prd" ;;
    prd)       START_STAGE="agent" ;;
    agent)     START_STAGE="verify" ;;
    verify)    START_STAGE="pr" ;;
    *)         START_STAGE="worktree" ;;
  esac
  log_info "[$REQ] Resuming from stage: $START_STAGE (last completed: $LAST_STAGE)"
fi

# ── Pipeline Start ────────────────────────────────────────────────────
log_info "[$REQ] Starting pipeline"
log_info "[$REQ] Requirements: $REQ_FILE"
log_info "[$REQ] Branch: $BRANCH"
log_info "[$REQ] Worktree: $WORKTREE_PATH"

update_status "$STATUS_FILE" "$REQ" "started" \
  "branch=$BRANCH" \
  "startTime=$(reqdrive_timestamp)"

CURRENT_STAGE="init"

# ══════════════════════════════════════════════════════════════════════
# STAGE 1: Worktree Setup
# ══════════════════════════════════════════════════════════════════════
if [ "$START_STAGE" = "worktree" ]; then
  CURRENT_STAGE="worktree"
  log_info ""
  log_info "[$REQ] ══════ Stage 1: Setting up worktree ══════"

  source "$SCRIPT_DIR/worktree.sh"

  if ! setup_worktree "$REQDRIVE_PROJECT_ROOT" "$WORKTREE_PATH" "$BRANCH" "$BASE_BRANCH"; then
    log_error "[$REQ] Worktree setup failed"
    exit $ERR_WORKTREE
  fi

  # Install dependencies in worktree
  if [ -n "$REQDRIVE_CMD_INSTALL" ] && [ "$REQDRIVE_CMD_INSTALL" != "null" ]; then
    log_info "[$REQ] Installing dependencies..."
    local_app_dir="$WORKTREE_PATH/$REQDRIVE_PATHS_APP_DIR"

    cd "$local_app_dir"
    if ! run_with_timeout "$INSTALL_TIMEOUT" bash -c "$REQDRIVE_CMD_INSTALL" 2>&1; then
      log_error "[$REQ] Dependency installation failed or timed out"
      cd "$REQDRIVE_PROJECT_ROOT"
      exit $ERR_PREREQ
    fi
    cd "$REQDRIVE_PROJECT_ROOT"
  fi

  save_checkpoint "$RUN_DIR" "$REQ" "worktree" "completed"
  START_STAGE="prd"
fi

# ══════════════════════════════════════════════════════════════════════
# STAGE 2: PRD Generation
# ══════════════════════════════════════════════════════════════════════
if [ "$START_STAGE" = "prd" ]; then
  CURRENT_STAGE="prd"
  log_info ""
  log_info "[$REQ] ══════ Stage 2: Generating PRD ══════"

  update_status "$STATUS_FILE" "$REQ" "generating-prd" \
    "branch=$BRANCH"

  source "$SCRIPT_DIR/prd-gen.sh"

  # Retry PRD generation up to 3 times
  PRD_GENERATED=false
  for prd_attempt in 1 2 3; do
    log_info "[$REQ] PRD generation attempt $prd_attempt/3"

    if generate_prd "$REQ_FILE" "$WORKTREE_PATH" "$MODEL" "$CLAUDE_TIMEOUT"; then
      # Validate the generated PRD
      local prd_file="$WORKTREE_PATH/$REQDRIVE_PATHS_AGENT_DIR/prd.json"
      if validate_prd_json "$prd_file"; then
        PRD_GENERATED=true
        break
      else
        log_warn "[$REQ] PRD validation failed, retrying..."
      fi
    else
      log_warn "[$REQ] PRD generation failed, retrying..."
    fi

    [ "$prd_attempt" -lt 3 ] && sleep 5
  done

  if [ "$PRD_GENERATED" = false ]; then
    log_error "[$REQ] PRD generation failed after 3 attempts"
    exit $ERR_PRD
  fi

  save_checkpoint "$RUN_DIR" "$REQ" "prd" "completed"
  START_STAGE="agent"
fi

# ══════════════════════════════════════════════════════════════════════
# STAGE 3+4: Agent + Verification Loop
# ══════════════════════════════════════════════════════════════════════
DRAFT_FLAG=""
VERIFY_ATTEMPT=0
AGENT_SUCCEEDED=false

while [ "$VERIFY_ATTEMPT" -lt "$MAX_VERIFY_RETRIES" ]; do
  VERIFY_ATTEMPT=$((VERIFY_ATTEMPT + 1))

  # ── Stage 3: Agent Execution ──
  if [ "$START_STAGE" = "agent" ] || [ "$START_STAGE" = "verify" ]; then
    # Only run agent if not resuming from verify stage
    if [ "$START_STAGE" != "verify" ]; then
      CURRENT_STAGE="agent"
      log_info ""
      log_info "[$REQ] ══════ Stage 3: Running agent (attempt $VERIFY_ATTEMPT/$MAX_VERIFY_RETRIES) ══════"

      update_status "$STATUS_FILE" "$REQ" "agent-running" \
        "branch=$BRANCH" \
        "verifyAttempt=$VERIFY_ATTEMPT"

      source "$SCRIPT_DIR/agent-run.sh"

      AGENT_EXIT=0
      if ! run_agent "$WORKTREE_PATH" "$MAX_AGENT_ITERS" "$MODEL" "$CLAUDE_TIMEOUT"; then
        AGENT_EXIT=$?
        log_warn "[$REQ] Agent did not complete successfully (exit: $AGENT_EXIT)"

        # Check if it was a timeout vs other failure
        if [ "$AGENT_EXIT" -eq "$ERR_AGENT_TIMEOUT" ]; then
          log_error "[$REQ] Agent timed out"
          # Continue to verification anyway - partial work may be valid
        fi
      fi

      save_checkpoint "$RUN_DIR" "$REQ" "agent" "completed" \
        "{\"verifyAttempt\": $VERIFY_ATTEMPT, \"agentExit\": $AGENT_EXIT}"
    fi

    START_STAGE="agent"  # Reset for next iteration
  fi

  # ── Stage 4: Verification ──
  CURRENT_STAGE="verify"
  log_info ""
  log_info "[$REQ] ══════ Stage 4: Running verification (attempt $VERIFY_ATTEMPT/$MAX_VERIFY_RETRIES) ══════"

  update_status "$STATUS_FILE" "$REQ" "verifying" \
    "branch=$BRANCH" \
    "verifyAttempt=$VERIFY_ATTEMPT"

  source "$SCRIPT_DIR/verify.sh"

  if run_verification "$WORKTREE_PATH" "$MODEL" "$CLAUDE_TIMEOUT"; then
    log_info "[$REQ] Verification PASSED"
    AGENT_SUCCEEDED=true
    save_checkpoint "$RUN_DIR" "$REQ" "verify" "passed"
    break
  else
    log_warn "[$REQ] Verification FAILED (attempt $VERIFY_ATTEMPT/$MAX_VERIFY_RETRIES)"
    save_checkpoint "$RUN_DIR" "$REQ" "verify" "failed" \
      "{\"verifyAttempt\": $VERIFY_ATTEMPT}"

    if [ "$VERIFY_ATTEMPT" -ge "$MAX_VERIFY_RETRIES" ]; then
      log_warn "[$REQ] Max retries reached. Creating draft PR for human review."
      DRAFT_FLAG="--draft"
    fi
  fi
done

# ══════════════════════════════════════════════════════════════════════
# STAGE 5: PR Creation
# ══════════════════════════════════════════════════════════════════════
CURRENT_STAGE="pr"
log_info ""
log_info "[$REQ] ══════ Stage 5: Creating PR ══════"

update_status "$STATUS_FILE" "$REQ" "creating-pr" \
  "branch=$BRANCH" \
  "verifyAttempts=$VERIFY_ATTEMPT"

source "$SCRIPT_DIR/pr-create.sh"

if create_pr "$WORKTREE_PATH" "$REQ" "$BRANCH" "$BASE_BRANCH" "$DRAFT_FLAG"; then
  FINAL_STATUS="pr-created"
  log_info "[$REQ] PR created successfully"
else
  log_warn "[$REQ] PR creation failed. Branch is still available at $BRANCH"
  FINAL_STATUS="pr-failed"
fi

# ── Record Final State ────────────────────────────────────────────────
DRAFT_BOOL="false"
[ -n "$DRAFT_FLAG" ] && DRAFT_BOOL="true"

update_status "$STATUS_FILE" "$REQ" "$FINAL_STATUS" \
  "branch=$BRANCH" \
  "verifyAttempts=$VERIFY_ATTEMPT" \
  "draft=$DRAFT_BOOL" \
  "agentSucceeded=$AGENT_SUCCEEDED" \
  "endTime=$(reqdrive_timestamp)"

save_checkpoint "$RUN_DIR" "$REQ" "pr" "completed"

log_info ""
log_info "[$REQ] Pipeline complete. Status: $FINAL_STATUS"

# Clear the failure cleanup since we succeeded
_CLEANUP_STACK=()
