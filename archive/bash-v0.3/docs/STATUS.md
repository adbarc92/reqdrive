# reqdrive — Status

## State summary

**Readiness:** L3 on the Readiness Ladder (L0 Specified, L1 Correct, L2
Trustworthy, L3 Agent-operable, L4 Shippable) — target met. L4 is not
targeted: reqdrive is a harness, not a shipped product.

**What changed:** the whole roadmap-completion effort (P0-P7) took reqdrive
from L0 to L3. P0 repaired the test harness — it structurally could not
report a failure, because `set -e` truncated the suite on the first error
instead of tallying it, so "all green" was guaranteed by construction. P1
wrote behavior-spec stories for every assertion. P2 froze the suite behind
a whole-file-hash tamper-evidence gate (`tests/oracle-gate.sh`). P3 built a
pipeline test harness. P4 made the draft-PR gate fail-closed — a PR is only
opened non-draft when `prd.json` is present, zero stories remain incomplete,
and `testCommand` positively passed (the L2 fix). P5 added three
doc-coverage gates and automated the `launch` lifecycle (the L3 gates). P6
rewrote the implementation prompt heredoc safely (quoted heredoc + explicit
`@@TOKEN@@` substitution) and added `reqdrive verify` as a standalone
command. P7 added the policy cluster — risk tiers by path and a hard-gated
post-iteration scope check. All CLAUDE.md Tier 2 roadmap items are now
complete.

**Known gaps:**
- `launch` lifecycle coverage is Linux-CI-only — PID liveness and signal
  trapping are unreliable under MSYS2, so that coverage does not extend to
  Windows/MSYS2 runs.
- The review agent is not a genuine writer≠grader: it uses the same model
  as the implementer, is off by default (`reviewCommand` empty), and runs
  after PR creation, so it cannot influence the draft decision. See the
  CLAUDE.md Decision Log.
- Config load does not schema-validate; `reqdrive validate` remains the
  validation entry point (see the CLAUDE.md Decision Log entry on deferring
  config-load-time schema validation).
- Open items tracked in `tests/FINDINGS.md`, all triaged Open — deferred /
  accepted risk, not blocking:
  - **F2** — an unanchored `$HOME` grep in one `tests/simple-test.sh`
    assertion.
  - **F3** — `build_implementation_prompt` (`lib/run.sh:285-288`) writes a
    blank Title/Description/Criteria when `jq` fails on malformed story
    JSON, with no guard or assertion.
  - **F4** — 18 assertions suite-wide end in a pure negative and cannot
    detect a setup failure (measured 2026-07-23).
  - **F6** — the draft-PR gate's `prd_present==0` branch (mid-run deletion
    of `prd.json`) is defensive and fails closed by construction, but is
    not exercised by a dedicated test.

**Next steps:** Tier 3, in the order recorded in the CLAUDE.md Decision Log:
vision-based QA agent, multi-requirement parallelism (`orchestrate`), PR
rejection feedback loop, CI integration, cost tracking / token budgets,
adaptive retry policies. The cheapest next item is CI integration
(`gh pr checks` polling — cheap in bash, but wants its own spec for the new
failure mode a polling loop introduces). The highest-value item is
vision-based QA, which is out of scope for this harness — it needs
Playwright and binary image data and is properly a separate Node/Python
product with its own readiness ladder.

## Corrections owed to WORKFLOW.md

`WORKFLOW.md` is not reachable from this checkout (it lives outside this
repo), so the correction below could not be applied directly and is
recorded here for manual application.

WORKFLOW.md §10 records reqdrive's starting position as **"L2, gap
docs-only"**, and §9's worked example repeats the same claim. Both are
wrong. reqdrive's true starting rung was **L0**, not L2:

- The claimed L1 (Correct) was not actually held: the test harness used
  `set -e`, which meant the suite could not report a failure at all — a
  failing assertion aborted the script before the pass/fail tally ran, so
  "157 passed, 0 failed" was guaranteed by construction regardless of
  whether the code was correct. A suite that cannot fail cannot certify L1.
- The claimed L2 (Trustworthy) was not actually held either: the draft-PR
  gate fail-*opened* in three distinct ways (a non-draft PR could be
  created without positive evidence of success). The original WORKFLOW.md
  survey found and recorded one of the three; the other two were only
  found during this effort's P4 phase.

Both the §10 table row and the §9 worked example should be corrected to
show reqdrive starting at **L0** (not L2) and reaching **L3** as of
2026-07-23 (not L4, since L4 is not targeted for a harness).

## Session log

### 2026-07-23 — Roadmap completion (P0-P7): L0 to L3
Eight-phase effort (P0-P7) taking reqdrive from Readiness Ladder rung L0 to L3.
P0 repaired the test harness (it structurally could not report a failure).
P1 wrote behavior-spec stories for all original assertions. P2 froze the
suite with a whole-file-hash tamper-evidence gate. P3 built a pipeline test
harness. P4 made the draft-PR gate fail-closed (the L2 fix). P5 added three
doc-coverage gates and automated the `launch` lifecycle (the L3 gates). P6
rewrote the implementation prompt heredoc safely and added `reqdrive
verify`. P7 added the policy cluster (risk tiers by path + hard-gated scope
check). All CLAUDE.md Tier 2 roadmap items completed; Tier 3 recorded as
deferred, with a reason per item, in the CLAUDE.md Decision Log. Frozen
suite: 202/202 passing. `ROADMAP.md` (the v0.2.0 simplification plan)
marked superseded by CLAUDE.md's Roadmap section. This file created per the
global `docs/STATUS.md` convention.
