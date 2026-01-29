#!/usr/bin/env bash
# config.sh — Locate and parse reqdrive.json manifest, export REQDRIVE_* vars.
# Sourced by bin/reqdrive and other lib scripts.

# ── Locate manifest ──────────────────────────────────────────────────

reqdrive_load_config_path() {
  # Walk up from cwd looking for reqdrive.json
  local dir
  dir="$(pwd)"
  while true; do
    if [ -f "$dir/reqdrive.json" ]; then
      export REQDRIVE_MANIFEST="$dir/reqdrive.json"
      export REQDRIVE_PROJECT_ROOT="$dir"
      return 0
    fi
    local parent
    parent="$(dirname "$dir")"
    if [ "$parent" = "$dir" ]; then
      echo "ERROR: No reqdrive.json found in current directory or any parent." >&2
      echo "Run 'reqdrive init' to create one." >&2
      exit 1
    fi
    dir="$parent"
  done
}

# ── Load and export all config ────────────────────────────────────────

reqdrive_load_config() {
  reqdrive_load_config_path

  local M="$REQDRIVE_MANIFEST"

  # Project
  export REQDRIVE_PROJECT_NAME
  REQDRIVE_PROJECT_NAME="$(jq -r '.project.name // ""' "$M")"
  export REQDRIVE_PROJECT_TITLE
  REQDRIVE_PROJECT_TITLE="$(jq -r '.project.title // ""' "$M")"

  # Paths (relative to project root)
  export REQDRIVE_PATHS_REQUIREMENTS_DIR
  REQDRIVE_PATHS_REQUIREMENTS_DIR="$(jq -r '.paths.requirementsDir // "docs/requirements"' "$M")"
  export REQDRIVE_PATHS_AGENT_DIR
  REQDRIVE_PATHS_AGENT_DIR="$(jq -r '.paths.agentDir // ".reqdrive/agent"' "$M")"
  export REQDRIVE_PATHS_APP_DIR
  REQDRIVE_PATHS_APP_DIR="$(jq -r '.paths.appDir // "."' "$M")"
  export REQDRIVE_PATHS_CONTEXT_FILE
  REQDRIVE_PATHS_CONTEXT_FILE="$(jq -r '.paths.contextFile // "CLAUDE.md"' "$M")"

  # Commands
  export REQDRIVE_CMD_INSTALL
  REQDRIVE_CMD_INSTALL="$(jq -r '.commands.install // ""' "$M")"
  export REQDRIVE_CMD_TEST
  REQDRIVE_CMD_TEST="$(jq -r '.commands.test // ""' "$M")"
  export REQDRIVE_CMD_TYPECHECK
  REQDRIVE_CMD_TYPECHECK="$(jq -r '.commands.typecheck // ""' "$M")"
  export REQDRIVE_CMD_LINT
  REQDRIVE_CMD_LINT="$(jq -r '.commands.lint // ""' "$M")"

  # Agent
  export REQDRIVE_AGENT_MODEL
  REQDRIVE_AGENT_MODEL="$(jq -r '.agent.model // "claude-opus-4-5-20251101"' "$M")"
  export REQDRIVE_AGENT_MAX_ITERATIONS
  REQDRIVE_AGENT_MAX_ITERATIONS="$(jq -r '.agent.maxIterations // 10' "$M")"
  export REQDRIVE_AGENT_BRANCH_PREFIX
  REQDRIVE_AGENT_BRANCH_PREFIX="$(jq -r '.agent.branchPrefix // "reqdrive"' "$M")"
  export REQDRIVE_AGENT_WORKTREE_PREFIX
  REQDRIVE_AGENT_WORKTREE_PREFIX="$(jq -r '.agent.worktreePrefix // "reqdrive"' "$M")"
  export REQDRIVE_AGENT_COMPLETION_SIGNAL
  REQDRIVE_AGENT_COMPLETION_SIGNAL="$(jq -r '.agent.completionSignal // "<promise>COMPLETE</promise>"' "$M")"

  # Orchestration
  export REQDRIVE_ORCH_MAX_PARALLEL
  REQDRIVE_ORCH_MAX_PARALLEL="$(jq -r '.orchestration.maxParallel // 3' "$M")"
  export REQDRIVE_ORCH_WORKTREE_ROOT
  REQDRIVE_ORCH_WORKTREE_ROOT="$(jq -r '.orchestration.worktreeRoot // "../worktrees"' "$M")"
  export REQDRIVE_ORCH_BASE_BRANCH
  REQDRIVE_ORCH_BASE_BRANCH="$(jq -r '.orchestration.baseBranch // "main"' "$M")"
  export REQDRIVE_ORCH_STATE_DIR
  REQDRIVE_ORCH_STATE_DIR="$(jq -r '.orchestration.stateDir // ".reqdrive/state"' "$M")"

  # Verification
  export REQDRIVE_VERIFY_MAX_RETRIES
  REQDRIVE_VERIFY_MAX_RETRIES="$(jq -r '.verification.maxRetries // 3' "$M")"

  # Security
  export REQDRIVE_SECURITY_MODE
  REQDRIVE_SECURITY_MODE="$(jq -r '.security.mode // "interactive"' "$M")"
  export REQDRIVE_SECURITY_ALLOW_TOOLS
  REQDRIVE_SECURITY_ALLOW_TOOLS="$(jq -r '.security.allowedTools // [] | join(",")' "$M")"

  # Requirements
  export REQDRIVE_REQ_PATTERN
  REQDRIVE_REQ_PATTERN="$(jq -r '.requirements.pattern // "REQ-*-*.md"' "$M")"
  export REQDRIVE_REQ_ID_REGEX
  REQDRIVE_REQ_ID_REGEX="$(jq -r '.requirements.idRegex // "REQ-[0-9]+"' "$M")"
}

# ── Helper functions ──────────────────────────────────────────────────

# Resolve a config-relative path to an absolute path
reqdrive_resolve_path() {
  local rel="$1"
  if [[ "$rel" = /* ]]; then
    echo "$rel"
  else
    echo "$REQDRIVE_PROJECT_ROOT/$rel"
  fi
}

# Find the requirements file for a given REQ ID (e.g. REQ-01)
reqdrive_get_req_file() {
  local req_id="$1"
  local req_dir
  req_dir="$(reqdrive_resolve_path "$REQDRIVE_PATHS_REQUIREMENTS_DIR")"
  local match=""
  for f in "$req_dir/${req_id}"*.md; do
    if [ -f "$f" ]; then
      match="$f"
      break
    fi
  done
  if [ -z "$match" ]; then
    return 1
  fi
  echo "$match"
}

# Get dependencies for a given REQ ID from the manifest
reqdrive_get_deps() {
  local req_id="$1"
  jq -r --arg req "$req_id" '.requirements.dependencies[$req] // [] | .[]' "$REQDRIVE_MANIFEST"
}

# Expand {variable} placeholders in a string using current env
reqdrive_expand_template() {
  local template="$1"
  local result="$template"
  # Replace known placeholders
  result="${result//\{branch\}/$2}"
  result="${result//\{project\}/$REQDRIVE_PROJECT_NAME}"
  result="${result//\{title\}/$REQDRIVE_PROJECT_TITLE}"
  echo "$result"
}

# Build Claude CLI security arguments based on security mode
# Returns the appropriate flags for the given stage
reqdrive_claude_security_args() {
  local stage="${1:-agent}"  # agent, prd, or verify

  case "$REQDRIVE_SECURITY_MODE" in
    dangerous)
      # User explicitly opted into dangerous mode with full awareness
      echo "--dangerously-skip-permissions"
      ;;
    allowlist)
      # Use allowedTools if configured
      if [ -n "$REQDRIVE_SECURITY_ALLOW_TOOLS" ]; then
        echo "--allowedTools $REQDRIVE_SECURITY_ALLOW_TOOLS"
      else
        # No allowlist configured, fall back to interactive
        echo ""
      fi
      ;;
    interactive|*)
      # Default: no special flags, Claude Code will prompt for permissions
      echo ""
      ;;
  esac
}

# Portable timestamp (works on both GNU and BSD date)
reqdrive_timestamp() {
  date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date +%Y-%m-%dT%H:%M:%S%z
}

# Portable date-based run ID
reqdrive_run_id() {
  date +%Y%m%d-%H%M%S
}
