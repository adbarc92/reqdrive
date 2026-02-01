# reqdrive Simplification Roadmap

## Vision

Transform reqdrive from an over-engineered enterprise system (23 scripts, 2000+ lines) into a lean, reusable workflow built on the proven Ralph pattern (85 lines).

## Current State

```
reqdrive/
├── bin/reqdrive                    # CLI entry point
├── lib/
│   ├── agent-run.sh               # Loop-based agent (redundant)
│   ├── agent-tasks.sh             # Tasks-based agent (keep concept)
│   ├── check-deps.sh              # Dependency checking
│   ├── clean.sh                   # Worktree cleanup
│   ├── config.sh                  # 50+ env vars (over-complex)
│   ├── deps.sh                    # Dependency graph
│   ├── errors.sh                  # 12 error codes (unnecessary)
│   ├── find-next-reqs.sh          # Find available reqs
│   ├── init.sh                    # Interactive setup
│   ├── orchestrate.sh             # Parallel orchestration
│   ├── prd-gen.sh                 # Separate PRD generation
│   ├── pr-create.sh               # PR creation (keep)
│   ├── run-single-req.sh          # 5-stage pipeline (over-complex)
│   ├── status.sh                  # Status reporting
│   ├── validate.sh                # Manifest validation
│   ├── verify.sh                  # Separate verification
│   └── worktree.sh                # Git worktree management
├── templates/
│   ├── prompt.md.tpl              # Agent prompt
│   ├── prompt-tasks.md.tpl        # Tasks-based prompt
│   └── reqdrive.json.tpl          # Full manifest template
├── skills/                        # Claude Code skills
└── tests/                         # Test suite
```

**Problems:**
- 5-stage pipeline when 2 stages suffice (run agent → create PR)
- Two agent implementations (loop vs tasks)
- Separate PRD generation, verification phases
- Complex error codes never used for recovery
- Git worktrees add complexity for rare parallelization needs
- 50+ environment variables

## Target State

```
reqdrive/
├── bin/reqdrive                    # CLI entry point (simplified)
├── lib/
│   ├── config.sh                  # Minimal config (~50 lines)
│   ├── run.sh                     # Core Ralph loop + PR creation
│   └── pr-create.sh               # PR creation (kept as-is)
├── templates/
│   ├── prompt.md                  # Single agent prompt
│   └── reqdrive.json.example      # Minimal example config
├── skills/                        # Keep for reference
└── tests/                         # Update for new structure
```

**4 scripts instead of 17.**

## What Changes

### Delete (move to `archive/`)
| File | Reason |
|------|--------|
| `lib/agent-run.sh` | Redundant with Ralph loop |
| `lib/agent-tasks.sh` | Merged into run.sh |
| `lib/errors.sh` | Over-engineered; use simple exit codes |
| `lib/verify.sh` | Agent handles its own verification |
| `lib/prd-gen.sh` | Optional; inline into prompt |
| `lib/worktree.sh` | Sequential execution is fine for v1 |
| `lib/orchestrate.sh` | No parallelization in v1 |
| `lib/run-single-req.sh` | Replaced by simpler run.sh |
| `lib/check-deps.sh` | Defer to v2 |
| `lib/find-next-reqs.sh` | Defer to v2 |
| `lib/deps.sh` | Defer to v2 |
| `lib/status.sh` | Simplified status in run.sh |
| `lib/clean.sh` | No worktrees to clean |
| `templates/prompt-tasks.md.tpl` | Merged into prompt.md |
| `templates/reqdrive.json.tpl` | Replace with minimal example |

### Keep (as-is or minimal changes)
| File | Changes |
|------|---------|
| `bin/reqdrive` | Simplify command dispatch |
| `lib/config.sh` | Reduce to ~50 lines |
| `lib/pr-create.sh` | Keep; it's well-designed |
| `lib/init.sh` | Simplify for minimal config |
| `lib/validate.sh` | Simplify validation |
| `skills/` | Keep as prompt references |
| `tests/` | Update for new structure |

### Create
| File | Purpose |
|------|---------|
| `lib/run.sh` | Core Ralph loop with integrated PR |
| `templates/prompt.md` | Unified agent prompt |
| `templates/reqdrive.json.example` | Minimal config example |
| `archive/` | Store removed files for reference |

## New Manifest Format

**Before (30+ fields):**
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

**After (6 fields):**
```json
{
  "requirementsDir": "docs/requirements",
  "testCommand": "npm test",
  "model": "claude-opus-4-5-20251101",
  "maxIterations": 10,
  "baseBranch": "main",
  "prLabels": ["agent-generated"]
}
```

## New Pipeline

```
┌─────────────────────────────────────────────────────────────────┐
│  reqdrive run REQ-01                                            │
├─────────────────────────────────────────────────────────────────┤
│  1. Load config (6 fields)                                      │
│  2. Find requirement file (REQ-01*.md)                          │
│  3. Create branch: reqdrive/req-01                              │
│  4. Build prompt (embed requirement + PRD instructions)         │
│  5. Loop until COMPLETE or max iterations:                      │
│     │  cat prompt.md | claude --dangerously-skip-permissions    │
│     │  Check for <promise>COMPLETE</promise>                    │
│  6. Create PR with gh                                           │
└─────────────────────────────────────────────────────────────────┘
```

**One script. One loop. One PR.**

## Implementation Steps

### Phase 1: Archive & Restructure
- [x] Create `archive/v1-complex/` directory
- [x] Move deleted files to archive (13 scripts)
- [x] Update .gitignore if needed

### Phase 2: Implement Simplified Core
- [x] Create `lib/run.sh` (Ralph loop + PR)
- [x] Simplify `lib/config.sh`
- [x] Prompt embedded in run.sh (no separate template needed)
- [x] Create `templates/reqdrive.json.example`

### Phase 3: Update CLI
- [x] Simplify `bin/reqdrive` command dispatch
- [x] Update `lib/init.sh` for minimal config
- [x] Simplify `lib/validate.sh`

### Phase 4: Documentation & Tests
- [ ] Update README/docs
- [ ] Update tests for new structure
- [ ] Add migration notes for existing users

## Results

| Metric | Before | After | Reduction |
|--------|--------|-------|-----------|
| lib/ scripts | 17 | 5 | 71% |
| lib/ lines | 1770 | 587 | 67% |
| Config fields | 30+ | 7 | 77% |
| Pipeline stages | 5 | 2 | 60% |

## Future Enhancements (v2)

These features are intentionally deferred:

1. **Parallelization** - Add `--parallel` flag with worktrees
2. **Dependency ordering** - Re-add deps.sh for multi-req runs
3. **PRD generation** - Add `--generate-prd` flag
4. **Resume capability** - Add checkpointing back if needed
5. **Security modes** - Add `--interactive` flag for non-dangerous mode

## Success Criteria

- [ ] `reqdrive run REQ-01` works end-to-end
- [ ] Total lib/ code under 300 lines
- [ ] Config has 6 or fewer fields
- [ ] Single Claude invocation loop (no separate PRD/verify calls)
- [ ] PR creation works as before
