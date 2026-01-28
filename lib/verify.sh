#!/usr/bin/env bash
# verify.sh — Verification orchestration via Claude Code
# Sourced by run-single-req.sh

run_verification() {
  local worktree_path="$1"
  local model="$2"

  local agent_dir="$worktree_path/$REQDRIVE_PATHS_AGENT_DIR"
  local prd_file="$agent_dir/prd.json"
  local app_dir="$worktree_path/$REQDRIVE_PATHS_APP_DIR"

  if [ ! -f "$prd_file" ]; then
    echo "  ERROR: prd.json not found at $prd_file"
    return 1
  fi

  cd "$worktree_path"

  echo "  Running verification..."

  # Build verification checks from manifest
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

  # Check if test generation is enabled
  local generate_tests
  generate_tests=$(jq -r '.verification.generateTests // true' "$REQDRIVE_MANIFEST")
  local test_gen_prompt=""
  if [ "$generate_tests" = "true" ]; then
    test_gen_prompt="Generate new unit tests for code changed by the agent and run them."
  fi

  VERIFY_OUTPUT=$(claude --dangerously-skip-permissions --model "$model" -p "$(cat <<PROMPT
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
PROMPT
)" 2>&1

  # Save verification report
  echo "$VERIFY_OUTPUT" > "$agent_dir/verification-report.txt"
  echo "  Verification report saved to $agent_dir/verification-report.txt"

  # Check result
  if echo "$VERIFY_OUTPUT" | grep -q "VERIFICATION_PASSED"; then
    echo "  Result: PASSED"
    return 0
  else
    echo "  Result: FAILED"
    return 1
  fi
}
