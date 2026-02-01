# reqdrive v0.2.0 Simplification Summary

**Date:** 2026-01-31
**Change Type:** Major architectural simplification

## Executive Summary

Reduced reqdrive from an over-engineered 17-script enterprise system to a lean 5-script workflow based on the proven "Ralph pattern" - a simple loop that pipes prompts to Claude until completion.

## Motivation

The original reqdrive was built with enterprise features that added complexity without immediate value:
- 5-stage pipeline (worktree → PRD → agent → verify → PR)
- Parallel execution via git worktrees
- Separate Claude calls for PRD generation and verification
- 12 specific error codes with recovery logic
- Checkpoint/resume capability
- 50+ environment variables
- Dependency-ordered multi-requirement orchestration

For most use cases, a simpler approach works: read requirement, run Claude, create PR.

## The Ralph Pattern

The simplification is based on a pattern discovered in `elevation-broker/scripts/ralph/`:

```bash
for i in $(seq 1 $MAX_ITERATIONS); do
  cat prompt.md | claude --dangerously-skip-permissions | tee output
  if grep "COMPLETE" output; then exit 0; fi
done
```

Key insights:
1. **Pipe stdin instead of -p flag** - Avoids shell quoting issues
2. **Single Claude invocation per iteration** - Agent handles its own planning
3. **Simple completion signal** - `<promise>COMPLETE</promise>`
4. **Loop externally** - Bash controls iterations, Claude does work

## What Changed

### Removed (Archived to `archive/v1-complex/`)

| File | Lines | Purpose | Why Removed |
|------|-------|---------|-------------|
| `agent-run.sh` | 122 | External iteration loop | Merged into run.sh |
| `agent-tasks.sh` | 79 | Tasks-based agent | Redundant approach |
| `errors.sh` | 386 | Error codes, retry logic | Over-engineered |
| `verify.sh` | 158 | Separate verification | Agent self-verifies |
| `prd-gen.sh` | 123 | PRD generation | Agent generates inline |
| `worktree.sh` | 147 | Git worktree management | Sequential is fine |
| `orchestrate.sh` | 182 | Parallel orchestration | Deferred to v2 |
| `run-single-req.sh` | 280 | 5-stage pipeline | Replaced by run.sh |
| `check-deps.sh` | 46 | Dependency checking | Deferred to v2 |
| `find-next-reqs.sh` | 45 | Find available reqs | Deferred to v2 |
| `deps.sh` | 58 | Dependency graph | Deferred to v2 |
| `status.sh` | 35 | Status reporting | Simplified |
| `clean.sh` | 18 | Worktree cleanup | No worktrees |

**Total archived: 1,679 lines across 13 files**

### Simplified

| File | Before | After | Change |
|------|--------|-------|--------|
| `bin/reqdrive` | 99 lines, 8 commands | 78 lines, 3 commands | Removed unused commands |
| `lib/config.sh` | 182 lines, 50+ vars | 67 lines, 7 vars | Minimal config |
| `lib/init.sh` | 231 lines | 89 lines | Creates minimal config |
| `lib/validate.sh` | 181 lines | 55 lines | Basic validation |
| `lib/pr-create.sh` | 158 lines | 95 lines | Works with minimal config |

### Created

| File | Lines | Purpose |
|------|-------|---------|
| `lib/run.sh` | 201 | Core pipeline: branch → prompt → loop → PR |
| `templates/reqdrive.json.example` | 9 | Minimal config example |
| `ROADMAP.md` | ~150 | Simplification plan and tracking |
| `docs/SIMPLIFICATION-SUMMARY.md` | this file | Reference documentation |

## New Architecture

### Before (v0.1.x)
```
reqdrive run REQ-01
    │
    ├── Stage 1: worktree.sh (create isolated worktree)
    │
    ├── Stage 2: prd-gen.sh (Claude call #1 - generate PRD)
    │
    ├── Stage 3: agent-run.sh (Claude call #2-N - implement)
    │   └── Loop with checkpoint saves
    │
    ├── Stage 4: verify.sh (Claude call - verify/fix)
    │   └── Retry loop up to 3x
    │
    └── Stage 5: pr-create.sh (create GitHub PR)
```

### After (v0.2.0)
```
reqdrive run REQ-01
    │
    ├── Create branch: reqdrive/req-01
    │
    ├── Build prompt (requirement embedded)
    │
    ├── Loop until COMPLETE:
    │   └── cat prompt | claude | check for signal
    │
    └── Create PR
```

## New Configuration

### Before (30+ fields)
```json
{
  "project": { "name": "...", "title": "..." },
  "paths": { "requirementsDir": "...", "agentDir": "...", "appDir": "...", "contextFile": "..." },
  "requirements": { "pattern": "...", "idRegex": "...", "dependencies": {} },
  "commands": { "install": "...", "test": "...", "typecheck": "...", "lint": "..." },
  "agent": { "model": "...", "maxIterations": 10, "branchPrefix": "...", "completionSignal": "..." },
  "verification": { "maxRetries": 3, "checks": [], "generateTests": true },
  "pr": { "labels": [], "reqLabel": true, "setupSteps": [], "regressionChecks": [] },
  "orchestration": { "maxParallel": 3, "baseBranch": "main", "stateDir": "..." },
  "security": { "mode": "interactive", "allowedTools": [] }
}
```

### After (7 fields)
```json
{
  "requirementsDir": "docs/requirements",
  "testCommand": "npm test",
  "model": "claude-sonnet-4-20250514",
  "maxIterations": 10,
  "baseBranch": "main",
  "prLabels": ["agent-generated"],
  "projectName": "My Project"
}
```

## New CLI

### Before
```
reqdrive init                    Scaffold manifest + agent prompt
reqdrive run REQ-01 REQ-03       Run specific requirements
reqdrive run --all               Run all (respecting deps)
reqdrive run --next              Auto-detect next available
reqdrive status [run-id]         Show run status
reqdrive clean                   Remove worktrees
reqdrive validate                Validate manifest
reqdrive deps                    Print dependency graph
```

### After
```
reqdrive init              Create reqdrive.json config
reqdrive run <REQ-ID>      Run pipeline for a requirement
reqdrive validate          Validate config
```

## How the New Pipeline Works

### 1. Branch Creation
```bash
git checkout -b reqdrive/req-01 main
```

### 2. Prompt Building
The prompt is built inline in `run.sh` with:
- Planning instructions (create PRD if not exists)
- Implementation instructions (pick highest-priority story)
- Progress tracking instructions
- The actual requirement content embedded at the end

### 3. Agent Loop
```bash
for i in $(seq 1 "$max_iterations"); do
  cat "$prompt_file" | timeout 1800 \
    claude --dangerously-skip-permissions --model "$model" 2>&1 | tee output

  if grep -qF "<promise>COMPLETE</promise>" output; then
    break
  fi
done
```

### 4. PR Creation
Uses existing `pr-create.sh` which:
- Pushes branch
- Extracts story info from `prd.json`
- Builds validation checklist from acceptance criteria
- Creates PR via `gh pr create`

## Agent Behavior

The agent (Claude) now handles:
1. **Planning** - Creates `prd.json` with user stories if it doesn't exist
2. **Implementation** - Picks highest-priority incomplete story
3. **Verification** - Runs tests after each change
4. **Progress** - Updates PRD and progress.txt
5. **Completion** - Outputs `<promise>COMPLETE</promise>` when done

All in a single Claude session per iteration.

## Migration Notes

### For Existing Users

1. **Config migration**: Create new minimal `reqdrive.json`:
   ```bash
   reqdrive init  # Will prompt to overwrite
   ```

2. **Archived features**: If you need:
   - Parallel execution → Restore `worktree.sh`, `orchestrate.sh`
   - Dependency ordering → Restore `deps.sh`, `check-deps.sh`
   - Detailed error handling → Restore `errors.sh`

   Files are in `archive/v1-complex/lib/`

3. **Security mode**: v0.2.0 uses `--dangerously-skip-permissions` by default. Run in sandboxed environments only.

## Metrics

| Metric | Before | After | Reduction |
|--------|--------|-------|-----------|
| lib/ scripts | 17 | 5 | 71% |
| lib/ lines | 1,770 | 587 | 67% |
| Config fields | 30+ | 7 | 77% |
| Pipeline stages | 5 | 2 | 60% |
| Claude calls per run | 3+ | 1 per iteration | Variable |

## Future Enhancements (v2+)

These features were intentionally deferred:

1. **`--parallel` flag** - Re-enable worktree-based parallelization
2. **`--deps` flag** - Re-enable dependency ordering
3. **`--generate-prd` flag** - Separate PRD generation step
4. **`--interactive` flag** - Non-dangerous security mode
5. **Resume capability** - Checkpoint/restart from failures

## References

- Original Ralph implementation: `elevation-broker/scripts/ralph/ralph.sh`
- Archived v1 implementation: `archive/v1-complex/`
- Roadmap: `ROADMAP.md`
