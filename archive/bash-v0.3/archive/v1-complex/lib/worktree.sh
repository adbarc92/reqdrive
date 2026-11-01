#!/usr/bin/env bash
# worktree.sh — Git worktree setup and teardown with error handling
# Sourced by run-single-req.sh

# Requires errors.sh to be loaded (for log_* functions and error codes)

setup_worktree() {
  local project_root="$1"
  local worktree_path="$2"
  local branch="$3"
  local base_branch="$4"

  cd "$project_root"

  # ── Clean Up Existing Worktree ──────────────────────────────────────
  if [ -d "$worktree_path" ]; then
    log_info "  Removing existing worktree at $worktree_path"

    # Try graceful removal first
    if ! git worktree remove "$worktree_path" 2>/dev/null; then
      log_warn "  Graceful removal failed, trying force removal"

      if ! git worktree remove "$worktree_path" --force 2>/dev/null; then
        log_warn "  Force removal failed, manually cleaning up"

        # Manual cleanup as last resort
        rm -rf "$worktree_path"
        git worktree prune 2>/dev/null || true
      fi
    fi
  fi

  # ── Ensure Parent Directory Exists ──────────────────────────────────
  local worktree_parent
  worktree_parent=$(dirname "$worktree_path")
  if [ ! -d "$worktree_parent" ]; then
    log_debug "  Creating worktree parent directory: $worktree_parent"
    mkdir -p "$worktree_parent"
  fi

  # ── Create or Reuse Branch ──────────────────────────────────────────
  if git show-ref --verify --quiet "refs/heads/$branch"; then
    log_info "  Branch $branch exists, creating worktree"

    if ! git worktree add "$worktree_path" "$branch" 2>&1; then
      log_error "  Failed to create worktree for existing branch $branch"
      return $ERR_WORKTREE
    fi
  else
    log_info "  Creating new branch $branch from $base_branch"

    # Verify base branch exists
    if ! git show-ref --verify --quiet "refs/heads/$base_branch"; then
      # Try remote
      if ! git show-ref --verify --quiet "refs/remotes/origin/$base_branch"; then
        log_error "  Base branch $base_branch not found locally or on remote"
        return $ERR_GIT
      fi
      base_branch="origin/$base_branch"
    fi

    if ! git worktree add "$worktree_path" -b "$branch" "$base_branch" 2>&1; then
      log_error "  Failed to create worktree with new branch $branch"
      return $ERR_WORKTREE
    fi
  fi

  # ── Verify Worktree Created ─────────────────────────────────────────
  if [ ! -d "$worktree_path" ]; then
    log_error "  Worktree directory not created at $worktree_path"
    return $ERR_WORKTREE
  fi

  if [ ! -f "$worktree_path/.git" ]; then
    log_error "  Worktree .git file not found - worktree may be corrupted"
    return $ERR_WORKTREE
  fi

  # ── Copy Agent Infrastructure ───────────────────────────────────────
  local agent_dir
  agent_dir="$(reqdrive_resolve_path "$REQDRIVE_PATHS_AGENT_DIR")"
  local wt_agent_dir="$worktree_path/$REQDRIVE_PATHS_AGENT_DIR"

  mkdir -p "$wt_agent_dir"

  # Copy prompt.md if it exists in the source
  if [ -f "$agent_dir/prompt.md" ]; then
    cp "$agent_dir/prompt.md" "$wt_agent_dir/"
    log_debug "  Copied prompt.md to worktree"
  else
    log_warn "  No prompt.md found at $agent_dir/prompt.md"
  fi

  # Initialize progress file
  {
    echo "# Agent Progress Log"
    echo "Started: $(reqdrive_timestamp)"
    echo "Branch: $branch"
    echo "---"
  } > "$wt_agent_dir/progress.txt"

  log_info "  Worktree ready at $worktree_path"
  return 0
}

teardown_worktree() {
  local project_root="$1"
  local worktree_path="$2"
  local keep_on_failure="${3:-false}"

  cd "$project_root"

  if [ ! -d "$worktree_path" ]; then
    log_debug "  Worktree already removed: $worktree_path"
    return 0
  fi

  if [ "$keep_on_failure" = "true" ]; then
    log_info "  Keeping worktree for debugging: $worktree_path"
    return 0
  fi

  log_info "  Removing worktree: $worktree_path"

  # Try graceful removal
  if git worktree remove "$worktree_path" 2>/dev/null; then
    log_debug "  Worktree removed gracefully"
    return 0
  fi

  # Force removal
  if git worktree remove "$worktree_path" --force 2>/dev/null; then
    log_debug "  Worktree force-removed"
    return 0
  fi

  # Manual cleanup
  log_warn "  Git worktree remove failed, cleaning up manually"
  rm -rf "$worktree_path"
  git worktree prune 2>/dev/null || true

  return 0
}

# List all reqdrive worktrees
list_worktrees() {
  local project_root="$1"
  local prefix="${REQDRIVE_AGENT_WORKTREE_PREFIX:-reqdrive}"

  cd "$project_root"

  git worktree list --porcelain | grep "^worktree" | cut -d' ' -f2 | while read -r wt; do
    if [[ "$wt" == *"$prefix"* ]]; then
      echo "$wt"
    fi
  done
}

# Clean all reqdrive worktrees
clean_all_worktrees() {
  local project_root="$1"

  cd "$project_root"

  local count=0
  list_worktrees "$project_root" | while read -r wt; do
    log_info "  Removing: $wt"
    teardown_worktree "$project_root" "$wt"
    count=$((count + 1))
  done

  # Prune any orphaned worktree references
  git worktree prune 2>/dev/null || true

  log_info "  Worktree cleanup complete"
}
