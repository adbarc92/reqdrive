#!/usr/bin/env bash
# preflight.sh - Pre-flight safety checks for reqdrive

# Source errors if not already loaded
if [ -z "$EXIT_PREFLIGHT_FAILED" ]; then
  source "${REQDRIVE_ROOT:-$(dirname "${BASH_SOURCE[0]}")/..}/lib/errors.sh"
fi

# ── Individual Checks ────────────────────────────────────────────────────────

# Check for clean working tree (no uncommitted changes)
check_clean_working_tree() {
  if ! git diff --quiet 2>/dev/null; then
    echo "[PREFLIGHT] Working tree has unstaged changes." >&2
    echo "            Please commit or stash your changes first." >&2
    echo "" >&2
    echo "  Unstaged files:" >&2
    git diff --name-only 2>/dev/null | sed 's/^/    /' >&2
    return 1
  fi

  if ! git diff --cached --quiet 2>/dev/null; then
    echo "[PREFLIGHT] Working tree has staged but uncommitted changes." >&2
    echo "            Please commit or unstage your changes first." >&2
    echo "" >&2
    echo "  Staged files:" >&2
    git diff --cached --name-only 2>/dev/null | sed 's/^/    /' >&2
    return 1
  fi

  return 0
}

# Check if branch already exists (locally or on remote)
check_branch_conflicts() {
  local branch="$1"

  # Check local
  if git show-ref --verify --quiet "refs/heads/$branch" 2>/dev/null; then
    echo "[PREFLIGHT] Branch '$branch' already exists locally." >&2
    echo "            The pipeline will switch to this branch and continue." >&2
    # This is a warning, not an error - we allow continuing on existing branches
    return 0
  fi

  # Check remote
  if git ls-remote --heads origin "$branch" 2>/dev/null | grep -q .; then
    echo "[PREFLIGHT] Branch '$branch' already exists on remote." >&2
    echo "            This may cause conflicts if the remote has changes." >&2
    echo "            Consider pulling the branch first or using a different name." >&2
    # Warning only, not a hard failure
    return 0
  fi

  return 0
}

# Check that base branch exists
check_base_branch_exists() {
  local base_branch="$1"

  # Check local
  if git show-ref --verify --quiet "refs/heads/$base_branch" 2>/dev/null; then
    return 0
  fi

  # Check remote
  if git ls-remote --heads origin "$base_branch" 2>/dev/null | grep -q .; then
    echo "[PREFLIGHT] Base branch '$base_branch' exists on remote but not locally." >&2
    echo "            Fetching..." >&2
    git fetch origin "$base_branch:$base_branch" 2>/dev/null || {
      echo "[PREFLIGHT] Could not fetch base branch '$base_branch' from origin." >&2
      return 1
    }
    return 0
  fi

  echo "[PREFLIGHT] Base branch '$base_branch' does not exist." >&2
  echo "            Please verify your baseBranch setting in reqdrive.json" >&2
  return 1
}

# Check that requirements directory exists
check_requirements_dir() {
  local req_dir="$1"

  if [ ! -d "$req_dir" ]; then
    echo "[PREFLIGHT] Requirements directory does not exist: $req_dir" >&2
    echo "            Please create it or update requirementsDir in reqdrive.json" >&2
    return 1
  fi

  # Check if there are any .md files
  if ! ls "$req_dir"/*.md >/dev/null 2>&1; then
    echo "[PREFLIGHT] No requirement files (*.md) found in: $req_dir" >&2
    echo "            Create a requirement file first, e.g.: ${req_dir}/REQ-01-feature-name.md" >&2
    return 1
  fi

  return 0
}

# Check that requirement file exists
check_requirement_exists() {
  local req_id="$1"
  local req_dir="$2"

  local req_slug
  req_slug=$(echo "$req_id" | tr '[:upper:]' '[:lower:]')
  local req_id_upper
  req_id_upper=$(echo "$req_id" | tr '[:lower:]' '[:upper:]')

  local found=0
  for f in "$req_dir/${req_id_upper}"*.md "$req_dir/${req_slug}"*.md; do
    if [ -f "$f" ]; then
      found=1
      break
    fi
  done

  if [ "$found" -eq 0 ]; then
    echo "[PREFLIGHT] Requirement file not found for: $req_id" >&2
    echo "            Expected pattern: ${req_dir}/${req_id_upper}*.md" >&2
    echo "" >&2
    echo "  Available requirements:" >&2
    ls "$req_dir"/*.md 2>/dev/null | xargs -I{} basename {} | sed 's/^/    /' >&2 || echo "    (none)" >&2
    return 1
  fi

  return 0
}

# Check we're in a git repository
check_git_repo() {
  if ! git rev-parse --git-dir >/dev/null 2>&1; then
    echo "[PREFLIGHT] Not in a git repository." >&2
    echo "            Please run reqdrive from within a git repository." >&2
    return 1
  fi
  return 0
}

# ── Main Preflight Function ──────────────────────────────────────────────────

# Run all pre-flight checks
# Arguments:
#   $1 - base branch name
#   $2 - requirements directory
#   $3 - requirement ID
#   $4 - target branch name
# Returns:
#   0 if all checks pass
#   EXIT_PREFLIGHT_FAILED if any check fails
run_preflight_checks() {
  local base_branch="$1"
  local req_dir="$2"
  local req_id="$3"
  local branch="$4"

  local failed=0

  echo "[INFO]  Running pre-flight checks..." >&2

  # Critical checks (must pass)
  check_git_repo || failed=1

  if [ "$failed" -eq 0 ]; then
    check_clean_working_tree || failed=1
  fi

  if [ "$failed" -eq 0 ]; then
    check_base_branch_exists "$base_branch" || failed=1
  fi

  if [ "$failed" -eq 0 ]; then
    check_requirements_dir "$req_dir" || failed=1
  fi

  if [ "$failed" -eq 0 ]; then
    check_requirement_exists "$req_id" "$req_dir" || failed=1
  fi

  # Non-critical checks (warnings only)
  if [ "$failed" -eq 0 ]; then
    check_branch_conflicts "$branch" || true
  fi

  if [ "$failed" -eq 1 ]; then
    echo "" >&2
    echo "[ERROR] Pre-flight checks failed. Use --force to bypass (not recommended)." >&2
    return "$EXIT_PREFLIGHT_FAILED"
  fi

  echo "[INFO]  Pre-flight checks passed." >&2
  return 0
}
