#!/usr/bin/env bash
# prd-gen.sh — PRD generation via Claude Code
# Sourced by run-single-req.sh

generate_prd() {
  local req_file="$1"
  local worktree_path="$2"
  local model="$3"

  local agent_dir="$worktree_path/$REQDRIVE_PATHS_AGENT_DIR"
  local req_basename
  req_basename=$(basename "$req_file")

  echo "  Generating PRD from $req_basename"
  echo "  Output: $agent_dir/prd.json"

  local branch_prefix="$REQDRIVE_AGENT_BRANCH_PREFIX"
  local project_title="$REQDRIVE_PROJECT_TITLE"
  local context_file="$REQDRIVE_PATHS_CONTEXT_FILE"

  # Get security arguments for PRD generation stage
  local security_args
  security_args=$(reqdrive_claude_security_args prd)

  # Use Claude Code with the design-to-prd skill to generate prd.json
  # shellcheck disable=SC2086
  claude $security_args --model "$model" -p "$(cat <<PROMPT
Load the design-to-prd skill. Then process the requirements document at:
$req_file

Configuration:
- Document type: Requirements specification
- Scope: Full feature set
- Audience: AI agents (very explicit, small stories)
- Existing systems: Yes, documented in $context_file

Output the agent-ready prd.json to: $agent_dir/prd.json
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
)" 2>&1

  # Verify prd.json was created
  if [ ! -f "$agent_dir/prd.json" ]; then
    echo "  ERROR: PRD generation failed - no prd.json produced"
    return 1
  fi

  # Validate JSON structure
  if ! jq empty "$agent_dir/prd.json" 2>/dev/null; then
    echo "  ERROR: Generated prd.json is not valid JSON"
    return 1
  fi

  local story_count
  story_count=$(jq '.userStories | length' "$agent_dir/prd.json")
  echo "  PRD generated: $story_count stories"
  return 0
}
