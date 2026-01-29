#!/usr/bin/env bash
# verify.sh — Verification orchestration via Claude Code with error handling
# Sourced by run-single-req.sh

# Requires errors.sh to be loaded

run_verification() {
  local worktree_path="$1"
  local model="$2"
  local timeout_secs="${3:-600}"  # Default 10 minutes

  local agent_dir="$worktree_path/$REQDRIVE_PATHS_AGENT_DIR"
  local prd_file="$agent_dir/prd.json"
  local app_dir="$worktree_path/$REQDRIVE_PATHS_APP_DIR"
  local report_file="$agent_dir/verification-report.txt"

  # ── Validate Prerequisites ──────────────────────────────────────────
  if [ ! -f "$prd_file" ]; then
    log_error "prd.json not found at $prd_file"
    return $ERR_VERIFY
  fi

  cd "$worktree_path"

  log_info "  Running verification..."

  # ── Build Verification Checks ───────────────────────────────────────
  local checks=""
  local check_count
  check_count=$(jq '.verification.checks // [] | length' "$REQDRIVE_MANIFEST")

  if [ "$check_count" -gt 0 ]; then
    checks="Run these verification checks:"$'\n'
    for i in $(seq 0 $((check_count - 1))); do
      local check_name check_cmd
      check_name=$(jq -r ".verification.checks[$i].name" "$REQDRIVE_MANIFEST")
      check_cmd=$(jq -r ".verification.checks[$i].command" "$REQDRIVE_MANIFEST")
      checks+="$((i + 1)). $check_name: \`$check_cmd\`"$'\n'
    done
  else
    # Fallback: build checks from commands config
    local n=1
    if [ -n "$REQDRIVE_CMD_TYPECHECK" ] && [ "$REQDRIVE_CMD_TYPECHECK" != "null" ]; then
      checks+="$n. TypeScript compilation: \`$REQDRIVE_CMD_TYPECHECK\`"$'\n'
      n=$((n + 1))
    fi
    if [ -n "$REQDRIVE_CMD_TEST" ] && [ "$REQDRIVE_CMD_TEST" != "null" ]; then
      checks+="$n. Tests: \`$REQDRIVE_CMD_TEST\`"$'\n'
      n=$((n + 1))
    fi
    if [ -n "$REQDRIVE_CMD_LINT" ] && [ "$REQDRIVE_CMD_LINT" != "null" ]; then
      checks+="$n. Lint: \`$REQDRIVE_CMD_LINT\`"$'\n'
      n=$((n + 1))
    fi
  fi

  if [ -z "$checks" ]; then
    log_warn "  No verification checks configured"
    checks="Run any available tests and verify the code works correctly."
  fi

  # ── Test Generation Option ──────────────────────────────────────────
  local generate_tests
  generate_tests=$(jq -r '.verification.generateTests // true' "$REQDRIVE_MANIFEST")
  local test_gen_prompt=""
  if [ "$generate_tests" = "true" ]; then
    test_gen_prompt="Generate new unit tests for code changed by the agent and run them."
  fi

  # ── Get Security Arguments ──────────────────────────────────────────
  local security_args
  security_args=$(reqdrive_claude_security_args verify)

  # ── Build Verification Prompt ───────────────────────────────────────
  local prompt
  prompt=$(cat <<PROMPT
Run verification against this project.

The PRD is at: $prd_file
The project root is: $app_dir

$checks

$test_gen_prompt

If verification fails, update the prd.json notes for the failing stories
with specific error context so the agent can fix them on retry.
Set "passes" back to false for any story whose code causes failures.

End your response with either:
  VERIFICATION_PASSED
or:
  VERIFICATION_FAILED

followed by a brief summary of results.
PROMPT
  )

  # ── Run Verification ────────────────────────────────────────────────
  log_debug "  Running Claude for verification (timeout: ${timeout_secs}s)"

  local output=""
  local claude_status=0

  # shellcheck disable=SC2086
  output=$(run_with_timeout "$timeout_secs" \
    claude $security_args --model "$model" -p "$prompt" 2>&1) || claude_status=$?

  # Save verification report regardless of outcome
  {
    echo "Verification Report"
    echo "==================="
    echo "Timestamp: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "Exit Status: $claude_status"
    echo ""
    echo "Output:"
    echo "-------"
    echo "$output"
  } > "$report_file"

  log_info "  Verification report saved to $report_file"

  # Handle timeout
  if [ "$claude_status" -eq 124 ] || [ "$claude_status" -eq 137 ]; then
    log_error "  Verification timed out after ${timeout_secs}s"
    return $ERR_CLAUDE_TIMEOUT
  fi

  # Handle other Claude errors
  if [ "$claude_status" -ne 0 ]; then
    log_warn "  Claude exited with status $claude_status (may still have valid results)"
  fi

  # ── Check Verification Result ───────────────────────────────────────
  if echo "$output" | grep -q "VERIFICATION_PASSED"; then
    log_info "  Result: PASSED"

    # Extract summary if present
    local summary
    summary=$(echo "$output" | sed -n '/VERIFICATION_PASSED/,$p' | tail -5)
    log_debug "  Summary: $summary"

    return 0
  elif echo "$output" | grep -q "VERIFICATION_FAILED"; then
    log_warn "  Result: FAILED"

    # Extract failure summary
    local failure_summary
    failure_summary=$(echo "$output" | sed -n '/VERIFICATION_FAILED/,$p' | tail -10)
    log_info "  Failure summary: $failure_summary"

    return $ERR_VERIFY
  else
    # No clear signal - try to infer from output
    log_warn "  No clear PASSED/FAILED signal in output"

    # Check for common failure indicators
    if echo "$output" | grep -qiE "(error|failed|failure|exception)"; then
      log_warn "  Found error indicators in output, treating as FAILED"
      return $ERR_VERIFY
    fi

    # Assume passed if no errors found
    log_info "  No errors found, treating as PASSED"
    return 0
  fi
}
