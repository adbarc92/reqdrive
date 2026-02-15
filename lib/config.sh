#!/usr/bin/env bash
# config.sh - Minimal configuration loader for reqdrive
# Finds reqdrive.json and exports REQDRIVE_* environment variables

# Source schema versioning
source "${REQDRIVE_ROOT:-$(dirname "${BASH_SOURCE[0]}")/..}/lib/schema.sh"

# ── Find manifest ────────────────────────────────────────────────────────

reqdrive_find_manifest() {
  local dir
  dir="$(pwd)"

  while true; do
    if [ -f "$dir/reqdrive.json" ]; then
      echo "$dir/reqdrive.json"
      return 0
    fi

    local parent
    parent="$(dirname "$dir")"

    if [ "$parent" = "$dir" ]; then
      return 1
    fi

    dir="$parent"
  done
}

# ── Load config ──────────────────────────────────────────────────────────

reqdrive_load_config() {
  local manifest
  manifest=$(reqdrive_find_manifest) || {
    echo "ERROR: No reqdrive.json found. Run 'reqdrive init' to create one." >&2
    exit 1
  }

  export REQDRIVE_MANIFEST="$manifest"
  export REQDRIVE_PROJECT_ROOT="$(dirname "$manifest")"

  # Check schema version
  check_schema_version "$manifest" || {
    echo "ERROR: Incompatible config version. Run 'reqdrive migrate' to update." >&2
    exit 1
  }

  # Core settings (with sensible defaults)
  export REQDRIVE_REQUIREMENTS_DIR
  REQDRIVE_REQUIREMENTS_DIR="$(jq -r '.requirementsDir // "docs/requirements"' "$manifest")"

  export REQDRIVE_TEST_COMMAND
  REQDRIVE_TEST_COMMAND="$(jq -r '.testCommand // ""' "$manifest")"

  export REQDRIVE_MODEL
  REQDRIVE_MODEL="$(jq -r '.model // "claude-sonnet-4-20250514"' "$manifest")"

  export REQDRIVE_MAX_ITERATIONS
  REQDRIVE_MAX_ITERATIONS="$(jq -r '.maxIterations // 10' "$manifest")"

  export REQDRIVE_BASE_BRANCH
  REQDRIVE_BASE_BRANCH="$(jq -r '.baseBranch // "main"' "$manifest")"

  export REQDRIVE_PR_LABELS
  REQDRIVE_PR_LABELS="$(jq -r '.prLabels // ["agent-generated"] | join(",")' "$manifest")"

  # Optional: project name for PR titles
  export REQDRIVE_PROJECT_NAME
  REQDRIVE_PROJECT_NAME="$(jq -r '.projectName // ""' "$manifest")"

  # Optional: shell command to run on pipeline completion
  export REQDRIVE_COMPLETION_HOOK
  REQDRIVE_COMPLETION_HOOK="$(jq -r '.completionHook // ""' "$manifest")"
}

# ── Helpers ──────────────────────────────────────────────────────────────

reqdrive_get_req_file() {
  local req_id="$1"
  local req_dir="$REQDRIVE_PROJECT_ROOT/$REQDRIVE_REQUIREMENTS_DIR"

  for f in "$req_dir/${req_id}"*.md; do
    if [ -f "$f" ]; then
      echo "$f"
      return 0
    fi
  done

  return 1
}
