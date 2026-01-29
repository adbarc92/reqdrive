#!/usr/bin/env bash
# agent-run.sh — Agent execution loop with timeout and error handling
# Sourced by run-single-req.sh

# Requires errors.sh to be loaded

run_agent() {
  local worktree_path="$1"
  local max_iterations="$2"
  local model="$3"
  local timeout_secs="${4:-600}"  # Default 10 minutes per iteration

  local agent_dir="$worktree_path/$REQDRIVE_PATHS_AGENT_DIR"
  local prompt_file="$agent_dir/prompt.md"
  local prd_file="$agent_dir/prd.json"
  local completion_signal="$REQDRIVE_AGENT_COMPLETION_SIGNAL"

  # ── Validate Prerequisites ──────────────────────────────────────────
  if [ ! -f "$prompt_file" ]; then
    log_error "Agent prompt not found at $prompt_file"
    return $ERR_AGENT
  fi

  if [ ! -f "$prd_file" ]; then
    log_error "prd.json not found at $prd_file"
    return $ERR_AGENT
  fi

  cd "$worktree_path"

  # Get security arguments for agent stage
  local security_args
  security_args=$(reqdrive_claude_security_args agent)

  local agent_start_time
  agent_start_time=$(date +%s)

  # ── Agent Iteration Loop ────────────────────────────────────────────
  for i in $(seq 1 "$max_iterations"); do
    log_info ""
    log_info "  ═══════════════════════════════════════════════════════"
    log_info "    Agent iteration $i of $max_iterations"
    log_info "  ═══════════════════════════════════════════════════════"

    # Check remaining stories before running
    local remaining
    remaining=$(jq '[.userStories[] | select(.passes == false)] | length' "$prd_file" 2>/dev/null || echo "?")
    log_info "  Stories remaining: $remaining"

    # Skip if all stories are already done
    if [ "$remaining" = "0" ]; then
      log_info "  All stories already complete"
      return 0
    fi

    # Save iteration state
    echo "{\"iteration\": $i, \"remaining\": $remaining, \"timestamp\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"}" \
      > "$agent_dir/iteration-state.json"

    # Read the prompt
    local prompt_content
    prompt_content=$(cat "$prompt_file")

    # Run Claude with timeout
    log_debug "  Running Claude (timeout: ${timeout_secs}s)"

    local output=""
    local claude_status=0

    # Use run_with_timeout from errors.sh
    # shellcheck disable=SC2086
    output=$(run_with_timeout "$timeout_secs" \
      claude $security_args --model "$model" -p "$prompt_content" 2>&1) || claude_status=$?

    # Handle timeout
    if [ "$claude_status" -eq 124 ] || [ "$claude_status" -eq 137 ]; then
      log_error "  Agent iteration $i timed out after ${timeout_secs}s"

      # Save timeout state for debugging
      echo "$output" > "$agent_dir/iteration-$i-timeout.log"

      # Continue to next iteration or exit based on policy
      if [ "$i" -eq "$max_iterations" ]; then
        return $ERR_AGENT_TIMEOUT
      fi
      continue
    fi

    # Handle other Claude errors
    if [ "$claude_status" -ne 0 ]; then
      log_warn "  Claude exited with status $claude_status"
      echo "$output" > "$agent_dir/iteration-$i-error.log"

      # Don't fail immediately - agent may have made partial progress
    fi

    # Log output for debugging (truncated)
    local output_preview
    output_preview=$(echo "$output" | tail -20)
    log_debug "  Output preview: $output_preview"

    # Save full output
    echo "$output" > "$agent_dir/iteration-$i.log"

    # Check for completion signal
    if echo "$output" | grep -qF "$completion_signal"; then
      log_info ""
      log_info "  Agent completed all stories at iteration $i"

      local elapsed=$(($(date +%s) - agent_start_time))
      log_info "  Total agent time: ${elapsed}s"

      return 0
    fi

    # Verify stories are being completed
    local new_remaining
    new_remaining=$(jq '[.userStories[] | select(.passes == false)] | length' "$prd_file" 2>/dev/null || echo "?")

    if [ "$new_remaining" != "?" ] && [ "$remaining" != "?" ]; then
      local completed=$((remaining - new_remaining))
      if [ "$completed" -gt 0 ]; then
        log_info "  Completed $completed stories this iteration"
      elif [ "$completed" -eq 0 ]; then
        log_warn "  No stories completed this iteration"
      fi
    fi

    log_info "  Iteration $i complete. Continuing..."
    sleep 2
  done

  log_warn "  Agent reached max iterations ($max_iterations)"

  # Check final state
  local final_remaining
  final_remaining=$(jq '[.userStories[] | select(.passes == false)] | length' "$prd_file" 2>/dev/null || echo "?")
  log_info "  Stories still incomplete: $final_remaining"

  local elapsed=$(($(date +%s) - agent_start_time))
  log_info "  Total agent time: ${elapsed}s"

  # Return success if all stories pass, even without completion signal
  if [ "$final_remaining" = "0" ]; then
    log_info "  All stories marked as passing despite no completion signal"
    return 0
  fi

  return $ERR_AGENT
}
