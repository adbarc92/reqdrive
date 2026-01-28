#!/usr/bin/env bash
# agent-run.sh — Agent execution loop (generalized from ralph-run.sh)
# Sourced by run-single-req.sh

run_agent() {
  local worktree_path="$1"
  local max_iterations="$2"
  local model="$3"

  local agent_dir="$worktree_path/$REQDRIVE_PATHS_AGENT_DIR"
  local prompt_file="$agent_dir/prompt.md"
  local completion_signal="$REQDRIVE_AGENT_COMPLETION_SIGNAL"

  if [ ! -f "$prompt_file" ]; then
    echo "  ERROR: Agent prompt not found at $prompt_file"
    return 1
  fi

  if [ ! -f "$agent_dir/prd.json" ]; then
    echo "  ERROR: prd.json not found at $agent_dir/prd.json"
    return 1
  fi

  cd "$worktree_path"

  for i in $(seq 1 "$max_iterations"); do
    echo ""
    echo "  ═══════════════════════════════════════════════════════"
    echo "    Agent iteration $i of $max_iterations"
    echo "  ═══════════════════════════════════════════════════════"

    # Check remaining stories before running
    local remaining
    remaining=$(jq '[.userStories[] | select(.passes == false)] | length' "$agent_dir/prd.json" 2>/dev/null || echo "?")
    echo "  Stories remaining: $remaining"

    # Run Claude Code with the agent prompt
    OUTPUT=$(cat "$prompt_file" | claude \
      --dangerously-skip-permissions \
      --model "$model" \
      -p 2>&1 | tee /dev/stderr) || true

    # Check for completion signal
    if echo "$OUTPUT" | grep -qF "$completion_signal"; then
      echo ""
      echo "  Agent completed all stories at iteration $i"
      return 0
    fi

    echo "  Iteration $i complete. Continuing..."
    sleep 2
  done

  echo "  Agent reached max iterations ($max_iterations)"

  # Check final state
  local final_remaining
  final_remaining=$(jq '[.userStories[] | select(.passes == false)] | length' "$agent_dir/prd.json" 2>/dev/null || echo "?")
  echo "  Stories still incomplete: $final_remaining"

  # Return success if all stories pass, even without completion signal
  if [ "$final_remaining" = "0" ]; then
    echo "  All stories marked as passing despite no completion signal"
    return 0
  fi

  return 1
}
