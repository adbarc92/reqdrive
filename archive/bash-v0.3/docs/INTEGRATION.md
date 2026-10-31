# Integration Guide: Using reqdrive in a Larger Pipeline

This document specifies how to integrate reqdrive into an outer orchestration pipeline for overnight or unattended app development.

## Overview

reqdrive is designed to be one stage in a larger automation pipeline. It takes a markdown requirement as input and produces a GitHub PR as output. Between invocation and PR, it generates machine-readable state files that an outer pipeline can poll, inspect, and act on.

```
┌─────────────────────────────────────────────────────────┐
│  Outer Pipeline                                         │
│                                                         │
│  ┌──────────┐    ┌──────────┐    ┌──────────┐          │
│  │ REQ-01   │───>│ REQ-02   │───>│ REQ-03   │──> ...   │
│  │ reqdrive │    │ reqdrive │    │ reqdrive │          │
│  └──────────┘    └──────────┘    └──────────┘          │
│       │               │               │                │
│       v               v               v                │
│   run.json        run.json        run.json             │
│   (result)        (result)        (result)             │
│                                                         │
│  Decision logic: continue / retry / abort / notify      │
└─────────────────────────────────────────────────────────┘
```

## Prerequisites

The target project must have:

1. `reqdrive.json` at the project root (run `reqdrive init` interactively first)
2. Requirement files in the configured `requirementsDir` (default: `docs/requirements/`)
3. A clean git working tree on the configured `baseBranch`
4. `gh` authenticated with push and PR create permissions
5. `claude` CLI installed and authenticated

## Invocation

### Foreground (recommended for pipelines)

```bash
reqdrive run REQ-01 --unsafe
```

The `--unsafe` flag grants the agent unrestricted permissions (required for unattended operation). The process blocks until the pipeline completes or fails.

**Exit codes:**

| Code | Name | Meaning |
|------|------|---------|
| 0 | `EXIT_SUCCESS` | Pipeline completed, PR created |
| 1 | `EXIT_GENERAL_ERROR` | Unexpected error |
| 2 | `EXIT_MISSING_DEPENDENCY` | `jq`, `git`, `gh`, or `claude` not found |
| 3 | `EXIT_CONFIG_ERROR` | Bad `reqdrive.json` or missing requirement file |
| 4 | `EXIT_GIT_ERROR` | Git operation failed (checkout, commit, push) |
| 5 | `EXIT_AGENT_ERROR` | Claude invocation failed (timeout, crash, no PRD) |
| 6 | `EXIT_PR_ERROR` | PR creation failed after retry |
| 7 | `EXIT_USER_ABORT` | User sent SIGINT (not applicable in unattended mode) |
| 8 | `EXIT_PREFLIGHT_FAILED` | Dirty working tree, missing branch, or missing req file |

### Background (fire-and-forget)

```bash
reqdrive launch REQ-01
```

Returns immediately with a PID. Always uses `--unsafe` mode. Use `reqdrive status REQ-01` or read `run.json` directly to check progress.

### Resume after interruption

```bash
reqdrive run REQ-01 --unsafe --resume
```

Picks up from the last saved checkpoint. Safe to call whether or not a checkpoint exists — starts fresh if none found.

### Skip preflight checks

```bash
reqdrive run REQ-01 --unsafe --force
```

Bypasses clean-tree and branch-existence checks. Useful when the outer pipeline has already validated git state.

## Reading Results

After a run completes, two files contain the machine-readable results.

### `run.json`

**Path:** `.reqdrive/runs/<req-slug>/run.json`

```json
{
  "status": "completed",
  "pid": 12345,
  "req_id": "REQ-01",
  "started_at": "2026-02-21T22:00:00-06:00",
  "updated_at": "2026-02-21T23:15:00-06:00",
  "current_iteration": 5,
  "exit_code": 0,
  "pr_url": "https://github.com/org/repo/pull/42",
  "summary": {
    "iterations_run": 5,
    "tests_passed": 4,
    "tests_failed": 1,
    "tests_skipped": 0,
    "commits_verified": 4,
    "commits_missing": 1,
    "stories_completed": 3,
    "stories_failed": 0,
    "stories_total": 4,
    "verification_passed": true
  }
}
```

**Field reference:**

| Field | Type | Description |
|-------|------|-------------|
| `status` | string | `"running"`, `"completed"`, `"failed"`, `"interrupted"` |
| `pid` | number | Process ID of the reqdrive run |
| `req_id` | string | Requirement ID (e.g., `"REQ-01"`) |
| `started_at` | string | ISO 8601 timestamp of pipeline start |
| `updated_at` | string | ISO 8601 timestamp of last status update |
| `current_iteration` | number | Last iteration number reached |
| `exit_code` | number\|null | Process exit code (`null` while running) |
| `pr_url` | string\|null | GitHub PR URL (`null` if not created) |
| `summary` | object\|null | Pipeline result summary (`null` if pipeline didn't reach implementation) |
| `summary.iterations_run` | number | Total implementation iterations executed |
| `summary.tests_passed` | number | Iterations where `testCommand` passed |
| `summary.tests_failed` | number | Iterations where `testCommand` failed |
| `summary.tests_skipped` | number | Iterations where no `testCommand` was configured |
| `summary.commits_verified` | number | Iterations where agent produced expected commit |
| `summary.commits_missing` | number | Iterations where expected commit was not found |
| `summary.stories_completed` | number | Stories marked `passes: true` in PRD |
| `summary.stories_failed` | number | Stories that exhausted their retry limit |
| `summary.stories_total` | number | Total stories in PRD |
| `summary.verification_passed` | boolean\|null | Final test suite result (`null` if no `testCommand`) |

### `verification-summary.json`

**Path:** `.reqdrive/runs/<req-slug>/verification-summary.json`

Written at the end of Phase 3 (verification), before PR creation.

```json
{
  "version": "0.3.0",
  "req_id": "REQ-01",
  "timestamp": "2026-02-21T23:14:50-06:00",
  "stories": {
    "total": 4,
    "completed": 3,
    "failed": 0,
    "remaining": 1
  },
  "iterations": {
    "run": 5,
    "max": 10
  },
  "tests": {
    "passed": 4,
    "failed": 1,
    "skipped": 0
  },
  "commits": {
    "verified": 4,
    "missing": 1
  },
  "verification_passed": true
}
```

## Completion Hook

The `completionHook` config field runs a shell command when the pipeline ends (success or failure). The following environment variables are available:

| Variable | Example | Description |
|----------|---------|-------------|
| `REQ_ID` | `REQ-01` | Requirement ID |
| `STATUS` | `completed` or `failed` | Pipeline outcome |
| `PR_URL` | `https://github.com/...` | PR URL (empty on failure) |
| `BRANCH` | `reqdrive/req-01` | Feature branch name |
| `EXIT_CODE` | `0` | Numeric exit code |

### Example: Slack notification

```json
{
  "completionHook": "curl -s -X POST https://hooks.slack.com/services/T.../B.../xxx -H 'Content-type: application/json' -d '{\"text\": \"reqdrive: $REQ_ID $STATUS $PR_URL\"}'"
}
```

### Example: Write result to shared file

```json
{
  "completionHook": "echo \"$REQ_ID,$STATUS,$EXIT_CODE,$PR_URL\" >> /shared/reqdrive-results.csv"
}
```

## Orchestration Patterns

### Sequential requirements (bash script)

```bash
#!/usr/bin/env bash
# run-overnight.sh — Run multiple requirements sequentially
set -euo pipefail

REQS=("REQ-01" "REQ-02" "REQ-03")
RESULTS_FILE="overnight-results.json"
echo "[]" > "$RESULTS_FILE"

for req in "${REQS[@]}"; do
  echo "=== Starting $req ==="
  req_slug=$(echo "$req" | tr '[:upper:]' '[:lower:]')

  # Run the pipeline (--force skips preflight since we manage git state)
  if reqdrive run "$req" --unsafe --force; then
    echo "$req completed successfully"
  else
    exit_code=$?
    echo "$req failed with exit code $exit_code"
  fi

  # Read results from run.json
  run_file=".reqdrive/runs/$req_slug/run.json"
  if [ -f "$run_file" ]; then
    # Append result to results array
    jq --arg req "$req" '. += [input | . + {"req_id": $req}]' \
      "$RESULTS_FILE" "$run_file" > "${RESULTS_FILE}.tmp" \
      && mv "${RESULTS_FILE}.tmp" "$RESULTS_FILE"
  fi

  # Return to base branch for the next requirement
  git checkout "$(jq -r '.baseBranch // "main"' reqdrive.json)"
done

echo "=== Overnight run complete ==="
echo "Results:"
jq -r '.[] | "\(.req_id): \(.status) — \(.pr_url // "no PR")"' "$RESULTS_FILE"
```

### Continue-on-error with summary

```bash
#!/usr/bin/env bash
# run-all.sh — Run all requirements, don't stop on failure
set -uo pipefail

REQS=("REQ-01" "REQ-02" "REQ-03")
FAILED=()
SUCCEEDED=()

for req in "${REQS[@]}"; do
  req_slug=$(echo "$req" | tr '[:upper:]' '[:lower:]')
  base_branch=$(jq -r '.baseBranch // "main"' reqdrive.json)

  # Ensure clean state
  git checkout "$base_branch" 2>/dev/null

  if reqdrive run "$req" --unsafe --force; then
    SUCCEEDED+=("$req")
  else
    FAILED+=("$req")
  fi

  # Return to base for next run
  git checkout "$base_branch" 2>/dev/null || true
done

echo ""
echo "=== Summary ==="
echo "Succeeded (${#SUCCEEDED[@]}): ${SUCCEEDED[*]:-none}"
echo "Failed (${#FAILED[@]}): ${FAILED[*]:-none}"

# Exit non-zero if anything failed
[ ${#FAILED[@]} -eq 0 ]
```

### Conditional logic based on verification results

```bash
#!/usr/bin/env bash
# smart-pipeline.sh — Act on verification results

req="$1"
req_slug=$(echo "$req" | tr '[:upper:]' '[:lower:]')

reqdrive run "$req" --unsafe || true

run_file=".reqdrive/runs/$req_slug/run.json"
verify_file=".reqdrive/runs/$req_slug/verification-summary.json"

# Read key metrics
status=$(jq -r '.status' "$run_file")
verification=$(jq -r '.summary.verification_passed' "$run_file" 2>/dev/null)
stories_done=$(jq -r '.summary.stories_completed' "$run_file" 2>/dev/null)
stories_total=$(jq -r '.summary.stories_total' "$run_file" 2>/dev/null)

case "$status" in
  completed)
    if [ "$verification" = "true" ]; then
      echo "READY: $req — all tests pass, PR ready for review"
    else
      echo "DRAFT: $req — tests failing, PR created as draft"
      # Optionally: retry with --resume
    fi
    ;;
  failed)
    echo "FAILED: $req — pipeline did not complete"
    echo "  Stories: $stories_done / $stories_total"
    # Optionally: retry or alert
    ;;
  interrupted)
    echo "INTERRUPTED: $req — resumable with --resume"
    ;;
esac
```

## Polling for Background Runs

When using `reqdrive launch`, poll `run.json` for completion:

```bash
req_slug="req-01"
run_file=".reqdrive/runs/$req_slug/run.json"

# Poll every 30 seconds
while true; do
  if [ ! -f "$run_file" ]; then
    sleep 30
    continue
  fi

  status=$(jq -r '.status' "$run_file")
  case "$status" in
    running)
      iteration=$(jq -r '.current_iteration' "$run_file")
      echo "Still running — iteration $iteration"
      sleep 30
      ;;
    completed|failed|interrupted)
      echo "Finished with status: $status"
      break
      ;;
  esac
done
```

## PID Liveness Check

The `pid` field in `run.json` allows you to verify if a "running" status is stale:

```bash
pid=$(jq -r '.pid' "$run_file")
if kill -0 "$pid" 2>/dev/null; then
  echo "Process is alive"
else
  echo "Process is gone — run crashed"
fi
```

`reqdrive status` does this check automatically and reports crashed runs.

## Configuration for Unattended Operation

Recommended `reqdrive.json` for overnight runs:

```json
{
  "version": "0.3.0",
  "requirementsDir": "docs/requirements",
  "testCommand": "npm test",
  "model": "claude-sonnet-4-20250514",
  "maxIterations": 15,
  "baseBranch": "main",
  "prLabels": ["agent-generated"],
  "projectName": "My App",
  "completionHook": "curl -s -X POST $SLACK_WEBHOOK -d '{\"text\": \"$REQ_ID: $STATUS $PR_URL\"}'"
}
```

Key settings:

- **`testCommand`**: Set this. Without it, the verification phase has no test signal and `verification_passed` will be `null`. The pipeline will still create PRs, but you won't know if they work.
- **`maxIterations`**: Default is 10. For complex requirements (5+ stories), consider 15-20. Each iteration is one story attempt, and stories can retry up to `maxStoryRetries` (default 3) times.
- **`model`**: `claude-sonnet-4-20250514` is the default. Use `claude-opus-4-6` for more complex requirements that need stronger reasoning.
- **`completionHook`**: Set this for notifications. Without it, you'll need to poll `run.json` or check `reqdrive status` manually.

## File Layout Reference

After a completed run, the run directory contains:

```
.reqdrive/runs/req-01/
├── run.json                    # Pipeline status + summary (machine-readable)
├── prd.json                    # Generated PRD with story status
├── checkpoint.json             # Resume state (iteration, branch, SHA)
├── progress.txt                # Agent progress log (human-readable)
├── prompt.md                   # Last iteration prompt
├── verification-summary.json   # Phase 3 verification results
├── verification.test.log       # Final test suite output
├── iteration-plan-1.log        # Planning phase agent output
├── iteration-1.log             # Implementation iteration output
├── iteration-1.summary.json    # Structured iteration summary
├── iteration-1.test.log        # Per-iteration test output
├── iteration-2.log
├── iteration-2.summary.json
├── iteration-2.test.log
└── output.log                  # Full stdout/stderr (launch only)
```

## Interpreting Results

### Is the PR safe to review?

```bash
verification=$(jq -r '.summary.verification_passed' run.json)
commits_missing=$(jq -r '.summary.commits_missing' run.json)

if [ "$verification" = "true" ] && [ "$commits_missing" = "0" ]; then
  echo "High confidence — tests pass, all commits verified"
elif [ "$verification" = "true" ]; then
  echo "Medium confidence — tests pass but some commits missing"
else
  echo "Low confidence — review carefully"
fi
```

### How much of the requirement was completed?

```bash
completed=$(jq -r '.summary.stories_completed' run.json)
total=$(jq -r '.summary.stories_total' run.json)
pct=$((completed * 100 / total))
echo "$pct% complete ($completed/$total stories)"
```

### Should I retry?

Retry is worthwhile when:
- `status` is `"failed"` with `exit_code` 5 (agent error) — transient agent failure
- `stories_completed > 0` but `stories_total > stories_completed` — partial progress
- `verification_passed` is `false` but `stories_completed == stories_total` — all stories done but tests failing

Do not retry when:
- `exit_code` is 2 (missing dependency) or 3 (config error) — environment problem
- `exit_code` is 8 (preflight failed) — git state issue
- `stories_failed > 0` — stories exhausted their retry limit within the run

## Limitations

- **No file locking**: Two concurrent runs targeting the same REQ-ID will race on shared state files. The outer pipeline must ensure only one run per REQ-ID at a time.
- **No parallel multi-requirement runs**: Each run operates on a single branch. Running multiple requirements simultaneously requires git worktrees (not yet implemented in `reqdrive orchestrate`).
- **Agent self-reporting is advisory**: The agent marks stories as `passes: true` in `prd.json`. This is a self-report, not independently verified. The `verification_passed` field from the final test suite run is the authoritative signal.
- **`testCommand` is warn-only during implementation**: Test failures during iterations are logged but don't abort or force retries. Only the final verification test influences the draft/ready PR decision.
- **Platform variance**: `nohup` and process tracking behave differently on MSYS2/Git Bash vs Linux. PID liveness checks may be unreliable on MSYS2. Prefer foreground `run` over `launch` when reliability matters.
