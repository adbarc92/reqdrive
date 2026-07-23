# Design — Completing the reqdrive Roadmap

**Date:** 2026-07-23
**Status:** Passed three rounds of adversarial critique
**Scope:** reqdrive L2→L3 readiness gap + all remaining CLAUDE.md Tier 2 items. Tier 3 explicitly deferred.

---

## 1. Measured starting state

All values measured 2026-07-23 and re-verified after each critique round.

| Fact | Value | Source |
|---|---|---|
| Suite result on this machine | 157 passed, 0 failed, 0 skipped, exit 0 | `bash tests/simple-test.sh` |
| `test_result` / `test_skip` call sites | 157 / 2 | `grep -c` |
| **Unique test names** | **157** | the 2 `test_skip` calls reuse 2 `test_result` names |
| Existing spec stories | 60 | `grep -c '^### US-' tests/BEHAVIOR-SPEC.md` |
| `claude` on PATH here | yes | `command -v claude` |
| CI | shellcheck + `bash -n` + simple suite + bats suite | `.github/workflows/ci.yml` |

**Environment dependence.** The two `HAS_CLAUDE`-gated assertions (`tests/simple-test.sh:1260`, `:1787`) run as `test_result` here and as `test_skip` — under the *same name* — in CI. Result-line count is **157 in both environments**; only the verdicts differ.

### 1.1 Blocking finding: the harness cannot report a failure

`tests/simple-test.sh:11` sets `set -e`, and all 157 assertions are `( ... )` followed by `test_result "name" $?`. Under `errexit` a failing subshell terminates the script **before `test_result` runs**:

```
$ bash -c 'set -e; ( echo one; false; echo two ); echo rc=$?'
one                     # aborts; no rc line
```

So `test_result`'s FAIL branch (`:43`) is unreachable, `$FAIL` is always 0, the final `[ "$FAIL" -eq 0 ]` is vacuous, "0 failed" is guaranteed by construction, and **red-first TDD is impossible today**.

### 1.2 The obvious fix is also wrong

Bash ignores `errexit` inside a compound command used as an `if` condition, and **the suppression propagates into the subshell body — even if the body sets `set -e` explicitly.** Measured:

| Form | `errexit` active inside? |
|---|---|
| `if ( ... ); then rc=0; else rc=$?; fi` | **no** — prints past the failure, rc=0 |
| `if ( set -e; ... ); then ...` | **no** — explicit body `set -e` does not restore it |
| `( ... ) && rc=0 \|\| rc=$?` | **no** |
| `set +e` at top; subshell body **without** `set -e` | **no** |
| **`set +e` at top; `set -e` as the first statement of the body; invoked as a simple command** | **yes** — stops at the failure, rc=1 |

Only the last form works. The natural fix produces a suite reporting **157 passed / 0 failed against a `lib/` function that returns 1 and writes nothing**, because many assertions end in a pure negative that a broken setup satisfies trivially. Round 3 applied both forms and confirmed: correct form → 3 FAILs; broken form → 157/0.

### 1.3 Behavior-spec coverage is worse than the survey implied

60 stories cover 4 modules — but those modules contain **96 test names**, so ~36 assertions *inside the specced modules* have no 1:1 story.

| Module group | Test names | Stories today |
|---|---|---|
| errors / schema / sanitize / config | 96 | 60 |
| `run.sh`-adjacent | 30 | 0 |
| CLI (`bin/reqdrive`) | 13 | 0 |
| preflight / pr-create / init / review | 18 | 0 |
| **Total** | **157** | **60** |

P1's real output is **~97 new stories plus reconciliation of the existing 60**. It is the largest item in the plan and sits on the critical path.

### 1.4 Findings the existing docs do not record

1. **The L2 claim is real but incomplete.** `lib/run.sh:1106-1117` re-runs `testCommand` and derives `verification_passed` from the exit code — a genuine C3 check. `reqdrive-audit.md`'s "never verifies outputs" is **false**.

2. **The draft gate fail-opens three ways.** `lib/run.sh:1168-1173`:
   - **(A) `verification_passed: null`** — no `testCommand` (`:1116`); the gate tests only for the literal `"false"`.
   - **(B) missing `prd.json`** — `final_remaining` initializes to the sentinel `"?"` (`:1077`), overwritten only inside `if [ -f "$prd_file" ]` (`:1082-1092`). A run whose planning failed produces a **non-draft PR with no PRD**.
   - **(C) `passes` omitted** — `lib/schema.sh:138` guards with `has("passes")`, so the field is optional, and `select(.passes == false)` does not match `null`. Verified: 3 stories, 1 passing, 2 with no `passes` field → `remaining: 0` → **no draft**, while `lib/pr-create.sh:138-139` prints "1/3 completed."

3. **Prompt output is corrupted by unnecessary escaping.** `sanitize_for_prompt` (`lib/sanitize.sh:43`) rewrites `$` → `\$`; bash does not re-scan an expanded value for escapes, so the backslash reaches the prompt — including the commit message the agent is told to use (`lib/run.sh:320`).

4. **`ROADMAP.md` is stale** — the v0.2.0 simplification plan.

5. **`reqdrive validate` exits 1, not 3** (`lib/validate.sh:16,70`), and `reqdrive_load_config` never calls `validate_config_schema`.

6. **The suite can destroy the repo if `mktemp` fails.** `tests/simple-test.sh:56` is `TEST_TEMP=$(mktemp -d)` with no guard; `:743` runs `rm -rf .git` after `cd "$TEST_TEMP"`. Verified: **`cd ""` returns 0 and leaves you in the invocation directory** — the repo root. Today `set -e` at `:11` masks this by aborting on a failed `mktemp`; P0 removes that accidental protection, so P0 must add a real one.

7. **The bats e2e tests cannot fail.** `tests/e2e/pipeline.bats` has **6** `|| skip` escape hatches (`:146, :223, :253, :301, :302, :338`), including all three tests that assert on the prompt builders. Round 3 gutted `build_implementation_prompt` to write an empty file and return 0: bats reported `ok ... # skip` and **exited 0**. Any suite named as a safety net must be able to report failure.

---

## 2. Decisions (do not re-litigate)

| # | Decision | Rationale |
|---|---|---|
| D1 | Ladder first, then Tier 2 features. | TDD lock-in needs a baseline that exists. |
| D2 | **Draft gate becomes fail-closed**: draft by default, cleared only on positive evidence. | Closing only fail-open (A) leaves (B) and (C) open. Enumerating negatives is a losing game. |
| D3 | All of Tier 2; Tier 3 deferred with recorded reasons. | Separate products. DOCTRINE J5. |
| D4 | Approach A + scoped extraction. | No gratuitous `run.sh` refactoring; no duplicated verification logic (J3). |
| D5 | Policy lives as a `policy` key in `reqdrive.json`. | One file, one loader, one validator. |
| D6 | Scope check ships warn-only, `"scopeCheck": "warn"\|"block"`. | Resolves roadmap-vs-principle contradiction. |
| D7 | Freeze covers `tests/simple-test.sh`; bats must stay green **with zero skips in `tests/e2e/`**. | *(Revised, round 3.)* "Green" is meaningless for a suite with 6 `\|\| skip` hatches (§1.4.7). |
| D8 | Lock generated in the CI environment configuration. | The baseline must be reproducible where it is enforced. |
| D9 | The `\$` corruption is fixed in a separate enumerated step, not frozen. | Byte-identity across all of P6 would enshrine a live defect. |
| D10 | **The freeze is a whole-file hash of `tests/simple-test.sh` plus `tests/oracle-gate.sh`**, not a per-test body hash, and not base-ref execution. | *(Revised, round 3.)* A per-body hash misses `test_result` itself — round 3 emptied every `lib/*.sh`, patched `test_result` to always PASS, and every name-and-body rule stayed green. One file hash subsumes rename, body edit, reporter tampering and gate tampering, needs no git remote, and behaves identically locally and in CI. |
| D11 | **P0 is validated by mutation, including a *silent* mutant.** | Inversion cannot distinguish the correct fix from the broken one; a `return 1` mutant is caught at the call site by errexit and does not exercise the assertions. |
| D12 | **`EXIT_CONCURRENT_RUN=10`** is added rather than reusing `EXIT_GIT_ERROR`. | "Another reqdrive is running" is not a git failure, and a caller scripting on exit codes must distinguish it from a genuine branch mismatch. |

---

## 3. Architecture

| Artifact | Purpose |
|---|---|
| `tests/simple-test.sh` (harness fixed) | Failures reportable rather than fatal — P0. |
| `tests/lib/pipeline-harness.sh` (new) | Fake `claude`, fake `gh`, scratch git repo — P3. |
| `tests/BEHAVIOR-SPEC.md` (extended) | Stories for all 157 test names. |
| `tests/oracle.lock.json` | Frozen baseline: names, story IDs, file hashes. |
| `tests/oracle-gate.sh` | Enforces DOCTRINE B2/B3. |
| `lib/verification.sh` (extracted) | Verification phase, shared by `run` and `verify`. Named `verification.sh`, not `verify.sh`, to avoid confusion with `archive/v1-complex/lib/verify.sh`. |

### 3.1 The freeze mechanism

**Runtime data comes from an actual run; integrity comes from file hashes.** Names and verdicts are parsed from a real suite run — source and runtime text differ for **4** of 157 names (e.g. `tests/simple-test.sh:1167` reads `... neutralizes \$(cmd) ...` and renders as `... neutralizes $(cmd) ...`), so scraping source for names is wrong.

**Output parsing**, specified exactly — `test_result` emits `echo -e "${GREEN}PASS${NC}: $name"` (`:40`) unconditionally with no TTY check, and 157 of 157 names contain `": "`:

1. Strip ANSI: `sed 's/\x1b\[[0-9;]*m//g'`
2. Match `^(PASS|FAIL|SKIP): `
3. Split on the **first** `": "` only — never `cut -d:`
4. For SKIP, strip the trailing ` (reason)`
5. Tolerate interleaved non-result lines (`[SCHEMA] Warning: ...` appears between results)

**Lock schema:**

```json
{
  "version": "0.3.0",
  "generated": "2026-07-23",
  "environment": { "claude": false },
  "suiteSha256": "…",
  "gateSha256": "…",
  "tests": [
    { "name": "find_manifest: finds manifest in current dir", "story": "US-CFG-01" }
  ]
}
```

The expected result count **is** `len(tests)`; there is no separate field that can drift as later phases add tests.

**Gate rules, in strict precedence order:**

| Rule | Condition | Verdict |
|---|---|---|
| R7 | `suiteSha256` or `gateSha256` mismatch | `NEEDS_HUMAN` — the test file or the gate itself changed |
| R2 | A locked name reported `FAIL` | Baseline weakened |
| R3 | A locked name reported `SKIP` | Silent weakening — exempted where `conditional` is unmet |
| R6 | A result name is **absent from the lock** | `NEEDS_HUMAN` — a new test must be registered, so P4–P7's own tests are protected too |
| R1 | A locked name absent from output | Renamed or deleted (diagnostic: names *which* test vanished) |
| R0 | Result count < `len(tests)` **and no FAIL parsed** | `SUITE_TRUNCATED` |

Precedence matters: the suite's last command is `[ "$FAIL" -eq 0 ]`, so post-P0 any FAIL exits non-zero. Without precedence an exit-code-based R0 would re-label every R2 as truncation — re-conflating the two signals P0 exists to separate.

**Why one file hash rather than per-test hashes, append-only lock diffs, and base-ref execution** (D10): those three controls together still lose to a six-line edit of `test_result`, which sits outside every subshell and therefore outside every body hash. Round 3 demonstrated it: every `lib/*.sh` emptied, `test_result` patched to report PASS unconditionally, all 157 bodies byte-identical → gate fully green. `suiteSha256` covers the reporter, the bodies, the names and the trailer in one rule, requires no `fetch-depth: 0`, no base-ref checkout, no first-PR bootstrap exception, and behaves identically on a laptop with no remote. R1 is retained only as a diagnostic.

**Regeneration is an explicit human act.** `tests/oracle-gate.sh --accept` regenerates hashes and the name list. Any intentional test change is one command plus a reviewable diff; no test change can happen silently.

**`conditional` is a closed enum with one member: `claude`.** An unrecognized value is a hard error, never an exemption — otherwise `"conditional": "flaky"` is a one-word kill switch. The `posix-process` member is **not** created: on MSYS2, the primary platform, it would permanently exempt the `launch` lifecycle tests, and an always-exempt test is a deleted test with ceremony (see P5).

**Locked tests can go red from unrelated source changes.** P5's doc-coverage tests parse the live dispatch block, so adding `verify)` in P6b turns an already-locked test red. That is a legitimate red-first signal, not a malfunction — stated so nobody "fixes" it by weakening the coverage test.

### 3.2 Verification extraction contract

Real dependencies of the Phase 3 block (`lib/run.sh:1067-1157`):

| Needed | Where it lives today |
|---|---|
| `RUN_SUMMARY_ITERATIONS`, `_TESTS_*`, `_COMMITS_*` | globals accumulated in the implementation loop (`:1013-1037`), initialized `:893-902` |
| `max_iterations` | `run_pipeline` local (`:888`) — **interpolated into the summary JSON at `:1136`** |
| `final_remaining` | declared `:1077`, computed `:1085`, **consumed after the block** by the draft gate at `:1168` |
| working tree / branch | implicit — `eval "$REQDRIVE_TEST_COMMAND"` runs against whatever is checked out |

Contract:

- `verify_collect <prd_file> <max_retries>` — sets `VERIFY_STORIES_TOTAL/COMPLETED/FAILED/REMAINING` and `VERIFY_PRD_PRESENT` (`0|1`). The `"?"` sentinel is retired **from the shell variables**; absence of the PRD is carried by `VERIFY_PRD_PRESENT`.
- `verify_run_tests <agent_dir>` — returns **`0` pass / `1` fail / `2` not configured**.
- `verify_write_summary <agent_dir> <req_id> <max_iterations> <mode>` — `max_iterations` is an explicit parameter; it is a `run_pipeline` local, not a `RUN_SUMMARY_*`, and omitting it emits `"max": ` → malformed JSON that `lib/pr-create.sh:147` swallows into `"?"`. `mode` is `full` or `merge`.
- `cmd_verify` derives `prd_file` from the run directory; that derivation is part of the contract.

**The JSON artifact keeps its shape.** `lib/run.sh:1132` already emits `"remaining": null` for the missing-PRD case. That stays — retiring a union type in an internal variable is right, silently changing a documented artifact is not. A new `"prd_present": true|false` field is added, and P6b's characterization criterion reads "identical modulo `timestamp` and the new `prd_present` field."

**`cmd_verify` merges; it never blind-overwrites.** A standalone verify has no implementation loop, so `RUN_SUMMARY_*` are zero; a fresh write would zero `iterations`/`tests`/`commits` — the evidence trail `lib/pr-create.sh:138-148` renders into the PR table.

**Defined edge cases:**
- *No existing summary* (the summary is written only at `:1123`, so runs that die earlier have none): exit 3, naming the missing file. No synthesized summary — a zeroed one is indistinguishable from a real run that did nothing.
- *Concurrent writer*: `cmd_verify` reads the PID in `run.json` and refuses while alive, with **`EXIT_CONCURRENT_RUN=10`** (D12). CLAUDE.md already records "no file locking on run directories."
- *Non-atomic write*: summary writes go through temp-file + `mv`, replacing the bare `cat >` heredoc at `:1123`.
- *Wrong tree*: refuses unless the checkout matches `checkpoint.json`'s branch or `--ref <branch>` is given; `EXIT_GIT_ERROR` (4).

---

## 4. Phases, exit criteria, and honest effort

Each phase ends with `oracle-gate.sh` green **and** `bats tests/unit tests/e2e` green with zero skips in `tests/e2e/` (D7). A phase needing a locked test changed stops and asks — the B3 `NEEDS_HUMAN` path.

### P0 · Make the harness able to report failure — ~3h

**Exit criteria**
- `tests/simple-test.sh:11` becomes `set +e`; `set -e` is inserted as the first statement of each of the 157 subshell bodies (§1.2). The `test_result "name" $?` lines are untouched. `:346-354` already sets `set +e` inside its body, so the inserted line is a no-op there and the edit stays uniform.
- **`mktemp` is guarded** (§1.4.6) — `set +e` removes the accidental protection `set -e` was providing:
  ```bash
  TEST_TEMP=$(mktemp -d) || { echo "FATAL: mktemp failed" >&2; exit 1; }
  [ -n "$TEST_TEMP" ] && [ -d "$TEST_TEMP" ] || { echo "FATAL: bad TEST_TEMP" >&2; exit 1; }
  ```
  and `tests/simple-test.sh:743` becomes `rm -rf "$TEST_TEMP/.git"` rather than a bare `rm -rf .git` after a `cd` that can silently no-op.
- Unmodified tree: 157 passed / 0 failed / exit 0.
- **Mutation criteria (D11)**, all three required:
  1. `return 1` at the top of `build_implementation_prompt` (`lib/run.sh:279`) → exactly 3 FAILs, suite completes, exit 1. *(Under the broken `if ( ... )` form this yields 157/0 — which is what the criterion exists to catch.)*
  2. `return 1` at the top of `load_checkpoint` (`:121`) → ≥3 FAILs.
  3. **Silent mutant:** `: > "$1"; return 0` in `build_implementation_prompt` — total functional loss with a success status → **≥2 FAILs**. Measured today: only 1. Meeting this criterion requires strengthening at least one pure-negative assertion *before* the freeze, which is the point.
  4. Stubbing `mktemp` to fail → suite exits non-zero before any test runs.
- The two error-code test names (`errors: defines all exit codes (0-8)`, `errors: EXIT_MESSAGES covers all codes`) are renamed now, while the rename surface is declared zero, because P6b/D12 add codes 9 and 10 and the old names would become lies that only a `NEEDS_HUMAN` could later correct.
- Beyond that rename, no test name changes.

### P1 · Spec retrofit — ~1–2 days, critical path

**Exit criteria**
- A story for every one of the 157 unique names; IDs `US-<MODULE>-NN`. Expect **~97 new stories plus reconciliation of the existing 60** (§1.3).
- Generated mapping file shows name → story with zero unmapped names.
- Zero files under `bin/` or `lib/` modified.
- Findings register created, with a stated counting rule and an exact count of **pure-negative assertions** (assertions whose final statement is a negation or an emptiness check — 21 by round 3's count, which the register must reproduce or correct). Seeded entries: `tests/simple-test.sh:1186` and `:1206` are satisfied by an empty prompt file; `:1206` interpolates `$HOME` into an unanchored grep pattern; `build_implementation_prompt` writes blank fields when `jq` fails on malformed story JSON (`lib/run.sh:285-288`, no guard).

### P2 · Freeze gate — ~4h

**Exit criteria**
- `tests/oracle.lock.json` generated from a real run with `claude` unavailable: 157 names, each with a `story`, plus `suiteSha256` and `gateSha256`.
- `bash tests/oracle-gate.sh` exits 0 on an unmodified tree, both with and without `claude` on PATH.
- Demonstrated individually: making one test fail → **R2, not mass-R1**; truncating the run → R0; **patching `test_result` to report PASS unconditionally → R7**; editing any test body → R7; adding an unregistered test → R6.
- `--accept` regenerates hashes and names, and is the only way to change them.
- `conditional` accepts only `claude`; any other value hard-fails.
- `oracle-gate` job added to `.github/workflows/ci.yml`, and `tests/oracle-gate.sh` added to the explicit shellcheck file list at `.github/workflows/ci.yml:29`.

### P3 · Pipeline test harness — ~1–2 days

Nothing invokes `run_pipeline` today (`grep -n 'run_pipeline' tests/simple-test.sh` → nothing). P4 and P6b both need one.

**Exit criteria**
- `tests/lib/pipeline-harness.sh` provides a scratch git repo with base branch and requirement file; a fake `claude` emitting a schema-valid `prd.json`, per-iteration `json:iteration-summary` blocks, and the completion signal; a fake `gh` recording invocation arguments.
- **The harness sets `set -euo pipefail` before sourcing `lib/run.sh`.** `lib/run.sh:6` sets only bare `set -e`, but `run_claude_iteration` detects agent failure via `if timeout 1800 claude ... | tee ...` — a pipeline whose status is `tee`'s unless `pipefail` is on. Without this the harness validates a path that can never fail.
- Handles that `run_pipeline` terminates with `exit` (`lib/run.sh:1186`, `:1189`) rather than returning.
- **The 6 `|| skip` hatches in `tests/e2e/pipeline.bats` (`:146, :223, :253, :301, :302, :338`) are converted to hard assertions.** They exist because the real `claude` is unavailable; the deterministic fake removes the reason. Until this lands, "bats green" means nothing (§1.4.7).
- `timeout` (coreutils) added to README prerequisites — a hard runtime dependency of `run_claude_iteration`, currently undocumented.
- One end-to-end assertion: a scripted run reaches PR creation and the fake `gh` records a `pr create` invocation.
- Deterministic: no wall-clock dependence.

### P4 · Close all three draft-gate fail-opens (red-first) — ~4h given P3

**Exit criteria**
- The gate at `lib/run.sh:1168-1173` is **inverted to fail-closed**: `--draft` is the default, cleared only when `VERIFY_STORIES_REMAINING` is 0 **and** `VERIFY_PRD_PRESENT` is 1 **and** `verify_run_tests` returned 0.
- Red-first assertion per fail-open, each observed failing first: (A) no `testCommand` → draft; (B) no `prd.json` → draft; (C) a story with `passes` omitted → draft.
- Positive control: `testCommand` passing, PRD present, all stories `passes: true` → **no** `--draft`.
- `select(.passes == false)` becomes `select(.passes != true)`, or `passes` becomes required in `validate_prd_schema` — whichever is chosen is asserted.
- **The consequence is stated and surfaced.** `testCommand` defaults to `""`, so on a default-configured project *every* PR is now a draft. That is the intended policy, but it must not be a mystery: a preflight warning at run start reads *"no `testCommand` configured — all PRs will be created as drafts"*, and the tri-state is used rather than wasted — `verify_run_tests` returning 2 produces a **distinct reason line in the PR body** ("no test command configured") separate from 1 ("tests failed").
- `verification-summary.json` still records `verification_passed: null` when no test command ran.
- The 5 existing *Run Summary & Verification* assertions stay green.

### P5 · L3 documentation, enforced by coverage tests — ~1–2 days

**Exit criteria**
- Three `doc-coverage` rules in `simple-test.sh`, each written first and observed failing:
  1. **Commands** — parsed from `bin/reqdrive:538-582` (`case`…`esac`), leading whitespace trimmed, keeping labels matching `^[a-z][a-z-]*)$` (excludes `-v|--version)`, `-h|--help|"")`, `*)`). 9 labels exist; `README.md:45-55` documents 7. **Fails on `plan` and `orchestrate`.**
  2. **Config fields** — each `REQDRIVE_*` set by `lib/config.sh` must have its JSON field in README, minus `DOC_EXEMPT` = {`REQDRIVE_MANIFEST`, `REQDRIVE_PROJECT_ROOT`} (derived paths, not config fields), each with a justifying comment. 12 exported, 8 documented. **Fails on `maxStoryRetries` and `reviewCommand`.**
  3. **Flags** — parsed from **case labels** in the option blocks (`bin/reqdrive:95-126`, `:400-422`) matching `^\s*(-[a-z]\|)?--[a-z-]+\)`, split on `|`. Parsing free `--[a-z-]+` literals instead would false-positive on `--help` inside the error string at `:114`. README's Run Options table (`:59-64`) documents `--interactive`, `--unsafe`, `--force`, `--resume`. **Fails on `--dangerously-skip-permissions`**, which is a real accepted flag (`:100`, `:401`) — resolved either by documenting it as a `--unsafe` alias or by a `DOC_EXEMPT` entry with a justifying comment.
- README updated until all three pass.
- `reqdrive-audit.md` → `docs/audits/2026-02-16-pipeline-audit.md` with a dated preamble retracting the "never verifies outputs" claim, citing `lib/run.sh:1106-1117`.
- `docs/LAUNCH-TEST-PLAN.md` cases 2, 5, 7, 8 automated against the P3 harness via `run.json` state transitions. Cases **1, 4, 6** (detached launch, duplicate-launch block, crash detection) depend on real background processes and PID liveness, unreliable under MSYS2: they run in a **Linux-only CI job**, not via a `conditional` exemption, because an always-exempt test on the primary platform is a deleted test with ceremony. §8 records that `launch` lifecycle coverage is CI-only.
- Case 3 (`logs`) asserts process behavior, not interactivity.
- New tests registered in the lock via `--accept` (required by R6).

### P6 · Tier 2 mechanical — ~2 days

**P6a — heredoc structural fix, three explicit steps**

*Step 1 — characterize.* Golden file capturing current `build_implementation_prompt` output for fixed fixtures, committed and passing **before** any change. Fixtures include values containing `&`, `\`, `` ` ``, `$`, and the literal `@@STORY_ID@@`. **The golden file is the sole named oracle for this phase** — the bats e2e tests are a secondary check and only after P3 removes their skip hatches.

*Step 2 — mechanical rewrite, byte-identical.*
- `<<'PROMPT_IMPL'` replaces `<<PROMPT_IMPL` at `lib/run.sh:298`.
- **All 24 escaped backticks in the body must be de-escaped** — measured: 24 backtick characters between `:298` and `:363`, all backslash-escaped, zero bare, at `:315, :316, :320, :321, :322, :327, :333, :340, :346, :356` (the three fence lines carry 3 each). A quoted heredoc performs no escape processing, so leaving them emits literal backslashes. Hand-edit, not a delimiter flip.
- Replacements are **quoted**: `${tpl//@@TOKEN@@/"$val"}`. Unquoted, bash ≥5.2's `patsub_replacement` (verified `on` by default here) expands `&` in the replacement to the matched text, so a title containing `&` injects a live `@@STORY_TITLE@@` into the prompt.
- **`shopt -u patsub_replacement 2>/dev/null || true`** — the `|| true` is mandatory. `patsub_replacement` does not exist before bash 5.2, `shopt -u` on an unknown option returns 1, `2>/dev/null` hides the message but not the status, and `lib/run.sh:6` sets `set -e`. Verified: without `|| true` the pipeline aborts on exactly the bash 4.x/5.0/5.1 versions the control exists to protect. An assertion exercises the unknown-option path.
- Injected values have `@@`-delimited tokens stripped; assertion: a title containing `@@STORY_ID@@` produces no substitution.
- Golden file matches **byte-identical**.

*Step 3 — correct the escaping defect (D9), enumerated.* Un-escape `\$` at injection time, since a file never re-evaluated by a shell needs no shell escaping. `lib/sanitize.sh` is **not** modified — its backtick neutralization is load-bearing for `tests/simple-test.sh:1186` and it has other callers. The golden file is updated in its own commit with one enumerated line per changed byte-range, plus a positive assertion that a `$`-containing title appears verbatim.

**P6b — verification extraction + `reqdrive verify <REQ-ID>`**

**Exit criteria**
- `lib/verification.sh` implements §3.2; `run_pipeline` calls it; the draft gate consumes `VERIFY_STORIES_REMAINING` + `VERIFY_PRD_PRESENT`.
- Characterization test: `verification-summary.json` from a P3-harness run identical before and after extraction, modulo `timestamp` **and the new `prd_present` field**.
- Assertion that the summary is **valid JSON when produced by `cmd_verify`** — the `max_iterations` parameter regression guard.
- `EXIT_VERIFICATION_FAILED=9` and `EXIT_CONCURRENT_RUN=10` added to `lib/errors.sh` with `EXIT_MESSAGES` entries.
- `reqdrive verify REQ-ID` runs in merge mode; exits 0 pass / 9 fail.
- Assertion: running `verify` after a completed run leaves `iterations.run` and the `tests`/`commits` counts unchanged (data-loss guard).
- Exits 3 when no summary exists; 4 on branch mismatch without `--ref`; 10 while `run.json`'s PID is alive.
- Summary writes are temp-file + `mv`.
- `verify` and `--ref` appear in README — enforced by P5 rules 1 and 3.

### P7 · Tier 2 policy cluster — ~2 days

**Exit criteria**
- `reqdrive.json` accepts `policy`; `lib/schema.sh` validates it:
  ```json
  { "policy": {
      "riskTiers": { "high": ["src/auth"], "medium": ["src/api"], "low": ["docs"] },
      "scopeCheck": "warn" } }
  ```
- **Matcher semantics specified**, because `**` is not meaningful here: in `[[ ]]` pattern matching `globstar` does not apply, so `src/api/**` and `src/api/*` both match `src/api/a/b.ts`, and `src/auth/**` does **not** match `src/auth` itself. Patterns use **prefix-directory** semantics — a path matches when `path == pattern` or `path == pattern/*` — and the config example uses bare prefixes, not `**`, so it stops implying recursion bash will not deliver.
- Matcher tested for: exact file match, nested descendant, the tier directory itself (`src/auth`), a sibling that shares the prefix (`src/auth.sh` must **not** match `src/auth`), no match, and a path matching two tiers (highest wins).
- `scopeCheck` accepts only `"warn"` or `"block"`.
- **Validation exit codes aligned first**, as its own red-first sub-item: `lib/validate.sh:16,70` change from bare `exit 1` to `EXIT_CONFIG_ERROR` (3), with an assertion pinning the code. The existing assertion at `:346-356` checks only `-ne 0` — recorded as a weak-assertion finding in P1.
- **`reqdrive_load_config` is not changed to schema-validate.** Doing so would newly reject configs that work today and put `US-CFG-04/05` and every minimal fixture at risk. Recorded as deferred with that reason.
- Absent `policy`: pipeline behavior byte-identical to P6 — proven by the baseline staying green.
- After each iteration, `git diff --name-only` paths are classified and recorded in the checkpoint and PR body.
- `"warn"` (default): a high-risk path touched without a passing `testCommand` run logs a warning; exit code unchanged.
- `"block"`: the same condition aborts the iteration with `EXIT_PREFLIGHT_FAILED` (8).

### P8 · Close out — ~4h

- `ROADMAP.md` gets a "Superseded — see CLAUDE.md" header; content preserved as history.
- CLAUDE.md Tier 2 checked; each Tier 3 item annotated with a deferral reason in the Decision Log.
- `docs/STATUS.md` created (it does not exist today) per the global convention.
- WORKFLOW.md §9/§10 reqdrive row corrected (§8 below).
- **P1's findings register is triaged**: each weak assertion is either strengthened, or recorded with an explicit accepted-risk note and a count. L1 PASS means "the oracle can report failure," not "every assertion is adequate" — §8 states this.
- Full suite green, gate green, bats green with zero e2e skips, CI green.

**Total: ≈9–12 working days.** P1, P3, P5 and P7 are the multi-day items.

---

## 5. Testing discipline

| Change type | Discipline | Artifact |
|---|---|---|
| New behavior (P4, P6b command, P7) | Red-first: write it, **observe it fail** (possible only after P0), then implement | Test + story + lock entry via `--accept` (R6 requires it) |
| Refactor (P6a step 2, P6b extraction) | Characterization: lock current output, require it unchanged | Golden file + baselines green |
| Deliberate correction (P6a step 3) | Characterize, then change in a separate enumerated commit | Updated golden + positive assertion |
| Harness change (P0) | **Mutation**, including a silent mutant | ≥3 FAILs from `return 1`; ≥2 from a silent no-op |
| Documentation (P5) | Coverage test red before any doc is written | 3 doc-coverage rules |

Red-green is the wrong tool for a refactor; assertion-inversion is the wrong tool for a harness change; and a `return 1` mutant is the wrong tool for proving assertion quality. Naming which oracle proves what is part of the discipline.

---

## 6. Error handling

| Condition | Exit code | Behavior |
|---|---|---|
| Final verification failed | `9` `EXIT_VERIFICATION_FAILED` (new) | `verify` exits 9; within `run`, forces draft |
| `verify` while the run's PID is alive | `10` `EXIT_CONCURRENT_RUN` (new) | Refuses; no concurrent writer |
| `verify` branch mismatch, no `--ref` | `4` `EXIT_GIT_ERROR` | Refuses rather than verifying the wrong tree |
| `verify` on unknown REQ-ID or missing summary | `3` `EXIT_CONFIG_ERROR` | Names the missing path |
| Scope violation, `scopeCheck: "block"` | `8` `EXIT_PREFLIGHT_FAILED` | Iteration aborts; checkpoint records it |
| Scope violation, `scopeCheck: "warn"` | `0` | Warning to checkpoint and PR body; never fatal |
| Malformed `policy` via `reqdrive validate` | `3` `EXIT_CONFIG_ERROR` | Requires the P7 exit-code alignment |

Config **load** performs no schema validation today, and this design does not change that (P7).

---

## 7. Out of scope

**Tier 3, deferred** (reasons recorded at P8): vision-based QA (Playwright + binary data — a separate Node/Python product); worktree orchestration (own design cycle); PR-rejection feedback (no failure data yet); CI polling (new failure mode, own spec); cost tracking (the `claude` CLI does not surface per-invocation tokens to the shell); adaptive retries (needs data that does not exist).

**Also out of scope:** decomposition of `lib/run.sh` beyond §3.2; modification of `lib/sanitize.sh`; wiring `validate_config_schema` into `reqdrive_load_config`; making the review agent a genuine writer≠grader (§8).

---

## 8. Ladder position

| Rung | Before | After | Evidence |
|---|---|---|---|
| L0 Specified | PARTIAL — 60 stories for 96 names in 4 of 10 modules | **PASS** | Story for all 157 names |
| L1 Correct | **FAIL** — the suite structurally cannot report a failure (§1.1) | **PASS** | Failures reportable (P0, mutation-proven incl. a silent mutant) + `suiteSha256`/`gateSha256` frozen (D10) |
| L2 Trustworthy | **FAIL** — three independent draft-gate fail-opens (§1.4.2) | **PASS** | Fail-closed draft gate, all three closed with a red-first test each |
| L3 Agent-operable | FAIL — undocumented commands, config fields, and flags | **PASS** | Three doc-coverage rules enforce documentation on every future change |
| L4 Shippable | Not targeted | Not targeted | reqdrive is a harness, not a shipped product |

**L1 PASS means the oracle can report failure — not that every assertion is strong.** ~21 of 157 assertions end in a pure negative and cannot detect setup failure. P0's silent-mutant criterion forces at least one to be strengthened before the freeze; P8 triages the rest with an explicit accepted-risk count. Claiming otherwise would repeat the mistake this design exists to fix.

**`launch` lifecycle coverage is CI-only** (P5): cases 1, 4 and 6 run in a Linux job because PID liveness and signal trapping are unreliable under MSYS2.

**Correction to WORKFLOW.md §9/§10.** That survey records reqdrive as **L2, gap docs-only**, based on the real `testCommand` re-run at `lib/run.sh:1106-1117`. That check is genuine, but two rungs beneath it are red: L1's oracle cannot report a failure (§1.1), and L2's draft gate fail-opens three ways (§1.4.2) — of which the survey found one. reqdrive's true starting rung is **L0**, and the gap is not docs-only. Both the §10 row and the §9 worked example should be corrected at P8.

**The `writer≠grader` claim is withdrawn from the L2 evidence column.** `run_review_phase` is invoked with the same `$model` as the implementer (`lib/run.sh:1178`), returns immediately when `reviewCommand` is empty — the default — and runs *after* `create_pr` (`:1176`), so its findings cannot influence the draft decision. Same model, off by default, post-hoc. Making it real needs a distinct `reviewModel` and a pre-PR position; out of scope here.

---

## Design Critique Log

Three independent adversarial rounds (DOCTRINE D4). 38 findings total. Every load-bearing finding was re-verified first-hand against the code before revision — several subagent claims were checked and confirmed, and one round-2 table row was found mislabeled and corrected.

### Critique Round 1 — 14 findings + 2 minor

| # | Finding | Resolution |
|---|---|---|
| 1 | **`set -e` makes the FAIL branch unreachable** — a failing test truncates the suite; R2 would be dead code, "0 failed" vacuous, red-first impossible. | New **P0** prerequisite; rule R0; §1.1; L1 corrected to start **FAIL**. |
| 2 | Conditional exemption applied to R1, but the else-branch emits the same name via `test_skip`, so **R3** fires and CI reddens on run one. | Exemption moved to R3; gate evaluates conditions itself. |
| 3 | `${tpl//@@T@@/$val}` broken by bash 5.2 `patsub_replacement` — `&` injects a live placeholder. | Replacement quoted; `shopt -u`; `&`/`\`/`` ` `` fixtures required. |
| 4 | "Byte-identical" was false and would have **frozen a live defect** (`\$` reaching the agent's commit message). | P6a split into characterize → rewrite → enumerated correction (D9); §1.4.3. |
| 5 | Verification extraction is not three clean functions; `cmd_verify` as specified **destroys** the evidence trail the PR body reads. | §3.2 rewritten: dependency table, tri-state, named globals, merge mode, branch-match + `--ref`. Renamed `lib/verification.sh`. |
| 6 | P2's assertions needed a pipeline harness introduced a phase later; nothing invokes `run_pipeline`. | New **P3** builds it first. |
| 7 | §1 numbers wrong: 157 unique names not 159; 60 stories not 62; `claude` is present locally. | §1 re-measured; D8 pins generation to the CI configuration. |
| 8 | §6 contradicted the code — `validate.sh` exits 1; config load never schema-validates. | P7 exit-code alignment as a red-first sub-item; config-load claim withdrawn. |
| 9 | Doc-coverage criteria not binary; README omits `plan` too; derived vars would fire forever. | P5 label regex, `DOC_EXEMPT`, corrected range and prediction. |
| 10 | bats declared out of scope, but CI gates on it and `pipeline.bats:282` asserts on the function P6a rewrites. | D7 revised: not frozen, must stay green. *(Round 3 tightened this further.)* |
| 11 | "3 injection assertions stay green" is a non-criterion — two are pure negatives an empty file satisfies. | Golden file becomes the positive oracle; weakness logged in P1. |
| 12 | P5 automates process-liveness tests CLAUDE.md calls unreliable, then forbids SKIP via R3. | *(Round 3 replaced this with a Linux-only CI job.)* |
| 13 | `writer≠grader` cited as L2 evidence is false: same model, off by default, post-PR. | Claim **withdrawn**. |
| 14 | Name-parsing hazards: ANSI codes, `": "` inside all names, source-vs-runtime text, SKIP suffix, interleaved warnings. | §3.1 specifies the parser step-by-step. |
| minor | `build_implementation_prompt` writes blank fields when `jq` fails. | P1 findings register. |
| minor | `oracle-gate.sh` would not be linted. | P2 exit criteria. |

### Critique Round 2 — 12 findings

| # | Finding | Resolution |
|---|---|---|
| 1 | **The P0 fix does not work and is worse than the status quo.** Bash suppresses `errexit` inside a subshell used as an `if` condition, and the suppression propagates into the body even with an explicit `set -e`. Applied as written, a `lib/` function returning 1 yields **157 passed / 0 failed**. Verified across five forms. | §1.2 added with the measured table. P0 respecified: `set +e` at top + `set -e` first in each body. **D11**: validate by mutation, not inversion. |
| 2 | **The freeze is not tamper-evident** — a name-only lock is satisfied by replacing every body with `true`; the gate polices itself; free-form `conditional` is a kill switch. | D10 (body hashes), R4, R5, base-ref execution, closed enum. *(Round 3 replaced the first four with a whole-file hash.)* |
| 3 | R0's exit-code clause swallows R2 — post-P0 any FAIL exits non-zero, so weakening would report as truncation. `expectedResultLines` would go stale. | Explicit precedence; R0 fires only when short *and* no FAIL; the count is `len(tests)`. |
| 4 | **The draft gate fail-opens three ways, not one** — missing `prd.json` and omitted `passes` are both worse than the `null` case. Verified. | **D2 revised** to fail-closed; P4 expands to a red-first test per fail-open plus a positive control; L2 corrected to start **FAIL**. |
| 5 | `verify_write_summary` as specified emits **malformed JSON** — `max_iterations` is a `run_pipeline` local with no parameter for it. | Explicit parameter; `prd_file` derivation added; valid-JSON assertion in P6b. |
| 6 | Merge mode had an undefined first-run case, a concurrent-writer race with detached `launch`, and a non-atomic `cat >`. | All three defined in §3.2. |
| 7 | "`--ref` enforced automatically by P5" is **false** — P5 checked only commands and config vars. | Third doc-coverage rule for flags. |
| 8 | P7's glob criteria are vacuous — `**` and `*` are indistinguishable in `[[ ]]` and `src/auth/**` never matches `src/auth`. | Prefix-directory semantics specified; test cases include `src/auth` and the `src/auth.sh` sibling. |
| 9 | P1 understated ~50% — 36 assertions inside the "specced" modules have no story; the plan is ≈8–11 days. | §1.3 rewritten; per-phase effort estimates added. |
| 10 | Factual errors: **24** escaped backticks not ~14; `:1186` not `:1176`; `final_remaining` computed at `:1085`. | All corrected and re-measured first-hand. |
| 11 | P3 harness fidelity: `lib/run.sh` sets bare `set -e`, so a sourced harness lacks `pipefail` — and failure is detected through a `claude \| tee` pipeline. `run_pipeline` ends in `exit`. `timeout` undocumented. | All three added as P3 exit criteria. |
| 12 | Lock edits had no append-only rule; locked doc-coverage tests will redden from unrelated edits. | R4 added *(later superseded)*; §3.1 states the cross-file reddening explicitly. |

### Critique Round 3 — 15 findings

Round 3 first **empirically confirmed the round-2 P0 fix**: applied to a copy it yields 157/0 clean; `return 1` in `build_implementation_prompt` produces exactly 3 FAILs; the broken `if ( ... )` variant produces 157/0 under the same mutant — so D11 genuinely discriminates. It also confirmed R5 extraction was mechanically feasible and that round 2's line-number corrections all hold. Then:

| # | Finding | Resolution |
|---|---|---|
| 1 | **P0's `set +e` removes the only guard on `mktemp`, and the suite then runs `rm -rf .git` in the repo root.** `cd ""` returns 0 and stays in the invocation directory — verified — and the test at `:743` passes while destroying the repository. | §1.4.6 added; P0 gains an explicit `mktemp` guard, a `[ -n ]`/`[ -d ]` check, `rm -rf "$TEST_TEMP/.git"`, and a fourth mutation criterion. |
| 2 | **The freeze is defeated by a six-line edit to `test_result`**, which sits outside every subshell and therefore outside every body hash. Demonstrated: all `lib/*.sh` emptied + reporter patched → 157/0, every rule green. | **D10 rewritten**: whole-file `suiteSha256` + `gateSha256` (rule R7). |
| 3 | **The three bats tests named as P6a's safety net cannot fail** — all end in `\|\| skip`; 6 hatches in `pipeline.bats`. Gutting the prompt builder produced `ok ... # skip` and exit 0. | §1.4.7 added; **D7 revised** to require zero e2e skips; P3 converts all 6 hatches to hard assertions; the golden file becomes P6a's sole named oracle. |
| 4 | **`shopt -u patsub_replacement 2>/dev/null` aborts the pipeline on bash < 5.2** — unknown option returns 1, `2>/dev/null` hides the message not the status, and `lib/run.sh:6` sets `set -e`. Verified. | `\|\| true` made mandatory, with an assertion exercising the unknown-option path. |
| 5 | R4 forbade removing entries but permitted rewriting them — updating a `bodySha256` in the same commit passed both R4 and R5. | Moot: R4/R5 removed in favor of R7 (finding 2). |
| 6 | §3.1's "generate from a run, never source" was incompatible with body hashes, and 4 of 157 names differ between source and runtime. | Moot under R7; §3.1 now states runtime data comes from the run and integrity from file hashes, and records the 4-name discrepancy. |
| 7 | **No rule fired on a test present in output but absent from the lock** — so every test P4–P7 writes was unprotected. | **R6** added; the contradictory P2 bullet deleted; lock registration named in each later phase. |
| 8 | Fail-closed + the default empty `testCommand` makes a non-draft PR unreachable, and the tri-state was introduced then ignored. | P4 states the consequence, adds a preflight warning, and uses the tri-state for a distinct PR-body reason line. |
| 9 | R4 could not run in CI — bare `actions/checkout@v4` is depth-1, `origin/main` unresolvable; plus bootstrap and local-run gaps. | Moot under R7, which needs no git remote and behaves identically locally and in CI. |
| 10 | Retiring the `"?"` sentinel silently changed the `verification-summary.json` contract and contradicted P6b's own characterization criterion. | The artifact keeps `"remaining": null`; a `prd_present` field is added; P6b's criterion restated. |
| 11 | Exit 4 for a live-PID refusal is wrong — "another reqdrive is running" is not a git failure. Also the two error-code test *names* become lies once codes 9/10 exist. | **D12**: `EXIT_CONCURRENT_RUN=10`. The two test names are renamed in P0, while the rename surface is declared zero. |
| 12 | P5 rule 3's parse spec was loose and its implied prediction wrong — it false-positives on `--help` inside a string at `:114` and really fails on `--dangerously-skip-permissions`. | Rule 3 now parses case labels, splits on `\|`, gains a `DOC_EXEMPT`, and states the true predicted failure. |
| 13 | D11's mutants are the easy ones — `return 1` is caught at the call site. A *silent* mutant produced only 1 FAIL of 3, and the weak assertions are then frozen forever with no phase repairing them. | Third **silent-mutant** criterion added to P0 (≥2 FAILs); P1's register gains a stated counting rule; P8 triages it; §8 states L1 PASS means "reportable," not "adequate." |
| 14 | Minor factual corrections: `max_iterations` at `:1136`; the heredoc at `:1123`; the PRD block `:1082-1092`; §1.3 sub-buckets 96/13/30/18; and **§1.2's row 4 was mislabeled** — `set +e` + body `set -e` does work. | All corrected; §1.2 row 4 relabeled "body **without** `set -e`". |
| 15 | **YAGNI:** cut base-ref execution + R4 (they cost a lot and do not hold, per finding 2), and cut the `posix-process` conditional (on MSYS2 it permanently exempts the entire `launch` lifecycle — a deleted test with ceremony). | Both cut. R7 replaces the former; a Linux-only CI job replaces the latter, with §8 recording that `launch` coverage is CI-only. |
