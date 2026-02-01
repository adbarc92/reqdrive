#!/usr/bin/env bash
# clean.sh — Remove all reqdrive worktrees
# Dispatched from bin/reqdrive as: reqdrive clean

set -e

source "${REQDRIVE_ROOT}/lib/config.sh"
reqdrive_load_config

echo "Cleaning up worktrees..."
cd "$REQDRIVE_PROJECT_ROOT"

PREFIX="$REQDRIVE_AGENT_WORKTREE_PREFIX"

git worktree list | grep "$PREFIX-" | awk '{print $1}' | while read -r wt; do
  echo "  Removing: $wt"
  git worktree remove "$wt" --force 2>/dev/null || true
done

echo "  Pruning stale worktree references..."
git worktree prune
echo "Done."
