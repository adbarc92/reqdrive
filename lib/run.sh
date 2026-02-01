#!/usr/bin/env bash
# run.sh - Core Ralph loop: requirement -> implementation -> PR
# Usage: source this file, then call run_pipeline <REQ-ID>

set -e

# ── Logging ──────────────────────────────────────────────────────────────

log_info() { echo "[INFO]  $(date +%H:%M:%S) $*" >&2; }
log_warn() { echo "[WARN]  $(date +%H:%M:%S) $*" >&2; }
log_error() { echo "[ERROR] $(date +%H:%M:%S) $*" >&2; }

# ── Main Pipeline ────────────────────────────────────────────────────────

run_pipeline() {
  local req_id="$1"

  if [ -z "$req_id" ]; then
    echo "Usage: reqdrive run <REQ-ID>" >&2
    exit 1
  fi

  # Normalize to uppercase
  req_id=$(echo "$req_id" | tr '[:lower:]' '[:upper:]')
  local req_slug=$(echo "$req_id" | tr '[:upper:]' '[:lower:]')

  log_info "Starting pipeline for $req_id"

  # ── Find requirement file ──
  local req_dir="$REQDRIVE_PROJECT_ROOT/$REQDRIVE_REQUIREMENTS_DIR"
  local req_file=""

  for f in "$req_dir/${req_id}"*.md "$req_dir/${req_slug}"*.md; do
    if [ -f "$f" ]; then
      req_file="$f"
      break
    fi
  done

  if [ -z "$req_file" ]; then
    log_error "No requirement file found matching ${req_id}*.md in $req_dir"
    exit 1
  fi

  log_info "Requirement: $req_file"

  # ── Setup branch ──
  local branch="reqdrive/$req_slug"
  local base_branch="${REQDRIVE_BASE_BRANCH:-main}"

  # Check if branch exists
  if git show-ref --verify --quiet "refs/heads/$branch" 2>/dev/null; then
    log_info "Switching to existing branch: $branch"
    git checkout "$branch"
  else
    log_info "Creating branch: $branch from $base_branch"
    git checkout -b "$branch" "$base_branch"
  fi

  # ── Setup agent directory ──
  local agent_dir="$REQDRIVE_PROJECT_ROOT/.reqdrive/agent"
  mkdir -p "$agent_dir"

  # ── Build prompt with embedded requirement ──
  local prompt_file="$agent_dir/prompt.md"
  local progress_file="$agent_dir/progress.txt"
  local prd_file="$agent_dir/prd.json"

  # Initialize progress file if needed
  if [ ! -f "$progress_file" ]; then
    cat > "$progress_file" <<EOF
# Progress Log for $req_id
Started: $(date)
---
EOF
  fi

  # Build the prompt
  local requirement_content
  requirement_content=$(cat "$req_file")

  cat > "$prompt_file" <<'PROMPT_START'
# Agent Instructions

You are an autonomous coding agent. Your job is to implement a requirement.

## Phase 1: Planning (if no prd.json exists)

If `.reqdrive/agent/prd.json` does not exist:

1. Read the requirement below
2. Create a PRD with user stories at `.reqdrive/agent/prd.json`:

```json
{
  "project": "<Project> - <Feature>",
  "sourceReq": "<REQ-XX>",
  "description": "...",
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

Rules for stories:
- Target 3-8 stories (combine related items if needed)
- Each story completable in one iteration
- Priority 1 = do first, higher = do later
- All start with `passes: false`

## Phase 2: Implementation

1. Read `.reqdrive/agent/prd.json`
2. Read `.reqdrive/agent/progress.txt` (check Codebase Patterns section)
3. Pick the highest-priority story where `passes: false`
4. Implement that single story
5. Run quality checks (test, typecheck, lint as appropriate)
6. If checks pass:
   - Commit with message: `feat: [Story ID] - [Story Title]`
   - Update PRD: set `passes: true` for this story
   - Append progress to `progress.txt`

## Progress Format

Append to progress.txt:
```
## [Date] - [Story ID]
- What was implemented
- Files changed
- Learnings for future iterations
---
```

## Stop Condition

After completing a story, check if ALL stories have `passes: true`.

If ALL complete: output `<promise>COMPLETE</promise>`
If more remain: end normally (next iteration continues)

## Important

- ONE story per iteration
- Commit after each story
- Keep tests passing

---

## Requirement Document

PROMPT_START

  # Append the actual requirement content
  echo "$requirement_content" >> "$prompt_file"

  log_info "Prompt built at $prompt_file"

  # ── Run Ralph loop ──
  local max_iterations="${REQDRIVE_MAX_ITERATIONS:-10}"
  local model="${REQDRIVE_MODEL:-claude-sonnet-4-20250514}"
  local completion_signal="<promise>COMPLETE</promise>"

  log_info "Starting agent loop (max $max_iterations iterations)"
  log_info "Model: $model"

  for i in $(seq 1 "$max_iterations"); do
    echo ""
    log_info "═══════════════════════════════════════════════════════"
    log_info "  Iteration $i of $max_iterations"
    log_info "═══════════════════════════════════════════════════════"

    # Check story progress if PRD exists
    if [ -f "$prd_file" ]; then
      local remaining
      remaining=$(jq '[.userStories[] | select(.passes == false)] | length' "$prd_file" 2>/dev/null || echo "?")
      log_info "Stories remaining: $remaining"

      if [ "$remaining" = "0" ]; then
        log_info "All stories complete!"
        break
      fi
    fi

    # Run Claude with prompt piped via stdin
    local output=""
    local tmpout="$agent_dir/.output-$i.tmp"

    cat "$prompt_file" | timeout 1800 \
      claude --dangerously-skip-permissions --model "$model" 2>&1 | tee "$tmpout" || true

    output=$(cat "$tmpout" 2>/dev/null || echo "")

    # Save iteration log
    echo "$output" > "$agent_dir/iteration-$i.log"
    rm -f "$tmpout"

    # Check for completion
    if echo "$output" | grep -qF "$completion_signal"; then
      log_info ""
      log_info "Agent completed all stories at iteration $i"
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
  fi

  log_info ""
  log_info "Pipeline complete for $req_id"
}
