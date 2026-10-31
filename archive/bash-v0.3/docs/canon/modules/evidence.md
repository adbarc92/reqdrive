# evidence (canon)

`lib/verification.sh`, `lib/policy.sh` — 98 governing requirements.

## Purpose

The pipeline's evidence layer: it counts stories, actually re-runs the test
suite, writes `verification-summary.json`, classifies changed paths into risk
tiers, and raises scope findings. Everything the draft decision and the PR's
verification table rest on is computed here.

## Public interface

| Symbol | Kind | Signature | Anchor | Notes |
|--------|------|-----------|--------|-------|
| `verify_collect` | function | `<prd_file> <max_retries>` | lib/verification.sh:56 | sets `VERIFY_STORIES_{TOTAL,COMPLETED,FAILED,REMAINING}`, `VERIFY_PRD_PRESENT` |
| `verify_run_tests` | function | `<agent_dir>` | lib/verification.sh:79 | **tri-state**: 0 passed, 1 failed, 2 no testCommand. Never collapse to a boolean |
| `verify_write_summary` | function | `<agent_dir> <req_id> <max_iters> <full\|merge>` | lib/verification.sh:98 | atomic write via `.tmp` + `mv` |
| `policy_tier_for_path` | function | `<path> → high\|medium\|low\|none` | lib/policy.sh:13 | literal path-prefix match |
| `policy_classify_paths` | function | `<path>…` | lib/policy.sh:35 | **dead code — no callers** |
| `policy_scope_check` | function | `<agent_dir> <iter> <tests_passed>` | lib/policy.sh:54 | returns 1 only in block mode |

## Invariants

- `verification_passed` is always one of the JSON literals `true`, `false`, `null` — never a quoted string. (lib/verification.sh:160)
- `remaining` is JSON `null` exactly when `prd_present` is false; otherwise an integer. (lib/verification.sh:107-112)
- A tier pattern matches only at a directory boundary: `path == pattern`, or `path` begins with `pattern/`. `src/auth` matches `src/auth/login.ts` but never `src/authorization/x.ts`. (lib/policy.sh:24, verified by execution)
- Tier precedence is the literal probe order `high, medium, low`, returning on first match. (lib/policy.sh:19-27, verified by execution)
- With no policy configured, `REQDRIVE_POLICY_JSON` is `{}`, every path classifies `none`, and no finding is possible. (lib/policy.sh:15)
- Warn mode never changes the pipeline's exit code; block mode's only escalation is returning 1, which the caller turns into exit 8. (lib/policy.sh:82-87 → lib/run.sh:1089-1093)
- `merge` mode never rewrites `iterations`/`tests`/`commits` from the accumulators — it reads them back from the existing file. (lib/verification.sh:116-125)
- The summary file is replaced atomically. (lib/verification.sh:135-164)

## Data flows

- **verification**: lib/run.sh:1131 → `verify_collect` lib/verification.sh:56 (reads prd.json) → `verify_run_tests` lib/verification.sh:85 (`eval "$REQDRIVE_TEST_COMMAND"`) → `verify_write_summary` lib/verification.sh:98 → draft gate lib/run.sh:1177 → PR table lib/pr-create.sh:168
- **scope check**: lib/run.sh:1088 (sourced per iteration) → `git diff --name-only HEAD~1 HEAD` lib/policy.sh:64 → `policy_tier_for_path` lib/policy.sh:71 → `scope-findings.txt` lib/policy.sh:79 → PR body lib/pr-create.sh:183-191

## Dependencies

Internal: `pipeline` (sole `full`-mode caller and owner of the `RUN_SUMMARY_*`
accumulators), `cli`'s `cmd_verify` (sole `merge`-mode caller, which defines its
own `log_info`/`log_warn` shims at bin/reqdrive:482-483), `config` (the
`REQDRIVE_TEST_COMMAND`/`REQDRIVE_POLICY_*` exports), `pr` (re-reads the
artifacts). External: `jq`, `git`, `date -Iseconds`, and the user's
`testCommand` executed via `eval`.

## Gotchas

- The final test suite genuinely executes — `eval "$REQDRIVE_TEST_COMMAND"` at lib/verification.sh:85 — but it runs in the **caller's CWD**, not the project root.
- Nothing here independently checks the agent's self-reported `passes: true`: `stories_completed` is a raw count of the agent's own claims. (lib/verification.sh:69)
- `git diff --name-only HEAD~1 HEAD` inspects the *last commit only*, not the iteration's full work — an agent making two commits hides the first from the scope check. (lib/policy.sh:64)
- A glob in config is silently inert: `riskTiers.high = ["src/auth/**"]` matches nothing, disabling the tier with no warning. Measured. (lib/policy.sh:24) → [drift](../requirements/drift-report.md#GLOB-FOOTGUN)
- Only the tier names `high`, `medium`, `low` are probed; a `critical` tier passes schema validation and is inert. (lib/policy.sh:19) → [drift](../requirements/drift-report.md#TIER-NAME-FOOTGUN)
- Only `high` ever produces a finding — `medium` and `low` are classification-only. (lib/policy.sh:72)
- When `testCommand` is unset, `verify_run_tests` returns 2 **without truncating** `verification.test.log`, so a stale log survives. (lib/verification.sh:92-95)
- `reqdrive verify req-01` (lowercase) rewrites the summary's `req_id` from `REQ-01` to `req-01`. (bin/reqdrive:561)
- `merge` mode does not validate the file it reads; a corrupt summary aborts `verify` with jq's status. (lib/verification.sh:120-125)

## Requirement coverage

98 governing reqs: **89 satisfied · 5 drifted · 2 intent-met · 2
not-code-verifiable**. Canon (intended) behavior for the drifted ones:

| REQ | Status | Canon (intended) | Link |
|-----|--------|------------------|------|
| DES-114 | drifted | post-iteration path classification is recorded | [drift-report](../requirements/drift-report.md#DES-114) |
| DES-116 | drifted | a scope finding is recorded in `checkpoint.json` | [drift-report](../requirements/drift-report.md#DES-116) |
| DES-131 | drifted | warn-mode findings reach the checkpoint as well as the PR | [drift-report](../requirements/drift-report.md#DES-116) |
| CLD-086 | drifted | *(register conflict)* CLAUDE.md:212 calls the scope check a hard gate; README/D6/code make it warn-by-default. The **code is right**, the doc is wrong | [drift-report](../requirements/drift-report.md#CLD-086) |
| RDM-077 | drifted | warn findings render under a `### Scope findings` heading | [drift-report](../requirements/drift-report.md#RDM-077) |

`INT-069` (PID liveness may be unreliable on MSYS2) is `not-code-verifiable` —
a runtime-platform property, excluded from drift and gap counts.

## Pointers

Draft gate consumer: [pipeline.md](pipeline.md). Rendering:
[pr.md](pr.md). Config keys: [config.md](config.md).
