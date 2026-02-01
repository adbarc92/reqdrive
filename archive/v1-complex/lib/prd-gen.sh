#!/usr/bin/env bash
# prd-gen.sh — PRD generation via Claude Code with error handling
# Sourced by run-single-req.sh

# Requires errors.sh to be loaded

generate_prd() {
  local req_file="$1"
  local worktree_path="$2"
  local model="$3"
  local timeout_secs="${4:-600}"  # Default 10 minutes

  local agent_dir="$worktree_path/$REQDRIVE_PATHS_AGENT_DIR"
  local prd_file="$agent_dir/prd.json"
  local req_basename
  req_basename=$(basename "$req_file")

  log_info "  Generating PRD from $req_basename"
  log_info "  Output: $prd_file"

  # Ensure agent directory exists
  mkdir -p "$agent_dir"

  local branch_prefix="$REQDRIVE_AGENT_BRANCH_PREFIX"
  local project_title="$REQDRIVE_PROJECT_TITLE"
  local context_file="$REQDRIVE_PATHS_CONTEXT_FILE"

  # Get security arguments for PRD generation stage
  local security_args
  security_args=$(reqdrive_claude_security_args prd)

  # Build the prompt
  local prompt
  prompt=$(cat <<PROMPT
Load the design-to-prd skill. Then process the requirements document at:
$req_file

Configuration:
- Document type: Requirements specification
- Scope: Full feature set
- Audience: AI agents (very explicit, small stories)
- Existing systems: Yes, documented in $context_file

Output the agent-ready prd.json to: $prd_file
Also output the human-readable PRD to: $agent_dir/prd-readable.md

The prd.json must follow this exact structure:
{
  "project": "$project_title - <Feature Name>",
  "sourceReq": "<REQ-XX>",
  "branchName": "$branch_prefix/<feature-slug>",
  "description": "...",
  "userStories": [
    {
      "id": "US-XXX",
      "title": "...",
      "description": "...",
      "acceptanceCriteria": ["..."],
      "priority": 1,
      "passes": false,
      "notes": ""
    }
  ]
}

Rules:
- The "sourceReq" field must match the REQ identifier from the filename
- The branchName must match the pattern: $branch_prefix/<feature-slug>
- Each user story must have "passes": false initially
- Target 5-12 user stories. If the REQ has more than 12 functional requirements, combine related ones into single stories
- Each story should be completable in a single coding iteration
- Priority should be 1 (highest) to N (lowest), assigned based on dependency order
- acceptanceCriteria should be concrete, testable statements
PROMPT
  )

  # Run Claude with prompt piped via stdin (Ralph pattern)
  log_info "  Running Claude for PRD generation..."

  local output=""

  # Pipe prompt to Claude, show output in real-time with tee
  # shellcheck disable=SC2086
  output=$(echo "$prompt" | timeout "$timeout_secs" \
    claude $security_args --model "$model" 2>&1 | tee /dev/stderr) || true

  # Save output for debugging
  echo "$output" > "$agent_dir/prd-gen.log"

  # Verify prd.json was created
  if [ ! -f "$prd_file" ]; then
    log_error "  PRD generation failed - no prd.json produced"
    log_debug "  Check $agent_dir/prd-gen.log for details"
    return $ERR_PRD
  fi

  # Validate JSON structure (detailed validation done by caller)
  if ! jq empty "$prd_file" 2>/dev/null; then
    log_error "  Generated prd.json is not valid JSON"

    # Try to extract JSON from output (Claude sometimes wraps in markdown)
    log_info "  Attempting to extract JSON from output..."
    local extracted
    extracted=$(echo "$output" | sed -n '/^{/,/^}/p' | head -1000)
    if echo "$extracted" | jq empty 2>/dev/null; then
      echo "$extracted" > "$prd_file"
      log_info "  Extracted valid JSON from output"
    else
      return $ERR_PRD_INVALID
    fi
  fi

  local story_count
  story_count=$(jq '.userStories | length' "$prd_file" 2>/dev/null || echo 0)

  if [ "$story_count" -eq 0 ]; then
    log_error "  PRD has no user stories"
    return $ERR_PRD_INVALID
  fi

  log_info "  PRD generated: $story_count stories"
  return 0
}
