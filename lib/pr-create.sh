#!/usr/bin/env bash
# pr-create.sh - Create a PR with validation checklist from PRD

# Source sanitize if not already loaded
if ! type sanitize_label &>/dev/null; then
  source "${REQDRIVE_ROOT:-$(dirname "${BASH_SOURCE[0]}")/..}/lib/sanitize.sh"
fi

create_pr() {
  local project_root="$1"
  local req="$2"
  local branch="$3"
  local base_branch="$4"
  local draft_flag="${5:-}"
  local agent_dir="${6:-}"

  # Fall back to runs dir based on req slug, then legacy path
  if [ -z "$agent_dir" ]; then
    local req_slug
    req_slug=$(echo "$req" | tr '[:upper:]' '[:lower:]')
    agent_dir="$project_root/.reqdrive/runs/$req_slug"
  fi
  local prd_file="$agent_dir/prd.json"

  # Push branch
  echo "  Pushing branch $branch..."
  git push -u origin "$branch" || {
    echo "  ERROR: Failed to push branch"
    return 1
  }

  # Extract info from PRD if it exists
  local project="$req Implementation"
  local story_count="0"
  local story_ids=""
  local checklist=""

  if [ -f "$prd_file" ]; then
    project=$(jq -r '.project // "Feature Implementation"' "$prd_file")
    story_count=$(jq '.userStories | length' "$prd_file")
    story_ids=$(jq -r '.userStories | map(.id) | join(", ")' "$prd_file")

    # Build validation checklist from acceptance criteria
    while IFS= read -r story; do
      local id title
      id=$(echo "$story" | jq -r '.id')
      title=$(echo "$story" | jq -r '.title')
      checklist+=$'\n'"### $id: $title"$'\n'
      while IFS= read -r criterion; do
        checklist+="- [ ] $criterion"$'\n'
      done < <(echo "$story" | jq -r '.acceptanceCriteria[]')
    done < <(jq -c '.userStories[]' "$prd_file")
  fi

  # Get commit summary
  local commits
  commits=$(git log --oneline "$base_branch".."$branch" 2>/dev/null || echo "No commits found")

  # Load verification summary if it exists
  local verification_file="$agent_dir/verification-summary.json"
  local verification_section=""
  if [ -f "$verification_file" ]; then
    local v_stories_completed v_stories_total v_stories_failed
    local v_tests_passed v_tests_failed v_tests_skipped
    local v_commits_verified v_commits_missing
    local v_iterations_run v_iterations_max
    local v_verification_passed

    v_stories_completed=$(jq -r '.stories.completed' "$verification_file" 2>/dev/null || echo "?")
    v_stories_total=$(jq -r '.stories.total' "$verification_file" 2>/dev/null || echo "?")
    v_stories_failed=$(jq -r '.stories.failed' "$verification_file" 2>/dev/null || echo "0")
    v_tests_passed=$(jq -r '.tests.passed' "$verification_file" 2>/dev/null || echo "0")
    v_tests_failed=$(jq -r '.tests.failed' "$verification_file" 2>/dev/null || echo "0")
    v_tests_skipped=$(jq -r '.tests.skipped' "$verification_file" 2>/dev/null || echo "0")
    v_commits_verified=$(jq -r '.commits.verified' "$verification_file" 2>/dev/null || echo "0")
    v_commits_missing=$(jq -r '.commits.missing' "$verification_file" 2>/dev/null || echo "0")
    v_iterations_run=$(jq -r '.iterations.run' "$verification_file" 2>/dev/null || echo "?")
    v_iterations_max=$(jq -r '.iterations.max' "$verification_file" 2>/dev/null || echo "?")
    v_verification_passed=$(jq -r '.verification_passed' "$verification_file" 2>/dev/null || echo "null")

    local v_status_icon="⚠️"
    if [ "$v_verification_passed" = "true" ]; then
      v_status_icon="✅"
    elif [ "$v_verification_passed" = "false" ]; then
      v_status_icon="❌"
    fi

    verification_section=$(cat <<VSEOF

## Pipeline Verification $v_status_icon

| Metric | Result |
|--------|--------|
| Stories | $v_stories_completed / $v_stories_total completed |
| Failed stories | $v_stories_failed (exhausted retries) |
| Iterations | $v_iterations_run / $v_iterations_max used |
| Test runs passed | $v_tests_passed |
| Test runs failed | $v_tests_failed |
| Tests skipped | $v_tests_skipped |
| Commits verified | $v_commits_verified |
| Commits missing | $v_commits_missing |
| Final verification | $v_verification_passed |
VSEOF
    )
  fi

  # Build label flags with proper sanitization
  local labels=()

  if [ -n "${REQDRIVE_PR_LABELS:-}" ]; then
    IFS=',' read -ra config_labels <<< "$REQDRIVE_PR_LABELS"
    for label in "${config_labels[@]}"; do
      local sanitized
      sanitized=$(sanitize_label "$label")
      if [ -n "$sanitized" ]; then
        labels+=("$sanitized")
      fi
    done
  fi

  # Add REQ-specific label (sanitized)
  local req_label
  req_label=$(echo "$req" | tr '[:upper:]' '[:lower:]')
  req_label=$(sanitize_label "$req_label")
  if [ -n "$req_label" ]; then
    labels+=("$req_label")
  fi

  # Build label arguments - each label properly quoted
  local label_args=()
  for label in "${labels[@]}"; do
    label_args+=("--label" "$label")
  done

  # Build PR body
  local pr_body
  pr_body=$(cat <<EOF
## Summary
- **Source:** $req
- **Branch:** \`$branch\`
- **Stories completed:** $story_ids ($story_count stories)

## Commits
\`\`\`
$commits
\`\`\`
$verification_section

## Validation Checklist

> Complete these checks before approving.

### Setup
- [ ] Pull branch: \`git checkout $branch\`
- [ ] Install dependencies
- [ ] Run tests locally

### Functional Verification
$checklist

### Regression Check
- [ ] Existing tests pass
- [ ] No unintended side effects

---
Generated by [reqdrive](https://github.com/anthropics/reqdrive)
EOF
  )

  # Create PR — capture URL from gh output
  echo "  Creating PR..." >&2
  local pr_url=""

  if pr_url=$(gh pr create \
    $draft_flag \
    --base "$base_branch" \
    --head "$branch" \
    "${label_args[@]}" \
    --title "$project" \
    --body "$pr_body" 2>&2); then
    : # success
  else
    local gh_exit=$?
    # Retry without labels — they're the most common failure point
    # (e.g., label doesn't exist on the repo)
    if [ ${#label_args[@]} -gt 0 ]; then
      echo "  WARN: gh pr create failed (exit $gh_exit), retrying without labels..." >&2
      if pr_url=$(gh pr create \
        $draft_flag \
        --base "$base_branch" \
        --head "$branch" \
        --title "$project" \
        --body "$pr_body" 2>&2); then
        : # success on retry
      else
        echo "  ERROR: gh pr create failed on retry (exit $?)" >&2
        return 1
      fi
    else
      echo "  ERROR: gh pr create failed (exit $gh_exit)" >&2
      return 1
    fi
  fi

  # pr_url should contain the URL printed by gh pr create on success.
  # If it's empty (e.g., gh printed URL to stderr instead), fall back to gh pr view.
  if [ -z "$pr_url" ] || ! echo "$pr_url" | grep -q "^https://"; then
    pr_url=$(gh pr view "$branch" --json url --jq '.url' 2>/dev/null || echo "")
  fi

  echo "  PR created: $branch" >&2
  [ -n "$pr_url" ] && echo "  URL: $pr_url" >&2

  # Output URL to stdout for caller to capture
  echo "$pr_url"
  return 0
}
