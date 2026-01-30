#!/usr/bin/env bash
# agent-tasks.sh — Simplified agent using Claude's built-in Tasks
# Single invocation - Claude manages its own task list internally

# Requires config.sh to be loaded for security args

run_agent_tasks() {
  local worktree_path="$1"
  local model="${2:-claude-sonnet-4-20250514}"
  local timeout_secs="${3:-1800}"  # Default 30 minutes for full run

  local agent_dir="$worktree_path/$REQDRIVE_PATHS_AGENT_DIR"
  local prompt_file="$agent_dir/prompt.md"
  local prd_file="$agent_dir/prd.json"
  local completion_signal="${REQDRIVE_AGENT_COMPLETION_SIGNAL:-<promise>COMPLETE</promise>}"

  # Validate prerequisites
  if [ ! -f "$prompt_file" ]; then
    echo "ERROR: Agent prompt not found at $prompt_file" >&2
    return 1
  fi

  if [ ! -f "$prd_file" ]; then
    echo "ERROR: prd.json not found at $prd_file" >&2
    return 1
  fi

  cd "$worktree_path" || return 1

  # Get security arguments
  local security_args
  security_args=$(reqdrive_claude_security_args agent)

  # Count initial stories
  local initial_remaining
  initial_remaining=$(jq '[.userStories[] | select(.passes == false)] | length' "$prd_file" 2>/dev/null || echo "?")

  echo "═══════════════════════════════════════════════════════"
  echo "  Agent (Tasks-Based) Starting"
  echo "═══════════════════════════════════════════════════════"
  echo "  Stories to complete: $initial_remaining"
  echo "  Timeout: ${timeout_secs}s"
  echo ""

  local start_time
  start_time=$(date +%s)

  # Single Claude invocation - it manages tasks internally
  # shellcheck disable=SC2086
  local output
  output=$(cat "$prompt_file" | timeout "$timeout_secs" \
    claude $security_args --model "$model" 2>&1 | tee /dev/stderr) || true

  # Save output
  echo "$output" > "$agent_dir/agent-run.log"

  local elapsed=$(($(date +%s) - start_time))
  echo ""
  echo "═══════════════════════════════════════════════════════"
  echo "  Agent completed in ${elapsed}s"
  echo "═══════════════════════════════════════════════════════"

  # Check results
  local final_remaining
  final_remaining=$(jq '[.userStories[] | select(.passes == false)] | length' "$prd_file" 2>/dev/null || echo "?")

  echo "  Stories remaining: $final_remaining"

  if echo "$output" | grep -qF "$completion_signal"; then
    echo "  Status: COMPLETE"
    return 0
  elif [ "$final_remaining" = "0" ]; then
    echo "  Status: All stories passing (no completion signal)"
    return 0
  else
    echo "  Status: Incomplete"
    return 1
  fi
}
