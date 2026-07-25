# pipeline (canon)

`lib/run.sh` — 212 governing requirements.

## Purpose

Owns the whole requirement→PR lifecycle (setup, Phase 1 planning, Phase 2 story
loop, Phase 3 verification, PR creation, Phase 4 review) and all durable run
state. The shell decides *which* story is worked and whether the PR opens as a
draft; the Claude subprocess only writes code.

## Public interface

| Symbol | Kind | Anchor | Notes |
|--------|------|--------|-------|
| `run_pipeline` | function | lib/run.sh:855 | the full pipeline; sole caller of every phase |
| `run_plan` | function | lib/run.sh:743 | Phase 1 only, for `reqdrive plan` |
| `pipeline_setup` | function | lib/run.sh:676 | config, slug, agent_dir, req-file resolution |
| `write_run_status` | function | lib/run.sh:24 | writes `run.json`; preserves `started_at`; `pr_url` JSON-escaped via `jq -Rn` |
| `save_checkpoint` / `load_checkpoint` | function | lib/run.sh:88 / :123 | 8-field checkpoint; resume warns (never fails) on HEAD/SHA divergence |
| `build_planning_prompt` | function | lib/run.sh:209 | quoted heredoc (`<<'PROMPT_PLAN'`, :213) |
| `build_implementation_prompt` | function | lib/run.sh:281 | quoted heredoc (:324) + ordered `@@TOKEN@@` substitution (:399-403); output pinned by `tests/fixtures/golden-impl-prompt.md` |
| `select_next_story` | function | lib/run.sh:413 | jq: highest-priority story with `passes != true` and `attempts < max` (:423-428) |
| `run_claude_iteration` | function | lib/run.sh:447 | one stateless `claude` process under `timeout 1800` (:465) |
| `run_review_phase` | function | lib/run.sh:510 | Phase 4; returns 0 on every path (:521,543,626,666) |
| `run_completion_hook` | function | lib/run.sh:484 | `bash -c` on the configured hook; exports `REQ_ID/STATUS/PR_URL/BRANCH/EXIT_CODE` |
| `extract_iteration_summary` | function | lib/run.sh:170 | lifts the fenced iteration-summary JSON out of agent output |

## Invariants

- Story selection is a pure jq function of `prd.json`; the agent is never asked which story is next. (lib/run.sh:423-428)
- Every Claude invocation is a fresh process — no `--continue`/`--resume`; cross-iteration context flows only through files. (lib/run.sh:447-478)
- Both prompt heredocs are quoted; PRD-derived values reach a prompt only via `sanitize_for_prompt` + token substitution. (lib/run.sh:213, 324, 299-321, 399-403)
- Planning failure (no `prd.json` after 2 attempts) hard-aborts with `EXIT_AGENT_ERROR` before any PR exists. (lib/run.sh:992-997)
- Phase 3 always writes `verification-summary.json` before PR creation. (lib/run.sh:1164 → create_pr at :1193)
- Phase 4 review always returns 0, so it can never abort the pipeline — and runs after the PR, so it can never change the draft flag. (lib/run.sh:1195, 666)
- Per-iteration `testCommand` and commit-format checks are observation-only: counters plus warnings, never abort, never retry. (lib/run.sh:1059-1082)
- The scope check is the loop's only hard gate, and only under `policy.scopeCheck: "block"`. (lib/run.sh:1088-1093, lib/policy.sh:82-87)
- `run.json.status` vocabulary is exactly `running|completed|failed|interrupted`. (lib/run.sh:874, 877-879, 994, 1196, 1200)
- All run state is confined to `.reqdrive/runs/<lowercased req-id>/`. (lib/run.sh:685, 691)

## Data flows

- **run**: bin/reqdrive:86 → lib/run.sh:855 → preflight lib/preflight.sh:165 → branch lib/run.sh:911 → plan lib/run.sh:962 → loop lib/run.sh:1019 → verify lib/verification.sh:85 → gate lib/run.sh:1177 → PR lib/pr-create.sh:78 → review lib/run.sh:1195
- **one iteration**: select lib/run.sh:1028 → prompt lib/run.sh:1043 → claude lib/run.sh:465 → summary lib/run.sh:170 → test lib/run.sh:1062 → commit check lib/run.sh:1077 → scope check lib/run.sh:1089 → attempts++ lib/run.sh:1096 → checkpoint lib/run.sh:1101

## Dependencies

Internal: `safety` (errors, sanitize, preflight — sourced :9-11), `evidence`
(policy sourced per-iteration at :1088; verification at :1131), `pr` (:1174),
`config` (the `REQDRIVE_*` env contract). External: `claude`, `jq`, `git`, `gh`
(via `pr`), coreutils `timeout`/`tee`/`seq`/`date -Iseconds`.

## Gotchas

- `create_pr`'s progress line is echoed to **stdout**, and `lib/run.sh:1193` captures that stdout as the PR URL — so `run.json.pr_url` is a two-line string. (lib/pr-create.sh:95) → [drift INT-030](../requirements/drift-report.md#INT-030)
- The agent can end Phase 2 early by printing `<promise>COMPLETE</promise>`; the shell greps for it and `break`s with no re-check of remaining stories. The live prompt never asks for it, so the signal is vestigial. (lib/run.sh:1112)
- `select_next_story` sorts by `.priority` with no default, and jq orders `null` before numbers — a story omitting `priority` sorts first. (lib/run.sh:426)
- `build_planning_prompt` appends sanitized content verbatim, so the **planning** prompt still contains `\$` escapes that the implementation path reverses. (lib/run.sh:276) → [drift](../requirements/drift-report.md#SANITIZE-PLANNING)
- An agent timeout or crash is warn-only; `run_claude_iteration` never propagates the failure, so the run can exit 0. (lib/run.sh:465-478)
- The INT/TERM/HUP traps write status `interrupted` but do **not** fire the completion hook. (lib/run.sh:877-879)
- `RUN_SUMMARY_*` accumulators are initialised to 0 *before* Phase 1, so a planning failure writes a zeroed summary where `null` is specified. (lib/run.sh:935 vs :53)
- `prompt.md` is overwritten every iteration and shared with `run_plan`, so post-run it reflects only the last one. (lib/run.sh:732, 1043)
- `run.json` is the only pipeline-written JSON artifact with no `version` field. (lib/run.sh:71-83)

## Requirement coverage

212 governing reqs: **200 satisfied · 6 drifted · 5 unimplemented (all Tier-3
roadmap) · 1 intent-met**. Canon (intended) behavior for the drifted ones:

| REQ | Status | Canon (intended) | Link |
|-----|--------|------------------|------|
| DES-002 | drifted | draft by default, cleared **only** on positive evidence | [drift-report](../requirements/drift-report.md#DES-002) |
| CLD-001 | drifted | the shell controls what to work on **and when to stop** | [drift-report](../requirements/drift-report.md#CLD-001) |
| INT-030 | drifted | `run.json.pr_url` is the GitHub PR URL | [drift-report](../requirements/drift-report.md#INT-030) |
| INT-048 | drifted | the hook's `PR_URL` is the PR URL, empty on failure | [drift-report](../requirements/drift-report.md#INT-030) |
| INT-015 | drifted | exit 5 means the Claude invocation failed (timeout, crash, no PRD) | [drift-report](../requirements/drift-report.md#INT-015) |
| INT-031 | drifted | `run.json.summary` is `null` when the pipeline never reached implementation | [drift-report](../requirements/drift-report.md#INT-031) |
| CLD-059 | drifted | keep the library at the simplified ~5-script shape | [drift-report](../requirements/drift-report.md#CLD-059) |
| CLD-092..097 | unimplemented | Tier-3 roadmap — expected, not a gap | index.json#unbuilt_features |

## Pointers

Draft gate and evidence math: [evidence.md](evidence.md). PR body:
[pr.md](pr.md). Prompt-safety rules: [../conventions/sanitization.md](../conventions/sanitization.md).
