# Drift Report (canon vs. as-built)

Requirements are canon; each entry is a place the code contradicts them — a
suspected bug or debt, **not** intended behavior. Canon documented these; it
changed no code.

**48 confirmed drifted requirements + 8 confirmed defects that no requirement
covers.** 2 candidate findings were refuted in verification and 1 was materially
corrected; all three are recorded at the bottom so they are not re-raised. Every
entry below carries a Phase-3 adversarial verifier verdict.

> Only `drifted` reqs appear here. `intent-met` (21) and `not-code-verifiable`
> (10) live in [register.md](register.md). All 6 unimplemented reqs are Tier-3
> roadmap and are **not** gaps.

## Summary — fix list, most severe first

| # | REQ / Finding | Sev | Module | One-line |
|---|---------------|-----|--------|----------|
| 1 | **DES-002** | **critical** | pipeline | the fail-closed draft gate is fail-**open** four ways; non-draft PRs reproduced with real incomplete work |
| 2 | INT-030 · INT-048 · US-PR-01 | high | pr | `run.json.pr_url` and the hook's `PR_URL` hold a two-line string, not a URL |
| 3 | PR-OVERSTATES-COMPLETION | high | pr | the PR body states "Stories completed: <all>" with no `.passes` filter, contradicting its own table |
| 4 | GLOB-FOOTGUN | high | evidence | a glob in `riskTiers` silently matches nothing — the protection is inert, and `validate` says PASSED |
| 5 | RDM-008 · INT-006 · INT-007 | high | ci-and-install | `gh`/`claude` auth is never checked; failure surfaces after a full agent cycle |
| 6 | INT-013 | high | safety | a bad `reqdrive.json` exits 1 (or 5), never the documented 3 |
| 7 | INT-014 | high | safety | exit 4 is unreachable from `run`; a failed checkout leaks raw 128 |
| 8 | INT-015 | high | safety | a Claude timeout or crash exits **0** |
| 9 | CLD-006 · CLD-108 · RDM-070 | medium | safety | three docs promise path-traversal scanning that does not exist |
| 10 | SANITIZE-PLANNING · SANITIZE-PR-BODY | medium | safety | `$`→`\$` escaping corrupts the planning prompt and the published PR body |
| 11 | RDM-012 · CLD-030 | medium | config | `reqdrive init` writes unescaped JSON; a quote breaks the file and init reports success |
| 12 | VALIDATE-FALSE-PASS | medium | config | `validate` passes a config `run` refuses |
| 13 | ATTEMPTS-UNVALIDATED | medium | config | a non-numeric `attempts` makes a story permanently unselectable |
| 14 | CLD-086 | medium | evidence | CLAUDE.md and STATUS.md call the scope check a hard gate; it is warn-by-default |
| 15 | CLD-110 | medium | safety | content-scan strict mode and its `--force` bypass are both dead code |
| 16 | US-REV-05 · RDM-077 | medium | pr | two PR sections lose their newlines; the review table never renders as a table |
| 17 | DES-116 · DES-131 · DES-114 | medium | evidence | scope findings never reach `checkpoint.json`; `policy_classify_paths` is dead |
| 18 | TIER-NAME-FOOTGUN | medium | evidence | an unrecognised tier name validates clean and is inert |
| 19 | INT-005 | medium | safety | preflight never checks HEAD is `baseBranch`; a mis-based existing branch is adopted silently |
| 20 | RDM-005 · RDM-009 · RDM-010 · CLD-058 · CLD-106 | medium | ci-and-install | the documented prerequisite set is neither accurate nor enforced |
| 21 | CLD-059 | medium | pipeline | "17 scripts to 5" — `lib/` is 11 files / 2,683 lines, larger than the 1,770 it replaced |
| 22 | DES-008 · DES-060 | medium | test-harness | the oracle lock was generated where it is not enforced |
| 23 | DES-059 · DES-121 | medium | test-harness | the pure-negative count is 24, not the 18 in FINDINGS.md and STATUS.md |
| 24 | DES-101 · DES-072 | medium | test-harness | the characterization test pins presence, not values; the `prd_present==0` branch is untested |
| 25 | CLD-001 | medium | pipeline | "the agent never decides what to work on next" overstates a real but narrower guarantee |
| 26 | CLD-099 · ARCHIVE-ROT | medium | ci-and-install | `scripts/**` is unchecked and has rotted; `worktree.sh` is not revivable as-is |
| 27 | INT-031 · INT-056 · RDM-045 · CLD-084 · CLD-091 · INT-016 · DES-081 · US-DOC-02 | low | various | artifact/field mismatches — see compact entries |
| 28 | COMMIT-CHECK-FORGEABLE | low | safety | agent-authored story id reaches a glob unquoted; reporting-only blast radius |
| 29 | CLD-098 · DES-120 · INT-017 | low | various | convention and documentation conformance |

---

## DES-002 — the draft-PR gate is fail-open  {#DES-002}

- **Canon (intended):** *"Make the draft-PR gate fail-closed: create a draft PR by default and clear the draft flag only on positive evidence, rather than enumerating individual fail-open conditions."* (design doc, decision D2, :89). Restated as the project's readiness claim in `docs/STATUS.md:16-19`.
- **As-built (drift):** the gate's *shape* is right — `local draft_flag="--draft"` cleared only when `prd_present==1 && final_remaining==0 && verification_passed=="true"` (lib/run.sh:1177-1178) — but three of its inputs can report success without success occurring:
  - **(A) An unreadable PRD scores as complete.** Every jq in `verify_collect` ends `|| echo "0"` (lib/verification.sh:68-75), so invalid, truncated, markdown-fenced, or `.userStories`-less JSON yields `remaining=0`, while `prd_present=1` is a bare `[ -f ]`. "I cannot read the plan" is scored identically to "the plan is complete."
  - **(B) An empty story list scores as complete.** `{"userStories":[]}` passes `validate_prd_schema` (lib/schema.sh:125-183, no minimum-count check) → total=0, remaining=0.
  - **(C) Agent story-deletion scores as complete.** Nothing binds `prd.json`'s story set to the plan — no freeze, hash, or count invariant exists — so an agent that deletes a story it cannot implement yields remaining=0. The attempts-increment jq at lib/run.sh:1096 is a silent no-op on a vanished id.
  - **(D) A blank or commented-out `testCommand` reads as a pass.** `[ -n "${REQDRIVE_TEST_COMMAND:-}" ]` (lib/verification.sh:83) treats `" "` or `"# npm test (disabled)"` as configured, and `eval` of either exits 0 → `verification_passed: true` rather than `null`.
- **Severity:** critical — this is the guarantee the project's L2/L3 readiness rests on.
- **Verifier verdict:** confirmed by **two independent skeptics**, both reproducing it end-to-end with the repo's own `tests/lib/pipeline-harness.sh` in scratch directories. Observed `gh pr create` argv with **no `--draft`** for: a story-shrinking agent (`"Stories 1 / 1 completed"` while US-002 was never implemented), a resumed run with a fenced `prd.json` (`"stories": {"total": 0 … }`, `verification_passed: true`), an empty story list, and both disabled-`testCommand` forms. The second skeptic classified all four **real-run reachable**, not unit-only.
- **What is genuinely sound and should not be "fixed":** the three states the gate was written for — missing PRD, correctly-counted incomplete stories, and `verification_passed` null/false — all correctly force a draft; `${draft_flag:+"$draft_flag"}` survives `set -u` and the label-dropping retry; and no other code path creates a PR.
- **Suggested reconciliation:** distinguish "counted zero" from "could not count" — drop the `|| echo "0"` fallbacks and fail closed on a jq error; require `total > 0`; record the planned story-id set in `checkpoint.json` at first write and require the final set to be a superset; trim `testCommand` and reject a whitespace/comment-only value.
- **Note on the suite:** the shipped positive control (`tests/simple-test.sh`, *"draft gate: full evidence produces non-draft PR"*) uses `"testCommand": "true"` — a vacuous-evidence case — so the suite would not notice the gate degrading to trusting agent self-report.

## INT-030 · INT-048 · US-PR-01 — `pr_url` is not a URL  {#INT-030}

- **Canon (intended):** `run.json.pr_url` is the GitHub PR URL, `null` when no PR was created (docs/INTEGRATION.md:128); the completion hook receives `PR_URL` (:183); `create_pr` emits the URL on stdout (`tests/BEHAVIOR-SPEC.md`, US-PR-01).
- **As-built (drift):** `lib/pr-create.sh:95` echoes `"  Pushing branch <branch>..."` to **stdout** without `>&2` — the only diagnostic in the file that does not redirect. `lib/run.sh:1193` captures that stdout wholesale with no extraction, so the value is two lines.
- **Severity:** high — an integrating pipeline reading `.pr_url` gets an unusable value; `bin/reqdrive:293` prints it raw in `status`; the same string is exported to `completionHook` and to any external `reviewCommand` (lib/run.sh:499, :641).
- **Verifier verdict:** confirmed, measured under fake `git`/`gh`: `"  Pushing branch reqdrive/req-01...\nhttps://github.com/test/repo/pull/42"` (72 bytes, literal `\n` at offset 0o43). `run.json` stays *valid* JSON — `jq -Rn` escapes it faithfully — so this is a wrong-value defect, not a parse failure. The review phase survives by accident: its `grep -o '[0-9]*$'` is line-oriented and the push line ends in `...`.
- **Suggested reconciliation:** add `>&2` to lib/pr-create.sh:95 (and :97). One line. Note that `tests/BEHAVIOR-SPEC.md:953-958` currently *freezes* the polluted value as expected, so the spec story and the oracle lock must be updated with the fix.

## PR-OVERSTATES-COMPLETION — the PR body contradicts itself  {#PR-OVERSTATES-COMPLETION}

- **Canon (intended):** no requirement governs this line — which is itself the finding. The PR body is the product's only user-visible output.
- **As-built (drift):** `lib/pr-create.sh:109-110` builds `story_count` and `story_ids` from `.userStories` with **no `.passes` filter**, rendered at :227 under the literal label `**Stories completed:**`. The Pipeline Verification table in the *same body* (:168) uses the `.passes`-filtered count from `lib/verification.sh:69`.
- **Severity:** high — a draft PR for a run where 1 of 3 stories passed states `**Stories completed:** US-01, US-02, US-03 (3 stories)` directly above `| Stories | 1 / 3 completed |`.
- **Verifier verdict:** confirmed; reproduced by running the real `create_pr` with stubbed `git`/`gh` and capturing `--body`. `grep passes lib/pr-create.sh` returns zero hits.
- **Assessed and cleared in the same pass:** the validation checklist rendering every criterion as an unchecked `- [ ]` regardless of pass state is **correct** — unchecked is the conservative direction and the surrounding prose establishes the human as the ticker. Its weakness is omission, not overstatement: nothing marks which stories were never attempted.
- **Suggested reconciliation:** filter by `.passes == true`, or relabel to `**Stories in scope:**` and add a completed count.

## GLOB-FOOTGUN — a glob silently disables a risk tier  {#GLOB-FOOTGUN}

- **Canon (intended):** `policy.riskTiers` values are path **prefixes**, not globs (README.md:167-172), and `reqdrive validate` validates the policy block (lib/schema.sh:105-113).
- **As-built (drift):** patterns are matched literally (lib/policy.sh:24), so the natural-looking `"high": ["src/auth/**"]` matches only a file *named* `src/auth/**`. Nothing warns. Measured: `src/auth`, `src/auth/login.ts` and `src/auth/sub/deep.ts` all classify `none`, while `reqdrive validate` reports `✓ Schema valid` / `Validation PASSED` (exit 0).
- **Severity:** high — a security-adjacent control that silently does nothing, with a config that the project's own validator blesses. The code comments (lib/policy.sh:4-9) and README explain the semantics, so the gap is validation, not intent.
- **Verifier verdict:** confirmed, measured.
- **Suggested reconciliation:** reject `*`, `?` and `[` in tier patterns in `validate_config_schema`, or warn at load time.

## RDM-008 · INT-006 · INT-007 — authentication is never checked  {#RDM-008}

- **Canon (intended):** `gh` must be authenticated with push and PR-create permission (README.md:21, docs/INTEGRATION.md:33); `claude` must be installed **and authenticated** (docs/INTEGRATION.md:34).
- **As-built (drift):** only presence is checked (`command -v`, install.sh:13, bin/reqdrive:19,26). `gh auth` appears nowhere in executable code — only in human checklists in `docs/VERIFICATION-PLAN.md`. The first credential-requiring call is `git push` at lib/pr-create.sh:96, after branch creation, planning, every implementation iteration and verification.
- **Severity:** high — a read-only token or expired SSO burns a full unattended agent cycle before failing.
- **Verifier verdict:** confirmed.
- **Suggested reconciliation:** add `gh auth status` to preflight; it is one command and fails in under a second.

## INT-013 · INT-014 · INT-015 · INT-016 · INT-017 — the exit-code contract  {#INT-013}

`docs/INTEGRATION.md:440-460` explicitly instructs integrators to branch on
these codes, so a code that never fires as documented is a contract violation.
All five confirmed, all **measured**.

| REQ | Canon (intended) | As-built (drift) | Sev |
|-----|------------------|------------------|-----|
| **INT-013** {#INT-013b} | 3 = bad `reqdrive.json` **or** missing requirement file | a missing/incompatible manifest exits **1** (lib/config.sh:37-38,47-48); a *malformed-JSON* manifest exits **5**, colliding with `EXIT_AGENT_ERROR` — which INTEGRATION.md:445 marks retry-worthy, so a broken config yields an infinite retry loop. Only the missing-req-file half emits 3 | high |
| **INT-014** {#INT-014} | 4 = a git operation (checkout, commit, push) failed | 4 is emitted only by `cmd_verify`; a failed checkout aborts under `set -e` with git's raw **128** — a value absent from the contract entirely (lib/run.sh:906-912); push failure becomes 6 | high |
| **INT-015** {#INT-015} | 5 = the Claude invocation failed (timeout, crash, no PRD) | only the no-PRD case exits 5. Measured: an agent exiting 42 on every turn → pipeline **exit 0**; an agent timing out on every implementation turn → **exit 0** with a PR created. Partial mitigation: incomplete stories force `--draft`, so the PR is flagged even though the exit code says success | high |
| **INT-016** {#INT-016} | 6 = PR creation failed **after retry** | accurate for the `gh` path (one label-dropping retry, lib/pr-create.sh:273-284), but a `git push` failure also returns 6 with **no** retry — and INTEGRATION.md:54 assigns push failures to code 4 | med |
| **INT-017** {#INT-017} | 7 = the user sent SIGINT | SIGINT exits **130** (lib/run.sh:877). 7 fires only when a user declines the `--unsafe` prompt, which is TTY-gated and therefore unreachable in the unattended mode the contract targets | low |

- **Suggested reconciliation:** make `reqdrive_load_config` exit `EXIT_CONFIG_ERROR`; wrap the checkout/push sites to exit `EXIT_GIT_ERROR`; propagate `run_claude_iteration`'s failure to `EXIT_AGENT_ERROR`; document 128/130 or trap them.

## CLD-006 · CLD-108 · RDM-070 — promised path-traversal scanning does not exist  {#CLD-006}

- **Canon (intended):** "requirement content is scanned for dangerous patterns (shell injection, **path traversal**)" — README.md:159, CLAUDE.md:56 (declared a *security boundary*), CLAUDE.md:262. `docs/PIPELINE-ANALYSIS.md:187` goes further, tabulating `validate_file_path()` as a "Hard error / unbypassable" check.
- **As-built (drift):** `validate_file_path` (lib/sanitize.sh:112) has **zero callers** in `lib/` or `bin/` — its only references are tests, the spec, the lock and that analysis doc. None of the 15 `DANGEROUS_PATTERNS` matches `../`, `..\`, a leading `/`, `~/`, or `ln -s`. Measured: traversal probes pass the scan clean with no warning.
- **Severity:** medium — **downgraded from high on verification.** The verifier established that requirement *content* is never used as a filesystem path (it is only `cat`'d into the prompt), so scanning content for traversal would protect nothing; and PRD-derived fields reach only jq selectors and template tokens. **Not attacker-reachable.**
- **The real, separate gap the docs do not mention:** the **REQ-ID CLI argument** is unvalidated (`req_id="$1"`, bin/reqdrive:121) and reaches both the requirement-file glob (lib/run.sh:704) and `mkdir -p` (lib/run.sh:691,729). Measured: a REQ-ID of `../../../../pwndir` created a directory outside the project root, and `../../../secrets/pwned` passed preflight and read an out-of-tree `.md`. Operator-triggered today; genuinely exploitable if a future `reqdrive orchestrate` ever sources REQ-IDs from a file or remote input.
- **Verifier verdict:** confirmed with that reframing.
- **Suggested reconciliation:** either wire `validate_file_path` into the REQ-ID path and add a traversal pattern, or amend all four docs to say "shell injection and dangerous commands" and state the REQ-ID trust assumption explicitly.

## SANITIZE-PLANNING · SANITIZE-PR-BODY — escaping that now corrupts  {#SANITIZE-PLANNING}

- **Canon (intended):** design decision D9 — the `\$` corruption is fixed in its own enumerated step (design doc:96). `sanitize_for_prompt` exists to make content safe for a prompt, not to alter it.
- **As-built (drift):** the fix landed for the implementation prompt only. `build_planning_prompt` (lib/run.sh:276) appends content sanitized at :738 into a **quoted** heredoc (:213), so the escaping buys nothing and the backslashes survive; `lib/pr-create.sh:52` sanitizes review findings immediately before `gh pr edit --body`, an execve argv that is never shell-re-evaluated.
- **Severity:** medium — it degrades the text the planning agent reads and the text published to GitHub.
- **Verifier verdict:** both confirmed, measured end-to-end. `Budget is $500 for ${TEAM} and run \`make test\`` reaches `prompt.md` as `Budget is \$500 for \${TEAM} and run 'make test'` (`od -c` shows literal `0x5C` before each `0x24`). For the PR body, GFM renders `\$` as a plain `$` so the *rendered* impact is small — but the stored/API body carries the backslashes, and the backtick→`'` rule destroys code spans unconditionally.
- **Why it went unnoticed:** the guarding test (tests/simple-test.sh:1831-1845) feeds **raw** content directly to `build_planning_prompt`, bypassing `sanitize_for_prompt` entirely, and asserts with a substring match that passes on both the correct and corrupted forms.
- **Suggested reconciliation:** drop the `$`→`\$` substitution from `sanitize_for_prompt` now that no consumer is a shell context (and delete the reversal at lib/run.sh:317-321), or move the escaping to the one call site that needs it.

## CLD-086 — the scope check is warn-by-default, not a hard gate  {#CLD-086}

- **Canon (intended):** `policy.scopeCheck` defaults to `"warn"`; `"block"` is opt-in (README.md:181-197, design decision D6, `templates/reqdrive.json.example:18`).
- **As-built (drift):** the **code is correct** (`local mode="${REQDRIVE_POLICY_SCOPE_CHECK:-warn}"`, lib/policy.sh:56). The drift is documentary: `CLAUDE.md:212` calls `policy_scope_check` a "hard gate, not advisory", and `docs/STATUS.md:21-22` and `:94` repeat it.
- **Severity:** medium — it misrepresents the project's actual enforcement posture in the two docs a maintainer reads first, and contradicts the "warn before enforce" principle at CLAUDE.md:54.
- **Verifier verdict:** confirmed; the drift is wider than first reported (STATUS.md too). No doc-coverage gate checks CLAUDE.md, only README.
- **Suggested reconciliation:** replace CLAUDE.md:212 with "warn-only by default (`policy.scopeCheck: "warn"`), promotable to a hard gate with `"block"` (aborts with `EXIT_PREFLIGHT_FAILED`/8)", and correct STATUS.md.

## Compact entries

Each confirmed, each with a verifier verdict; grouped to keep the fix list usable.

**config / init**
- **RDM-012 · CLD-030** {#RDM-012} *(medium)* — canon: `init` creates a valid `reqdrive.json`. Drift: `lib/init.sh:57-68` interpolates raw answers with no JSON escaping. Measured: `My "Quoted" Project` → `jq empty` parse error while init prints "Done!" and exits 0; `C:\reqs` parses but silently becomes `C:<CR>eqs`; a crafted answer can inject sibling keys. Fix: `jq -n --arg`.
- **VALIDATE-FALSE-PASS** {#VALIDATE-FALSE-PASS} *(medium, no governing req)* — `lib/validate.sh` never calls `check_schema_version`, so a `version: "1.0.0"` config reports "Validation PASSED" (exit 0) while `reqdrive run` refuses it (exit 1). Measured both.
- **ATTEMPTS-UNVALIDATED** {#ATTEMPTS-UNVALIDATED} *(medium, no governing req)* — `attempts` is absent from `lib/schema.sh` entirely. Measured: `"attempts": "lots"` passes validation, and jq's cross-type ordering makes `(("lots" // 0) < 3)` false, so the story is permanently skipped and the loop logs "All stories complete!". Contained: Phase 3 still counts it remaining, so the PR drafts. It also flips `verification.sh:74`'s `>= max` true, mislabelling it retry-exhausted.
- `reqdrive validate` always prints "(1 errors)" — `ERRORS` increments once per failed *check group* and only one group exists (lib/validate.sh:27-36). Cosmetic; each violation is still printed and exit 3 is right.

**evidence / policy**
- **DES-116 · DES-131** {#DES-116} *(medium)* — canon: a scope finding is recorded in `checkpoint.json`. Drift: `save_checkpoint` (lib/run.sh:88-121) has no scope field in any mode, and block mode exits at :1092 *before* the save at :1101. Findings survive only in `scope-findings.txt` (both modes) and the PR body (warn only).
- **DES-114** {#DES-114} *(low)* — canon: post-iteration path classification is recorded. Drift: `policy_classify_paths` (lib/policy.sh:35) has zero callers anywhere, including tests — a knowing bypass (see the comment at :48-51), but `tests/BEHAVIOR-SPEC.md:1454` still describes it as the matcher the scope check consumes. Only the high-tier violating subset is persisted.
- **TIER-NAME-FOOTGUN** {#TIER-NAME-FOOTGUN} *(medium, no governing req)* — only `high`/`medium`/`low` are probed (lib/policy.sh:19); a `critical` tier validates clean and is inert. Measured.
- **RDM-077** {#RDM-077} *(medium)* — canon: warn findings render under a `### Scope findings` heading. Drift: `$(printf '\n### Scope findings\n\n')` at lib/pr-create.sh:186 loses its trailing newlines, fusing the first finding onto the heading. Measured with `cat -A`. Findings 2..n render fine.
- **US-REV-05** {#US-REV-05} *(medium)* — same command-substitution bug at lib/pr-create.sh:40-42 collapses the review findings heading, header row, delimiter and first finding onto one line, so GFM renders no table at all.

**pipeline / cli artifacts**
- **CLD-001** {#CLD-001} *(medium)* — canon: "the shell controls what to work on, when to stop… the agent never decides what to work on next." Verified true in the narrow sense: given a fixed `prd.json`, `select_next_story` is a pure deterministic function and the agent cannot influence its own assignment within an iteration (selection at lib/run.sh:1028 precedes prompt-building at :1043). Verified **false** in the causal sense: the agent authors `prd.json`, the prompt at lib/run.sh:366 explicitly invites it to reorder priorities, and `<promise>COMPLETE</promise>` (:1112) ends Phase 2 with no re-check. A missing `priority` sorts first (jq null ordering, measured). Contained by the fail-closed intent of Phase 3 — see DES-002 for how far that containment actually holds. Fix: amend the principle to "reproducible given a fixed PRD, plus a fail-closed outcome gate", and correct the stale `lib/run.sh:347` citation (it is :413).
- **INT-031** *(low)* — `RUN_SUMMARY_*` initialise to 0 before Phase 1 (lib/run.sh:935), so a planning failure writes a zeroed `.summary` where `null` is specified.
- **INT-056** *(low)* — `verification.test.log` and `iteration-N.test.log` are absent, or stale from a previous run, when no `testCommand` is configured (lib/verification.sh:92-95).
- **RDM-045** {#RDM-045} *(medium)* — canon: `projectName` supplies the PR title. Drift: `lib/pr-create.sh` never reads it; the title comes from the PRD's `.project` or `"<REQ> Implementation"`.
- **CLD-084** {#CLD-084} *(low)* — canon: the PR body carries an iteration-log summary. Drift: only an `iterations run/max` table row exists.
- **CLD-091** {#CLD-091} *(low)* — canon: `pr-create.sh` consumes `REQDRIVE_POLICY_*`. Drift: it reads `scope-findings.txt` directly; zero references to either variable. Fix the doc, not the code.
- **INT-005** {#INT-005} *(medium)* — canon: a clean tree **on baseBranch**. Drift: nothing compares HEAD to baseBranch (lib/preflight.sh:165-201). Harmless for a fresh run (the branch is cut from the configured base at lib/run.sh:911), but on the existing-branch path lib/preflight.sh:40-45 downgrades a pre-existing `reqdrive/<slug>` to a warning — measured: an unrelated commit from a mis-based branch landed in the PR.

**prerequisites**
- **RDM-005** {#RDM-005} *(medium)* — bash 4.0+ is documented and never checked; `declare -A` at lib/errors.sh:21 is sourced unconditionally, so stock macOS bash 3.2 fails at source time for *every* command, including `--help`.
- **RDM-009** {#RDM-009} *(medium)* — canon: `claude` only for `run`/`launch`. Drift in both directions: `cmd_plan` requires it (bin/reqdrive:395); `install.sh:12` makes it an install-time hard requirement, blocking `validate`/`init`/`status`/`logs`/`migrate`; `cmd_launch` never checks it, deferring the error into the detached child's `output.log` while `launch` exits 0.
- **RDM-010** {#RDM-010} *(medium)* — `timeout`/`sha256sum` documented, checked by neither installer nor CLI. Worse than reported: `lib/run.sh:6` sets `set -e` without `pipefail`, so a missing `timeout` in `timeout … | tee` yields `tee`'s status 0 — the failure is **silent** and misreported as "Agent failed to create PRD after 2 attempts". (`sha256sum` *is* self-checked at tests/oracle-gate.sh:23.)
- **CLD-058** {#CLD-058} *(low)* — CLAUDE.md:128 and :250-256 claim "bash/jq/git/gh"; the real runtime set adds `claude` and `timeout`. README.md:23 already concedes this; CLAUDE.md was never updated.
- **CLD-099** {#CLD-099} *(medium)* — canon: every modified `.sh` passes `bash -n`. Drift: CI covers `bin/`, `lib/`, `install.sh` only. Note the two halves are causally independent — `scripts/setup-validation-env.sh` **passes** `bash -n`; its rot is semantic (missing `templates/prompt.md.tpl` :212; sources `lib/prd-gen.sh`/`agent-run.sh`/`verify.sh` :262,270,275, all archived; calls undefined `reqdrive_load_config_path` :299; emits a v0.1.x manifest), so closing the CI gap would not have caught it.

**self-description**
- **CLD-059** {#CLD-059} *(medium)* — canon: keep the library at the simplified ~5-script shape ("17 scripts to 5", CLAUDE.md:131; `docs/SIMPLIFICATION-SUMMARY.md:231`). Measured: `lib/` is **11 files / 2,683 lines** vs the archived v0.1.x `lib/`'s **13 files / 1,770 lines** — 913 lines (52%) *larger* than what it replaced. The archived figure quoted in both docs (1,679) is itself 91 lines under the on-disk total. The anti-goal holds (no v0.1.x module returned); the numeric claim does not.
- **ARCHIVE-ROT** {#ARCHIVE-ROT} *(low, corrected on verification)* — CLAUDE.md:139 keeps `archive/` so `worktree.sh` can be revived for `orchestrate`. It is not drop-in revivable, but **less broken than first reported**: `ERR_WORKTREE`, `ERR_GIT`, `log_info` and `log_warn` *do* resolve via the co-archived `errors.sh:32-50`. Genuinely unresolvable: `reqdrive_resolve_path`, `reqdrive_timestamp`, `$REQDRIVE_PATHS_AGENT_DIR`, `$REQDRIVE_AGENT_WORKTREE_PREFIX` — all from the v0.1.x config layer, which was **deleted rather than archived**. Reviving means porting a path resolver and two env vars. Related: seven archived scripts still `source "${REQDRIVE_ROOT}/lib/config.sh"`, now silently resolving to the live 0.3.0 loader. Also `skills/README.md:29-30` still calls `reqdrive plan` "coming soon" and `reqdrive verify` "(future)"; both shipped.
- **DES-120** {#DES-120} *(low)* — the WORKFLOW.md L2→L0 correction was never applied; it lives parked at `docs/STATUS.md:59-83`. That file is outside this checkout, so this is not code-fixable here.

**test harness**
- **DES-008 · DES-060** {#DES-008} *(medium)* — canon: decision D8, "lock generated in the CI environment configuration". Drift: `tests/oracle.lock.json` records `environment.claude: true` and `generated: 2026-07-24` — it was generated on a workstation with `claude` on PATH. CI installs no `claude`, and `tests/oracle-gate.sh` reads `.environment` **only** in the `--accept` writer (:69), never at enforce time. The field is decorative; the two `conditional: "claude"` entries are what actually keep CI green.
- **DES-059 · DES-121** {#DES-059} *(medium)* — canon: the pure-negative count is measured and triaged. Drift: **24** today (13 terminal `!` + 11 `[ -z `), derived twice by independent methods; `tests/FINDINGS.md:18` and `docs/STATUS.md:43` both say 18, and the design doc says ~21. The suite grew 157→202 and the figure was never remeasured. (A stricter reading that excludes 3 guard-form hits gives 21 — still not 18.)
- **DES-101** {#DES-101} *(medium)* — canon: the characterization test proves the extraction did not change the summary. Drift: of its 12 `jq -e` assertions (tests/simple-test.sh:2669-2685), 10 are bare `has()` presence checks; the other two pin a constant string and a non-null. No computed value is pinned — flipping `.stories.completed` from 3 to 0, or `prd_present` from true to false, leaves it green. `prd_present` is exactly the field the draft gate keys on.
- **DES-072** {#DES-072} *(low)* — the "missing prd.json forces draft" test was retargeted (commit `551d454`) to assert a planning-abort (rc==5, no `pr create`), so the `prd_present != 1` branch at lib/run.sh:1178/:1181 has no exercising test. `tests/FINDINGS.md:19` (F6) records this honestly.
- **DES-081 · US-DOC-02** {#DES-081} *(low)* — `DOC_EXEMPT` has **5** members (tests/simple-test.sh:2987); the design spec pins 2 (:264) and `tests/BEHAVIOR-SPEC.md:1362` pins 3. The two extra names are `REQDRIVE_POLICY_JSON`/`REQDRIVE_POLICY_SCOPE_CHECK`; `policy` *is* documented at README.md:101, so nothing undocumented is being concealed — but neither spec was updated to authorise them.

**conventions**
- **COMMIT-CHECK-FORGEABLE** {#COMMIT-CHECK-FORGEABLE} *(low — downgraded from high)* — `lib/run.sh:1077` interpolates the agent-authored story id unquoted into a `[[ == ]]` RHS pattern, and `lib/schema.sh:159` constrains `.id` to existence only. Measured: id `US-*` credits a stale prior-iteration commit; id `US-[0-9]` likewise. **Bounded**: the `feat:\ \[` prefix is backslash-escaped and literal-anchored, so no id matches a non-conforming message. **Downgraded** because nothing gates on the counter (the draft gate at :1178 ignores it), and because the signal was already trivially forgeable — the agent writes the commit messages, so `git commit --allow-empty -m 'feat: [US-2] done'` passes with a perfectly literal id. Worth a one-line quote as hygiene.
- **CLD-098** {#CLD-098} *(low)* — canon: library scripts set `set -e`. Drift: 6 of 11 do not (`config`, `errors`, `pr-create`, `preflight`, `sanitize`, `schema`). **No concrete bug follows** — every lib is sourced into `bin/reqdrive`, which sets `set -euo pipefail`. Documentation-conformance only. The inverse is the live hazard: the 5 that *do* set it at file top level mutate their sourcer's options, which `tests/simple-test.sh:374` already works around.

---

## Refuted or corrected in verification — do not re-raise

- **"The oracle gate passes against a red suite."** *Refuted.* `oracle-gate.sh` does capture `SUITE_RC` (:47) and never gates on it, and `--accept` will lock a red suite — but R2 (:158-164) fails the gate for any locked test that FAILs, R6 for any unlocked name that ran, and `tests/gate-selftest.sh:73` demonstrates R2 firing. A lock taken while red reddens on the very next enforce run. Residual hole is narrow: a suite emitting all 202 expected PASS lines yet exiting non-zero for an unrelated reason.
- **"`reqdrive_load_config` not calling `validate_config_schema` is drift."** *Refuted* — it is a recorded decision (CLAUDE.md:187) and the code matches it exactly. The *consequence* is real and documented in [modules/config.md](../modules/config.md): jq's `//` fires only on null/false, so wrong-typed truthy values pass through — measured, `policy.scopeCheck: "blocking"` loads and silently degrades the gate to warn; `maxIterations: "ten"` breaks `seq` so the loop body never runs.
- **"`archive/v1-complex/lib/worktree.sh` calls 8 symbols that exist nowhere."** *Corrected to 4 of 8* — see [ARCHIVE-ROT](#ARCHIVE-ROT).
- **"The validation checklist does not exist / is fake."** *Refuted* — it is real and reaches `gh pr create --body`; see [claims-audit.md](../claims-audit.md) for its verified caveats.
