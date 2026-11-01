# Claims Audit — stated capabilities vs. canon

What the project says about itself, graded against
[the canon](architecture.md) at commit `7420d69` (2026-07-24). Every grade is
anchored; the evidence lives in [requirements/drift-report.md](requirements/drift-report.md)
and the module docs.

Grades: **Supported** (true as written) · **Supported, with caveat** (true, but a
reader would want the caveat) · **Overstated** (the load-bearing word does more
work than the code earns) · **Unsupported** (not true today).

## Claims under audit

The one-line descriptions the project is summarized by, in the two forms it is
usually stated:

> *reqdrive — a requirements-to-PR pipeline that generates a PRD, then implements
> story-by-story deterministically and opens a PR with a validation checklist.*

> *reqdrive — a requirements-to-PR pipeline: takes a written spec, generates a
> PRD, implements story-by-story deterministically, and opens a PR with a
> validation checklist — the ambiguity-to-working-code loop, automated.*

And the strongest form of the summary claim:

> *…a pipeline that turns written requirements into **reviewed, working**
> pull requests.*

## Verdict table

| # | Claim | Grade | Evidence |
|---|-------|-------|----------|
| 1 | "requirements-to-PR pipeline" / "takes a written spec" | **Supported** | markdown req in → GitHub PR out, end to end (lib/run.sh:855 → lib/pr-create.sh:261) |
| 2 | "generates a PRD" | **Supported** | Phase 1 writes `prd.json` and hard-aborts with exit 5 if the agent produces none (lib/run.sh:962-997) |
| 3 | "implements story-by-story" | **Supported** | one stateless `claude` process per story, fresh each time (lib/run.sh:1019-1046, :447-478) |
| 4 | "deterministically" | **Supported, with caveat** | see below |
| 5 | "opens a PR with a validation checklist" | **Supported, with caveat** | see below |
| 6 | "**reviewed** … pull requests" | **Overstated** | see below |
| 7 | "**working** pull requests" | **Overstated** | see below |
| 8 | "the ambiguity-to-working-code loop, automated" | **Supported, with caveat** | the loop is genuinely automated end to end; "working" carries the same weight as #7 |

---

### #4 "deterministically" — Supported, with caveat

**What is true, and it is the non-obvious engineering:** story selection is a
pure jq function of `prd.json` — `[.userStories[] | select(.passes != true and
((.attempts // 0) < $max))] | sort_by(.priority) | first | .id`
(lib/run.sh:423-428). The agent is never asked what to work on; the shell selects
at `lib/run.sh:1028` *before* building the prompt at `:1043`, and the prompt says
"implement ONLY story `@@STORY_ID@@`". Three consecutive runs on a fixed PRD were
verified identical. That is a real property most agent harnesses do not have.

**The caveat:** `prd.json` — the sole input to that function — is written by the
agent, and the implementation prompt explicitly invites it to *"update priorities
in prd.json"* (lib/run.sh:366). The agent therefore influences future selection
one iteration ahead, can remove a story from the queue by setting `passes: true`
(nothing re-verifies that per story), and can end Phase 2 early with
`<promise>COMPLETE</promise>` (lib/run.sh:1112). A story omitting `priority` sorts
first under jq's null ordering.

**Fair phrasing:** "deterministic story selection" or "the shell, not the agent,
picks the next story" — both fully earned. "Deterministic pipeline" is not.
→ [CLD-001](requirements/drift-report.md#CLD-001)

### #5 "opens a PR with a validation checklist" — Supported, with caveat

**Verified true, end to end.** A dedicated verifier tried to refute this and
could not: `lib/pr-create.sh:112-121` reads each story's `id`, `title` and
`acceptanceCriteria[]` and emits

```
### Functional Verification

### US-001: Login form
- [ ] User can submit email and password
- [ ] Invalid creds show an error
```

spliced at `:246` into the body that reaches `gh pr create --body` at `:267`.
Rendered end-to-end under a fake `gh`. The PR body *also* carries a Pipeline
Verification table from `verification-summary.json` (`:160-178`) and a scope-findings
section (`:183-191`) — both more than the claim promises.

**The caveats a careful reader would want:**
- It degrades **silently**. A story whose `acceptanceCriteria` is missing ships as a heading with zero checkboxes (jq's error goes to stderr inside a process substitution, so `set -e` never fires); `prd.json` absent, `userStories: []` and `acceptanceCriteria: []` all render an identical empty section. A reviewer cannot tell "nothing to verify" from "the content was lost". Schema validation *would* catch it but is warn-only at every call site (lib/run.sh:916, 1000, 1106).
- Nothing downstream reads the checklist back or gates a merge on it — it is a prompt to a human, which is the honest reading of "validation checklist" but worth knowing.
- Zero test coverage: no assertion anywhere checks that a `- [ ]` line ever appears.
- One line in the same body is factually wrong: `**Stories completed:** <all story ids>` has no `.passes` filter, so it contradicts the verification table directly above it. → [PR-OVERSTATES-COMPLETION](requirements/drift-report.md#PR-OVERSTATES-COMPLETION)

### #6 "reviewed … pull requests" — Overstated

This is the weakest claim in the set, and the project's own decision log
already says so (CLAUDE.md:190):

- **Off by default.** `reviewCommand` defaults to `""` (lib/config.sh); with the default config no review happens at all.
- **Not an independent grader.** The review runs on the *same* `$model` as the implementer (lib/run.sh:1195 → :610) — writer and grader are the same system.
- **Cannot influence the outcome.** It runs *after* `gh pr create` (lib/run.sh:1193 then :1195) and returns 0 on every path (:521, 543, 626, 666), so it can never change the draft flag or abort anything.
- **And the output is currently broken.** The findings table's heading, header row, delimiter and first finding collapse onto one line (lib/pr-create.sh:40-42), so GFM renders no table; the same section is passed through `sanitize_for_prompt` before `gh pr edit`, publishing literal `\$` and turning code spans into single quotes. → [US-REV-05](requirements/drift-report.md#US-REV-05)

**Fair phrasing:** "opens a PR with a verification table and a validation
checklist for human review", or "with an optional post-PR review pass". Drop
"reviewed" as an unqualified property of the output.

### #7 "working pull requests" — Overstated

"Working" implies the pipeline will not present unverified work as ready. The
design decision that would earn it — D2, *"the draft-PR gate becomes fail-closed:
draft by default, cleared only on positive evidence"* — is the project's stated
L2 fix and its headline readiness claim (`docs/STATUS.md:16-19`).

**The gate's shape is right; three of its inputs can report success without
success occurring.** Two independent verifiers reproduced **non-draft PRs with
real incomplete work** using the repo's own test harness:

| Path | What happens | Observed |
|------|--------------|----------|
| Unparseable / fenced / `.userStories`-less `prd.json` | every jq in `verify_collect` ends `\|\| echo "0"` (lib/verification.sh:68-75), so "cannot count" reads as "zero remaining"; `prd_present` is a bare `[ -f ]` | `gh pr create` with **no `--draft`**, body reading "Verification passed / Stories 0 / 0 completed" |
| Agent deletes a story it cannot implement | nothing binds `prd.json`'s story set to the plan — no freeze, hash or count invariant | non-draft PR asserting "Stories 1 / 1 completed" while US-002 was never implemented |
| `userStories: []` | passes `validate_prd_schema` (no minimum-count check) | non-draft PR, zero commits, "Verification passed" |
| `testCommand: " "` or `"# npm test (disabled)"` | `[ -n … ]` says configured, `eval` exits 0 | `verification_passed: true` instead of `null` → non-draft |

Two further facts a reader should weigh: a Claude **timeout or crash exits 0**
(lib/run.sh:465-478 — measured), so an integrator branching on exit status cannot
see agent failure; and nothing ever independently checks a story's self-reported
`passes: true` (lib/verification.sh:69).

**What genuinely holds:** the three states the gate was written for — missing
PRD, correctly-counted incomplete stories, and `verification_passed` null/false —
*do* force a draft; the final test suite really is executed (`eval
"$REQDRIVE_TEST_COMMAND"`, lib/verification.sh:85), not merely re-read from the
agent's self-report; and no other code path creates a PR.

**Fair phrasing:** "opens a draft PR unless the story set is complete and the
test suite passes" — accurate, still impressive, and does not rest on the
fail-open paths. → [DES-002](requirements/drift-report.md#DES-002)

---

## README and in-repo publicity

| Claim | Grade | Note |
|-------|-------|------|
| "Version 0.3.0" | **Supported** | `bin/reqdrive:11`, measured |
| Command table (10 commands) | **Supported** | every documented command exists and every existing command is documented — machine-gated (tests/simple-test.sh:2963) |
| Config field table (12 fields, defaults) | **Supported** | all 12 read at lib/config.sh:53-91 with matching defaults; the README table is *more* accurate than CLAUDE.md's, which omits `maxStoryRetries` and `policy` |
| `orchestrate` "**Not implemented** — prints a coming soon notice and exits 0" | **Supported** | measured. Honest self-description |
| `verify` exit codes 0/9/3/4/10 | **Supported** | all five measured |
| Risk-tier prefix semantics (`src/auth` matches `src/auth/login.ts`, not `src/authorization/x.ts`) | **Supported** | measured exactly as documented — one of the better-specified parts of the repo |
| Scope check "warn by default, block opt-in", with the rationale | **Supported** | code matches; it is CLAUDE.md:212 and STATUS.md that wrongly call it a hard gate → [CLD-086](requirements/drift-report.md#CLD-086) |
| "Requirement content is scanned for … **path traversal**" (README.md:159, CLAUDE.md:56/262, PIPELINE-ANALYSIS.md:187) | **Unsupported** | `validate_file_path` has zero runtime callers and no pattern matches `../`. Mitigating: content is never used as a path, so the check would protect nothing — the real gap is the unvalidated REQ-ID argument → [CLD-006](requirements/drift-report.md#CLD-006) |
| "Windows Users: … Git Bash or WSL2" (README.md:25) | **Unsupported by evidence** | all six CI jobs are `ubuntu-latest`; nothing verifies MSYS2/WSL2. The suite does pass locally under Git-Bash (202/202, ~10 min) |
| "all 152 tests must pass" (CLAUDE.md:232) / "157 tests" (CLAUDE.md:26) | **Unsupported** | measured **202** in the suite, the lock and BEHAVIOR-SPEC; `docs/STATUS.md:97`'s "202/202" is the correct figure |
| "Simplification from 17 scripts to 5" (CLAUDE.md:131) | **Unsupported** | `lib/` is 11 files / 2,683 lines — 52% *larger* than the 1,770-line v0.1.x lib it replaced → [CLD-059](requirements/drift-report.md#CLD-059) |
| "L3 on the Readiness Ladder" (docs/STATUS.md:5) | **Overstated** | L3 rests on the L2 fix (the fail-closed gate), which does not hold → #7 above. L1 *is* now genuinely held: the harness can report a failure (202/202 correct assertion form, 0 deviations) and is frozen behind whole-file hashes |

## What to do with this

**Defensible as written, no change needed:** #1, #2, #3, and every README row
graded Supported. The determinism property and the risk-tier semantics are the
two things here that are more rigorous than the average project of this kind, and
both survived adversarial verification intact.

**Worth rewording wherever the project is described** — one sentence covers both:

> *reqdrive — a requirements-to-PR pipeline: takes a written spec, generates a
> PRD, then implements story-by-story with deterministic shell-side story
> selection, opening a draft PR unless the story set is complete and the test
> suite passes — with a validation checklist and verification table in the body.*

That drops "reviewed" and unqualified "working", keeps everything the code
earns, and is arguably a stronger claim because "draft unless proven" is a more
specific engineering statement than "working".

**Worth fixing in the repo first**, if the claim matters more than the wording:
[DES-002](requirements/drift-report.md#DES-002) is four bounded changes (fail
closed on a jq error instead of `|| echo "0"`; require `total > 0`; pin the story
set in the checkpoint; trim `testCommand`). Fixing them would make "working"
defensible as written.
