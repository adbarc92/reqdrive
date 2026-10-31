# skills-and-archive (canon)

`skills/**`, `archive/**` — 4 governing requirements. **Index module:** many
small independent peers, one row each.

## Purpose

Two quarantined bodies of content: four Claude Code skills a human invokes
interactively, and the archived v0.1.x implementation retained as design
reference. Neither is reachable from the running pipeline.

## Peer inventory

| Peer | Path | Kind | One line |
|------|------|------|----------|
| design-to-prd | skills/design-to-prd/SKILL.md | skill | design docs → requirements; writes markdown `tasks/prd-<feature>.md`, **not** the pipeline's `prd.json` |
| prd | skills/prd/SKILL.md | skill | feature idea → PRD; same markdown output shape |
| project-journal | skills/project-journal/SKILL.md | skill | maintains `FOR[username].md`; competes with the `docs/STATUS.md` convention |
| verification-workflow | skills/verification-workflow/SKILL.md | skill | overlaps Phase 3 / `reqdrive verify`, but is human-invoked |
| errors.sh | archive/v1-complex/lib/errors.sh | archived-lib | 385 lines; the only archived file that still resolves its own symbols (`ERR_*`, `log_*`) |
| worktree.sh | archive/v1-complex/lib/worktree.sh | archived-lib | 176 lines; the stated reason archive/ is kept — see gotchas |
| orchestrate.sh | archive/v1-complex/lib/orchestrate.sh | archived-lib | 181 lines; parallel run driver |
| run-single-req.sh | archive/v1-complex/lib/run-single-req.sh | archived-lib | 279 lines; sources a `pr-create.sh` that is not in the archive (:252) |
| verify.sh | archive/v1-complex/lib/verify.sh | archived-lib | 168 lines; the name `lib/verification.sh` exists to avoid colliding with it |
| prd-gen · agent-run · agent-tasks · deps · check-deps · find-next-reqs · status · clean | archive/v1-complex/lib/ | archived-lib | 123/122/79/79/63/56/37/22 lines |
| prompt.md.tpl · prompt-tasks.md.tpl · reqdrive.json.tpl | archive/v1-complex/templates/ | template | v0.1.x prompt and 30-field manifest templates |
| PHASE1-VALIDATION-GUIDE · VALIDATION-PLAN · SESSION-STATE-2025-01-30 | archive/docs/ | archived-doc | frozen history |

## Invariants

- No file under `archive/` is sourced, executed, or otherwise reachable from `bin/` or `lib/` at runtime — the only `archive` mention in live code is a naming comment. (lib/verification.sh:4-5; repo-wide grep: 2 hits, both comments)
- Git worktree support is absent from the active pipeline — zero occurrences of `worktree` in `bin/`, `lib/`, `tests/`. (grep)
- `skills/` is never loaded by the pipeline; zero occurrences of `skills` in `bin/`, `lib/`, `tests/`. They load only through interactive Claude Code invocation. (skills/README.md:3)
- The v0.1.x command surface has not returned: dispatch exposes exactly `init|run|validate|status|migrate|plan|verify|orchestrate|launch|logs`. (bin/reqdrive:680-722)
- `reqdrive orchestrate` remains a pure stub touching no worktree code. (bin/reqdrive:579-586)

## Dependencies

Internal: none at runtime — that is the point. `bin/reqdrive:579-586` is the
placeholder for what `orchestrate.sh` + `worktree.sh` would become. External:
Claude Code `/skill` invocation (skills only); `git worktree` (archived only).

## Gotchas

- `archive/v1-complex/` is **not a faithful v0.1.x snapshot**: the v0.1.x `config.sh` was deleted rather than archived, and seven archived scripts still `source "${REQDRIVE_ROOT}/lib/config.sh"` — which now silently resolves to the *live* 0.3.0 loader. (archive/v1-complex/lib/check-deps.sh:8 and six siblings)
- Consequently `worktree.sh` is not drop-in revivable: `reqdrive_resolve_path` (:81), `reqdrive_timestamp` (:97), `$REQDRIVE_PATHS_AGENT_DIR` and `$REQDRIVE_AGENT_WORKTREE_PREFIX` are defined **nowhere** in the repo. Its other dependencies (`ERR_WORKTREE`, `ERR_GIT`, `log_info`, `log_warn`) *do* resolve, via the co-archived `errors.sh:32-50`. Reviving it means porting a path resolver and two env vars — not a rewrite. → [drift ARCHIVE-ROT](../requirements/drift-report.md#ARCHIVE-ROT)
- `skills/README.md:29-30` is stale: it lists `reqdrive plan` as "(coming soon)" and `reqdrive verify` as "(future)". Both shipped. (bin/reqdrive:394, :440)
- The `cmd_orchestrate` stub promises **sequential** processing while CLAUDE.md:222 defines `orchestrate` as **parallelism via git worktrees** — the two descriptions of the same unbuilt command disagree. (bin/reqdrive:580-585)
- The `prd` and `design-to-prd` skills emit markdown PRDs, not the `prd.json` the pipeline consumes — they are adjacent tools, not pipeline components. (skills/prd/SKILL.md:134-138 vs lib/run.sh:224-240)
- Nothing enforces the quarantine: no test asserts that `archive/` and `skills/` stay unreachable, so a future `source .../archive/...` would pass CI.

## Requirement coverage

4 governing reqs: **2 satisfied · 1 drifted · 1 unimplemented (roadmap)**.

| REQ | Status | Canon (intended) | Link |
|-----|--------|------------------|------|
| CLD-061 | satisfied | worktree support stays archived, not reintroduced | — |
| CLD-070 | satisfied | multi-requirement parallelism stays deferred | — |
| CLD-059 | drifted | keep the library at the simplified ~5-script shape | [drift-report](../requirements/drift-report.md#CLD-059) |
| CLD-093 | unimplemented | `orchestrate` builds worktree parallelism | roadmap — index.json#unbuilt_features |

Scale, measured: `archive/` is 3,446 lines across 19 files and `skills/` 1,639
lines — 5,085 inert lines against 3,410 live (`bin/` + `lib/`). Live `lib/`
(2,683 lines / 11 files) is now **larger** than the 1,770-line / 13-file v0.1.x
`lib/` the simplification replaced.

## Pointers

The stub that would consume this: [cli.md](cli.md). The simplification claim:
[../requirements/drift-report.md#CLD-059](../requirements/drift-report.md#CLD-059).
