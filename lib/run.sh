#!/usr/bin/env bash
# run.sh - Core pipeline: requirement -> planning -> implementation -> PR
# Usage: source this file, then call run_pipeline <REQ-ID>

set -e

# Source dependencies
source "$REQDRIVE_ROOT/lib/errors.sh"
source "$REQDRIVE_ROOT/lib/sanitize.sh"
source "$REQDRIVE_ROOT/lib/preflight.sh"

# ── Logging ──────────────────────────────────────────────────────────────────

log_info() { echo "[INFO]  $(date +%H:%M:%S) $*" >&2; }
log_warn() { echo "[WARN]  $(date +%H:%M:%S) $*" >&2; }
log_error() { echo "[ERROR] $(date +%H:%M:%S) $*" >&2; }

# ── Checkpoint Management ────────────────────────────────────────────────────

save_checkpoint() {
  local agent_dir="$1"
  local req_id="$2"
  local branch="$3"
  local iteration="$4"
  local prd_file="$5"

  local checkpoint_file="$agent_dir/checkpoint.json"
  local prd_exists="false"
  local stories_complete="[]"

  if [ -f "$prd_file" ]; then
    prd_exists="true"
    stories_complete=$(jq '[.userStories[] | select(.passes == true) | .id]' "$prd_file" 2>/dev/null || echo "[]")
  fi

  cat > "$checkpoint_file" <<EOF
{
  "version": "0.3.0",
  "req_id": "$req_id",
  "branch": "$branch",
  "iteration": $iteration,
  "timestamp": "$(date -Iseconds)",
  "prd_exists": $prd_exists,
  "stories_complete": $stories_complete
}
EOF

  log_info "Checkpoint saved: iteration $iteration"
}

load_checkpoint() {
  local agent_dir="$1"
  local req_id="$2"

  local checkpoint_file="$agent_dir/checkpoint.json"

  if [ ! -f "$checkpoint_file" ]; then
    echo ""
    return 0
  fi

  # Validate checkpoint schema
  if ! validate_checkpoint_schema "$checkpoint_file" 2>/dev/null; then
    log_warn "Checkpoint file has invalid schema, ignoring"
    echo ""
    return 0
  fi

  # Verify checkpoint is for the right requirement
  local checkpoint_req
  checkpoint_req=$(jq -r '.req_id' "$checkpoint_file" 2>/dev/null || echo "")

  if [ "$checkpoint_req" != "$req_id" ]; then
    log_warn "Checkpoint is for different requirement ($checkpoint_req), ignoring"
    echo ""
    return 0
  fi

  echo "$checkpoint_file"
}

# ── Iteration Summary Extraction ──────────────────────────────────────────────

# Extract the iteration summary JSON block from agent output
# Args: $1 = output text, $2 = agent_dir, $3 = iteration number
# Saves to iteration-N.summary.json if found
extract_iteration_summary() {
  local output="$1"
  local agent_dir="$2"
  local iteration="$3"

  local summary_file="$agent_dir/iteration-$iteration.summary.json"

  # Extract the json:iteration-summary fenced block
  local summary
  summary=$(echo "$output" | sed -n '/^```json:iteration-summary/,/^```/{/^```/d;p}')

  if [ -z "$summary" ]; then
    log_warn "No iteration summary found in agent output (iteration $iteration)"
    return 0
  fi

  # Validate it's valid JSON
  if ! echo "$summary" | jq empty 2>/dev/null; then
    log_warn "Iteration summary is not valid JSON (iteration $iteration)"
    return 0
  fi

  echo "$summary" > "$summary_file"

  # Log a one-line summary
  local story_id action notes
  story_id=$(echo "$summary" | jq -r '.storyId // "unknown"')
  action=$(echo "$summary" | jq -r '.action // "unknown"')
  notes=$(echo "$summary" | jq -r '.notes // ""')
  log_info "Summary: Story: $story_id | Action: $action | $notes"

  return 0
}

# ── Prompt Builders ──────────────────────────────────────────────────────────

# Build a planning-only prompt
# Args: $1 = prompt_file, $2 = sanitized requirement content
build_planning_prompt() {
  local prompt_file="$1"
  local sanitized_content="$2"

  cat > "$prompt_file" <<'PROMPT_PLAN'
# Agent Instructions: Planning Phase

You are an autonomous coding agent. Your ONLY job in this phase is to create a PRD.

## Task

Read the requirement below and create a PRD with user stories at `.reqdrive/agent/prd.json`.

**Do NOT implement anything.** Only create the PRD file.

## PRD Schema

```json
{
  "version": "0.3.0",
  "project": "<Project> - <Feature>",
  "sourceReq": "<REQ-XX>",
  "description": "Brief description of the feature",
  "userStories": [
    {
      "id": "US-001",
      "title": "...",
      "description": "...",
      "acceptanceCriteria": ["..."],
      "priority": 1,
      "passes": false
    }
  ]
}
```

## Rules

- Target 3-8 user stories (combine related items if needed)
- Each story must be completable in a single implementation session
- Priority 1 = implement first, higher numbers = implement later
- All stories start with `passes: false`
- Include clear, testable acceptance criteria for each story
- The `version` field must be `"0.3.0"`

## Iteration Summary

At the END of your response, output a summary:

```json:iteration-summary
{
  "storyId": "N/A",
  "action": "planned",
  "filesChanged": [".reqdrive/agent/prd.json"],
  "testsRun": false,
  "testsPassed": false,
  "committed": false,
  "notes": "Created PRD with N user stories"
}
```

---

## Requirement Document

PROMPT_PLAN

  echo "$sanitized_content" >> "$prompt_file"
}

# Build a story-specific implementation prompt
# Args: $1 = prompt_file, $2 = story_id, $3 = story_json, $4 = sanitized requirement content
build_implementation_prompt() {
  local prompt_file="$1"
  local story_id="$2"
  local story_json="$3"
  local sanitized_content="$4"

  local story_title story_description story_criteria
  story_title=$(echo "$story_json" | jq -r '.title')
  story_description=$(echo "$story_json" | jq -r '.description')
  story_criteria=$(echo "$story_json" | jq -r '.acceptanceCriteria | map("- " + .) | join("\n")')

  cat > "$prompt_file" <<PROMPT_IMPL
# Agent Instructions: Implement Story ${story_id}

You are an autonomous coding agent. Implement the following user story.

## Your Story

- **ID:** ${story_id}
- **Title:** ${story_title}
- **Description:** ${story_description}

### Acceptance Criteria

${story_criteria}

## Instructions

1. Read \`.reqdrive/agent/progress.txt\` for context from previous iterations
2. Read \`.reqdrive/agent/prd.json\` for full PRD context
3. Implement **this story only** (${story_id})
4. Run quality checks (test, typecheck, lint as appropriate)
5. If checks pass:
   - Commit with message: \`feat: [${story_id}] - ${story_title}\`
   - Update PRD: set \`passes: true\` for story ${story_id}
   - Append progress to \`progress.txt\`

## Progress Format

Append to progress.txt:
\`\`\`
## [Date] - ${story_id}
- What was implemented
- Files changed
- Learnings for future iterations
---
\`\`\`

## Important

- Implement ONLY story ${story_id}
- Commit after completing the story
- Keep tests passing
- If you discover a dependency issue, update priorities in prd.json and leave this story as \`passes: false\`

## Iteration Summary

At the END of your response, output a summary:

\`\`\`json:iteration-summary
{
  "storyId": "${story_id}",
  "action": "implemented|skipped|failed",
  "filesChanged": ["path/to/file"],
  "testsRun": true,
  "testsPassed": true,
  "committed": true,
  "notes": "Brief description"
}
\`\`\`

---

## Requirement Document (Reference)

${sanitized_content}
PROMPT_IMPL
}

# ── Story Selection ──────────────────────────────────────────────────────────

# Select the next story to implement (highest priority where passes == false)
# Args: $1 = prd_file
# Prints the story ID, or empty string if all complete
select_next_story() {
  local prd_file="$1"

  if [ ! -f "$prd_file" ]; then
    echo ""
    return 0
  fi

  local story_id
  story_id=$(jq -r '
    [.userStories[] | select(.passes == false)]
    | sort_by(.priority)
    | first
    | .id // empty
  ' "$prd_file" 2>/dev/null)

  echo "$story_id"
}

# Get full story JSON object by ID
# Args: $1 = prd_file, $2 = story_id
get_story_details() {
  local prd_file="$1"
  local story_id="$2"

  jq --arg id "$story_id" '.userStories[] | select(.id == $id)' "$prd_file" 2>/dev/null
}

# ── Claude Invocation ────────────────────────────────────────────────────────

# Run a single Claude invocation
# Args: $1 = prompt_file, $2 = agent_dir, $3 = label, $4 = model
# Returns: output in $CLAUDE_OUTPUT
run_claude_iteration() {
  local prompt_file="$1"
  local agent_dir="$2"
  local label="$3"
  local model="$4"

  local tmpout="$agent_dir/.output-${label}.tmp"

  # Build claude command based on mode
  local claude_cmd="claude --model $model"

  if [ "${REQDRIVE_INTERACTIVE:-true}" = "false" ]; then
    claude_cmd="$claude_cmd --dangerously-skip-permissions"
  fi

  log_info "Running claude [$label] ($([ "${REQDRIVE_INTERACTIVE:-true}" = "true" ] && echo "interactive" || echo "unsafe") mode)..."

  # Execute claude
  if cat "$prompt_file" | timeout 1800 $claude_cmd 2>&1 | tee "$tmpout"; then
    : # Success
  else
    local exit_code=$?
    if [ $exit_code -eq 124 ]; then
      log_error "Claude timed out after 30 minutes"
    elif [ $exit_code -ne 0 ]; then
      log_warn "Claude exited with code $exit_code"
    fi
  fi

  CLAUDE_OUTPUT=$(cat "$tmpout" 2>/dev/null || echo "")
  rm -f "$tmpout"
}

# ── Main Pipeline ────────────────────────────────────────────────────────────

run_pipeline() {
  local req_id="$1"

  if [ -z "$req_id" ]; then
    echo "Usage: reqdrive run <REQ-ID>" >&2
    exit "$EXIT_GENERAL_ERROR"
  fi

  # Normalize to uppercase
  req_id=$(echo "$req_id" | tr '[:lower:]' '[:upper:]')
  local req_slug
  req_slug=$(echo "$req_id" | tr '[:upper:]' '[:lower:]')

  log_info "Starting pipeline for $req_id"

  # ── Setup paths ──
  local req_dir="$REQDRIVE_PROJECT_ROOT/$REQDRIVE_REQUIREMENTS_DIR"
  local branch="reqdrive/$req_slug"
  local base_branch="${REQDRIVE_BASE_BRANCH:-main}"
  local agent_dir="$REQDRIVE_PROJECT_ROOT/.reqdrive/agent"

  # ── Run pre-flight checks ──
  if [ "${REQDRIVE_FORCE:-false}" = "true" ]; then
    log_warn "Skipping pre-flight checks (--force flag used)"
  else
    if ! run_preflight_checks "$base_branch" "$req_dir" "$req_id" "$branch"; then
      exit "$EXIT_PREFLIGHT_FAILED"
    fi
  fi

  # ── Find requirement file ──
  local req_file=""

  for f in "$req_dir/${req_id}"*.md "$req_dir/${req_slug}"*.md; do
    if [ -f "$f" ]; then
      req_file="$f"
      break
    fi
  done

  if [ -z "$req_file" ]; then
    log_error "No requirement file found matching ${req_id}*.md in $req_dir"
    exit "$EXIT_CONFIG_ERROR"
  fi

  log_info "Requirement: $req_file"

  # ── Validate requirement content ──
  local requirement_content
  requirement_content=$(cat "$req_file")

  if ! validate_requirement_content "$requirement_content"; then
    if [ "${REQDRIVE_FORCE:-false}" != "true" ]; then
      exit "$EXIT_PREFLIGHT_FAILED"
    fi
    log_warn "Continuing despite suspicious content (--force flag used)"
  fi

  # ── Check for resume ──
  mkdir -p "$agent_dir"
  local start_iteration=1
  local checkpoint_file=""

  if [ "${REQDRIVE_RESUME:-false}" = "true" ]; then
    checkpoint_file=$(load_checkpoint "$agent_dir" "$req_id")
    if [ -n "$checkpoint_file" ]; then
      local checkpoint_iteration
      checkpoint_iteration=$(jq -r '.iteration' "$checkpoint_file")
      local checkpoint_branch
      checkpoint_branch=$(jq -r '.branch' "$checkpoint_file")
      local checkpoint_time
      checkpoint_time=$(jq -r '.timestamp' "$checkpoint_file")

      log_info "Found checkpoint from $checkpoint_time"
      log_info "  Branch: $checkpoint_branch"
      log_info "  Last completed iteration: $checkpoint_iteration"

      start_iteration=$((checkpoint_iteration + 1))
      branch="$checkpoint_branch"
    else
      log_info "No checkpoint found, starting fresh"
    fi
  fi

  # ── Setup branch ──
  if git show-ref --verify --quiet "refs/heads/$branch" 2>/dev/null; then
    log_info "Switching to existing branch: $branch"
    git checkout "$branch"
  else
    log_info "Creating branch: $branch from $base_branch"
    git checkout -b "$branch" "$base_branch"
  fi

  # ── Setup agent files ──
  local prompt_file="$agent_dir/prompt.md"
  local progress_file="$agent_dir/progress.txt"
  local prd_file="$agent_dir/prd.json"

  # Validate existing PRD on resume
  if [ -f "$prd_file" ]; then
    if ! validate_prd_schema "$prd_file" 2>/dev/null; then
      log_warn "Existing prd.json has schema issues (may be fixed by agent)"
    fi
  fi

  # Initialize progress file if needed
  if [ ! -f "$progress_file" ]; then
    cat > "$progress_file" <<EOF
# Progress Log for $req_id
Started: $(date)
---
EOF
  fi

  # Sanitize the requirement content before embedding in prompts
  local sanitized_content
  sanitized_content=$(sanitize_for_prompt "$requirement_content")

  local max_iterations="${REQDRIVE_MAX_ITERATIONS:-10}"
  local model="${REQDRIVE_MODEL:-claude-sonnet-4-20250514}"
  local completion_signal="<promise>COMPLETE</promise>"
  local CLAUDE_OUTPUT=""

  # ══════════════════════════════════════════════════════════════════════
  # Phase 1: Planning (create PRD if it doesn't exist)
  # ══════════════════════════════════════════════════════════════════════

  if [ ! -f "$prd_file" ]; then
    log_info ""
    log_info "═══════════════════════════════════════════════════════"
    log_info "  Phase 1: Planning"
    log_info "═══════════════════════════════════════════════════════"

    build_planning_prompt "$prompt_file" "$sanitized_content"
    log_info "Planning prompt built"

    local plan_attempts=0
    local plan_max=2

    while [ "$plan_attempts" -lt "$plan_max" ]; do
      plan_attempts=$((plan_attempts + 1))
      log_info "Planning attempt $plan_attempts of $plan_max"

      run_claude_iteration "$prompt_file" "$agent_dir" "plan-$plan_attempts" "$model"

      # Save planning log
      echo "$CLAUDE_OUTPUT" > "$agent_dir/iteration-plan-$plan_attempts.log"
      extract_iteration_summary "$CLAUDE_OUTPUT" "$agent_dir" "plan-$plan_attempts"

      # Check if PRD was created
      if [ -f "$prd_file" ]; then
        if validate_prd_schema "$prd_file" 2>/dev/null; then
          log_info "PRD created and validated successfully"
          break
        else
          log_warn "PRD created but has schema issues"
          if [ "$plan_attempts" -lt "$plan_max" ]; then
            log_info "Retrying planning..."
            rm -f "$prd_file"
          fi
        fi
      else
        log_warn "PRD not created by agent"
        if [ "$plan_attempts" -lt "$plan_max" ]; then
          log_info "Retrying planning..."
        fi
      fi
    done

    if [ ! -f "$prd_file" ]; then
      log_error "Agent failed to create PRD after $plan_max attempts"
      exit "$EXIT_AGENT_ERROR"
    fi

    # Final validation (warn only, don't block)
    if ! validate_prd_schema "$prd_file" 2>/dev/null; then
      log_warn "PRD has schema issues but proceeding with implementation"
    fi
  else
    log_info "PRD exists, skipping planning phase"
  fi

  # ══════════════════════════════════════════════════════════════════════
  # Phase 2: Implementation (one story per iteration)
  # ══════════════════════════════════════════════════════════════════════

  log_info ""
  log_info "═══════════════════════════════════════════════════════"
  log_info "  Phase 2: Implementation"
  log_info "═══════════════════════════════════════════════════════"
  log_info "Starting agent loop (max $max_iterations iterations, starting at $start_iteration)"
  log_info "Model: $model"
  log_info "Mode: ${REQDRIVE_INTERACTIVE:-true} (interactive)"

  for i in $(seq "$start_iteration" "$max_iterations"); do
    echo ""
    log_info "═══════════════════════════════════════════════════════"
    log_info "  Iteration $i of $max_iterations"
    log_info "═══════════════════════════════════════════════════════"

    # Deterministic story selection
    local next_story
    next_story=$(select_next_story "$prd_file")

    if [ -z "$next_story" ]; then
      log_info "All stories complete!"
      break
    fi

    local story_json
    story_json=$(get_story_details "$prd_file" "$next_story")
    local story_title
    story_title=$(echo "$story_json" | jq -r '.title')

    log_info "Target story: $next_story - $story_title"

    # Build story-specific prompt
    build_implementation_prompt "$prompt_file" "$next_story" "$story_json" "$sanitized_content"

    # Run Claude
    run_claude_iteration "$prompt_file" "$agent_dir" "$i" "$model"

    # Save iteration log
    echo "$CLAUDE_OUTPUT" > "$agent_dir/iteration-$i.log"

    # Extract iteration summary
    extract_iteration_summary "$CLAUDE_OUTPUT" "$agent_dir" "$i"

    # Save checkpoint
    save_checkpoint "$agent_dir" "$req_id" "$branch" "$i" "$prd_file"

    # Validate PRD after each iteration
    if [ -f "$prd_file" ]; then
      if ! validate_prd_schema "$prd_file" 2>/dev/null; then
        log_warn "prd.json has schema issues after iteration $i (agent may fix next iteration)"
      fi
    fi

    # Check for completion signal (secondary indicator)
    if echo "$CLAUDE_OUTPUT" | grep -qF "$completion_signal"; then
      log_info ""
      log_info "Agent signaled completion at iteration $i"
      break
    fi

    log_info "Iteration $i complete. Continuing..."
    sleep 2
  done

  # ── Verify completion ──
  local final_remaining="?"
  if [ -f "$prd_file" ]; then
    final_remaining=$(jq '[.userStories[] | select(.passes == false)] | length' "$prd_file" 2>/dev/null || echo "?")
  fi

  if [ "$final_remaining" != "0" ] && [ "$final_remaining" != "?" ]; then
    log_warn "Agent did not complete all stories ($final_remaining remaining)"
    log_warn "Creating draft PR for review"
  fi

  # ── Create PR ──
  log_info ""
  log_info "═══════════════════════════════════════════════════════"
  log_info "  Creating Pull Request"
  log_info "═══════════════════════════════════════════════════════"

  source "$REQDRIVE_ROOT/lib/pr-create.sh"

  local draft_flag=""
  [ "$final_remaining" != "0" ] && [ "$final_remaining" != "?" ] && draft_flag="--draft"

  if create_pr "$REQDRIVE_PROJECT_ROOT" "$req_id" "$branch" "$base_branch" "$draft_flag"; then
    log_info "PR created successfully"
  else
    log_warn "PR creation failed. Branch available at: $branch"
    exit "$EXIT_PR_ERROR"
  fi

  log_info ""
  log_info "Pipeline complete for $req_id"
  exit "$EXIT_SUCCESS"
}
