#!/usr/bin/env bash
# worktree.sh — Git worktree setup and teardown
# Sourced by run-single-req.sh

setup_worktree() {
  local project_root="$1"
  local worktree_path="$2"
  local branch="$3"
  local base_branch="$4"

  cd "$project_root"

  # Clean up existing worktree if present
  if [ -d "$worktree_path" ]; then
    echo "  Removing existing worktree at $worktree_path"
    git worktree remove "$worktree_path" --force 2>/dev/null || true
  fi

  # Create branch if it doesn't exist
  if git show-ref --verify --quiet "refs/heads/$branch"; then
    echo "  Branch $branch exists, creating worktree"
    git worktree add "$worktree_path" "$branch"
  else
    echo "  Creating new branch $branch from $base_branch"
    git worktree add "$worktree_path" -b "$branch" "$base_branch"
  fi

  # Copy agent infrastructure into worktree
  local agent_dir
  agent_dir="$(reqdrive_resolve_path "$REQDRIVE_PATHS_AGENT_DIR")"
  local wt_agent_dir="$worktree_path/$REQDRIVE_PATHS_AGENT_DIR"

  mkdir -p "$wt_agent_dir"

  # Copy prompt.md if it exists in the source
  if [ -f "$agent_dir/prompt.md" ]; then
    cp "$agent_dir/prompt.md" "$wt_agent_dir/"
  fi

  # Initialize progress file
  echo "# Agent Progress Log" > "$wt_agent_dir/progress.txt"
  echo "Started: $(reqdrive_timestamp)" >> "$wt_agent_dir/progress.txt"
  echo "---" >> "$wt_agent_dir/progress.txt"
}

teardown_worktree() {
  local project_root="$1"
  local worktree_path="$2"

  cd "$project_root"
  git worktree remove "$worktree_path" --force 2>/dev/null || true
}
