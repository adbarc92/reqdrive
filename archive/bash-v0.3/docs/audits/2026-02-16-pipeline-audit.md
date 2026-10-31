> **Historical document — dated 2026-02-16. Corrections appended 2026-07-23.**
>
> **Retracted claim:** this audit states that reqdrive "validates inputs
> exhaustively but never verifies outputs." That is **false** as of the
> verification phase. `lib/run.sh:1106-1117` re-runs the configured
> `testCommand` and derives `verification_passed` from the process exit
> code — an independent output check, not agent self-report.
>
> **Still true, and worse than this audit found:** the draft-PR gate
> fail-opened three ways (null verification, missing `prd.json`, and
> stories omitting the optional `passes` field). All three are closed by
> the fail-closed inversion in
> [`docs/superpowers/specs/2026-07-23-reqdrive-roadmap-completion-design.md`](../superpowers/specs/2026-07-23-reqdrive-roadmap-completion-design.md).
>
> The Tier 1/2/3 recommendations below drove the roadmap in `CLAUDE.md`
> and are retained as the reasoning behind it.

# reqdrive Pipeline — Audit Report

## Executive Summary

reqdrive v0.3.0 is a well-engineered Bash CLI (~750 lines across 8 modules + 530-line entry point) that automates the path from a markdown requirement document to a GitHub pull request by orchestrating Claude Code as an autonomous coding agent. The core pipeline — pre-flight checks, PRD generation, deterministic story-by-story implementation, and PR creation — is production-ready, thoroughly tested (135+ tests), and thoughtfully designed around a key architectural insight: the shell controls *what* and *when*, the agent controls *how*.

**What exists is strong.** The input validation is multi-layered (pattern detection, shell escaping, path traversal prevention). The checkpoint/resume system handles expensive long-running operations gracefully. Story selection is deterministic via jq, preventing agent drift. PR creation includes retry logic for common failure modes. The codebase is modular, well-commented, and follows consistent conventions.

**What's missing is output verification.** The pipeline validates inputs exhaustively but never verifies outputs. It doesn't check if commits actually happened, doesn't run tests itself (delegates entirely to the agent), doesn't verify that changed files are in-scope for the target story, and relies on the agent's self-reported iteration summaries for observability. The `testCommand` config field is auto-detected during `init` but never executed by the shell. This means the pipeline can report success even when the agent failed silently, committed nothing, or broke existing tests.

**The gap between "reqdrive works" and "reqdrive produces mergeable PRs overnight" is primarily the verification layer.** The six-stage vision (CLARIFY → SPECIFY → TEST → IMPLEMENT → VERIFY → SHIP) maps cleanly onto what exists: Stages 2 and 4 are implemented, Stage 6 is partially implemented, and Stages 1, 3, and 5 are either prompt-only patterns (skills) or entirely missing. The clarification and PRD skills exist as interactive Claude Code skills but are not wired into the automated pipeline. The verification-workflow skill has good reference material but no automation harness. There is no test-before-implement capability and no retry-on-failure loop.

---

## Inventory

| Artifact | Path | Purpose | Stage Mapping | Maturity |
|----------|------|---------|---------------|----------|
| CLI entry point | `bin/reqdrive` (531 lines) | Command dispatch, arg parsing, dependency checks | All | Production |
| Error codes | `lib/errors.sh` (62 lines) | Exit codes 0-8 + `die()`/`die_on_error()` | All | Production |
| Config loader | `lib/config.sh` (92 lines) | Manifest discovery (walk-up), env var export | All | Production |
| Schema validator | `lib/schema.sh` (190 lines) | JSON validation for config, PRD, checkpoint | Stage 2, 4 | Production |
| Input sanitizer | `lib/sanitize.sh` (138 lines) | Shell injection prevention, label cleaning | Stage 2, 4 | Production |
| Pre-flight checks | `lib/preflight.sh` (197 lines) | Git state, branch, requirement file validation | Stage 4 | Production |
| Core pipeline | `lib/run.sh` (723 lines) | Planning → implementation loop → PR creation | Stage 2, 4, 6 | Production |
| PR creation | `lib/pr-create.sh` (169 lines) | Push branch, build checklist, create GH PR | Stage 6 | Production |
| Init wizard | `lib/init.sh` (97 lines) | Interactive project setup | Setup | Production |
| Config validator | `lib/validate.sh` (72 lines) | Validate reqdrive.json | Setup | Production |
| PRD skill | `skills/prd/SKILL.md` | Interactive PRD generation with clarifying questions | Stage 1, 2 | Reference |
| Design-to-PRD skill | `skills/design-to-prd/SKILL.md` | Transform design docs into structured PRDs | Stage 1, 2 | Reference |
| Verification skill | `skills/verification-workflow/SKILL.md` | Test generation + static analysis + reporting | Stage 3, 5 | Reference |
| Project detection | `skills/verification-workflow/scripts/detect_project.sh` | Identify project type (Next.js, Expo, Spring Boot) | Stage 5 | Production |
| Server detection | `skills/verification-workflow/scripts/detect_server.sh` | Find running dev server on common ports | Stage 5 | Production |
| Unit test patterns | `skills/verification-workflow/references/unit-test-patterns.md` | Vitest/Jest/React Native test templates | Stage 3 | Reference |
| E2E patterns | `skills/verification-workflow/references/e2e-patterns.md` | Playwright test templates + discovery workflow | Stage 3, 5 | Reference |
| Spring Boot patterns | `skills/verification-workflow/references/spring-boot-patterns.md` | JUnit5/Mockito/TestContainers patterns | Stage 3 | Reference |
| Project journal skill | `skills/project-journal/SKILL.md` | Maintain project docs across sessions | N/A | Reference |
| Test suite | `tests/simple-test.sh` (600+ lines, 135 tests) | Config, schema, sanitization, preflight tests | N/A | Production |
| Config example | `templates/reqdrive.json.example` | Example configuration | Setup | Complete |
| Quick start guide | `docs/QUICKSTART.md` | User-facing setup + usage guide | N/A | Complete |
| Pipeline analysis | `docs/PIPELINE-ANALYSIS.md` | Technical deep-dive with critique | N/A | Complete |
| Marching orders | `docs/MARCHING_ORDERS_2026-02-09.md` | Phased improvement roadmap | N/A | Complete |
| Dev-pipeline skill | *Does not exist* | Was proposed but never built | Stage 1-6 | Missing |
| `reqdrive plan` command | Stub in `bin/reqdrive` | Standalone PRD generation | Stage 2 | Stub |
| `reqdrive orchestrate` command | Stub in `bin/reqdrive` | Multi-requirement sequencing | All | Stub |

---

## Stage-by-Stage Analysis

### Stage 1: CLARIFY

**Status: Exists as interactive skill, not wired into pipeline**

The `skills/prd/SKILL.md` defines a clarification workflow: 3-5 targeted questions with lettered options (e.g., "1A, 2C, 3B"), focusing on problem/goal, core functionality, scope boundaries, and success criteria. The `skills/design-to-prd/SKILL.md` adds a richer five-phase workflow for transforming design documents, including concept extraction, multi-document synthesis, and conflict resolution.

**What works:**
- The question format (lettered options) is well-designed for fast user iteration
- The PRD skill separates clarification from specification cleanly
- The design-to-prd skill handles diverse input types (wireframes, vision docs, meeting notes)

**What's missing:**
- Neither skill is callable from the automated pipeline. They're Claude Code interactive skills invoked via `/prd` or `/design-to-prd` — conversation patterns, not functions.
- No structured output format that an orchestrator could consume. The PRD skill saves to `tasks/prd-[name].md` (markdown), while the pipeline expects `.reqdrive/runs/<slug>/prd.json` (JSON). These are different formats in different locations.
- No programmatic way to determine when clarification is "complete enough" to proceed. The rubric exists in the skill but isn't encoded as machine-checkable criteria.

**What it would take to make this a callable stage:**
1. A `reqdrive clarify <REQ-ID>` command that launches an interactive Claude session using the PRD skill's question framework
2. The session would read the requirement file, ask clarifying questions, and write an enriched requirement back (or a separate `clarified.md`)
3. This is inherently interactive — the user must answer questions — so it can't be fully autonomous. But it could be optional: `reqdrive run` proceeds without it, `reqdrive run --clarify` triggers it first.

### Stage 2: SPECIFY

**Status: Implemented in pipeline (planning phase) + standalone skills**

The pipeline's Phase 1 (planning) implements this stage. `build_planning_prompt()` in `lib/run.sh:168-236` instructs Claude to read the requirement and produce `prd.json` with 3-8 user stories, each with ID, title, description, acceptance criteria, and priority. Schema validation enforces structure. Up to 2 retry attempts handle failed PRD generation.

**What works:**
- PRD JSON schema is well-defined and validated (`lib/schema.sh:validate_prd_schema`)
- The planning prompt is safely constructed (quoted heredoc `<<'PROMPT_PLAN'`)
- Retry logic prevents single-attempt failures from blocking the pipeline
- The PRD format is machine-parseable — downstream stages consume it via jq

**What's missing:**
- **No quality rubric for PRDs.** The schema validates structure (fields exist, types correct) but not content quality. A PRD with one story titled "Do everything" and no meaningful acceptance criteria would pass validation.
- **The prd skill's richer output format isn't used.** The interactive PRD skill generates markdown with goals, functional requirements, non-goals, technical considerations, and success metrics. The pipeline's prd.json captures only stories and acceptance criteria — a strict subset.
- **`priority` is not validated.** `lib/schema.sh` validates `id`, `title`, `acceptanceCriteria`, and optionally `passes`, but `priority` (used by `select_next_story` for sorting) is not type-checked. A non-numeric priority would produce undefined sorting behavior.
- **No handoff from Stage 1.** If a user runs the PRD skill interactively, the output (`tasks/prd-[name].md`) isn't in the format or location the pipeline expects. There's no bridge.

**What would improve this:**
1. Add `priority` to the schema validation (must be a number)
2. Add PRD quality checks: minimum story count, acceptance criteria must be non-empty strings, no duplicate story IDs
3. Consider enriching `prd.json` with fields from the PRD skill (goals, non-goals, technical considerations) — downstream prompts could use them for better context

### Stage 3: TEST

**Status: Not implemented. Reference material exists but no automation.**

The verification-workflow skill has reference patterns for writing tests (Vitest, Jest, Playwright, JUnit5/Mockito), and the SKILL.md describes a "Step 4a: Unit Tests from Requirements" workflow. But this is a Claude Code interactive skill — it requires a human to invoke `/verification-workflow` and a running implementation to test against.

**Critical gap: Tests are not written before implementation.** The pipeline goes straight from PRD to implementation. There is no stage where tests are generated from acceptance criteria and locked in *before* the implementation agent runs. This means:

1. The implementation agent writes its own tests (if any), which are definitionally not independent of the implementation
2. There's no objective quality ratchet — the agent decides what "passes" means
3. A lazy or confused agent can mark `passes: true` without tests actually existing or running

**Assessment of existing test patterns:**
- The unit test patterns (`references/unit-test-patterns.md`) are solid for component-level testing: React Testing Library, hook testing with `renderHook`, API mocking with `vi.fn()`. They include a "requirements mapping" section showing how to convert acceptance criteria text into test code.
- The E2E patterns (`references/e2e-patterns.md`) include a valuable "discovery pattern" for exploring unknown functionality with screenshots, plus a conversion guide for turning E2E observations into unit tests.
- The Spring Boot patterns cover unit (Mockito), integration (`@WebMvcTest`, `@DataJpaTest`), and full integration (`@SpringBootTest` + TestContainers).
- **Integration test gap:** For non-Spring Boot projects, there's no explicit integration test pattern. The gap between unit tests (isolated) and E2E tests (browser-based) is meaningful for API-heavy features.

**Can tests be generated from requirements without an implementation?**
Partially. Acceptance criteria like "Button shows confirmation dialog before deleting" can become E2E test stubs (navigate to page, find button, click, assert dialog appears). But for unit tests, you need to know the module structure — you can't write `import { useAuth } from './hooks/useAuth'` without knowing the implementation will create that file at that path.

**Realistic approach:** Generate E2E test skeletons and behavioral contract tests from acceptance criteria. These test *what* should happen, not *how* — they're implementation-independent. Unit tests should be generated after implementation (Stage 5) as a verification step, not as a pre-implementation gate.

### Stage 4: IMPLEMENT

**Status: Implemented and mature**

This is the strongest part of the pipeline. `lib/run.sh:618-684` implements the implementation loop with:
- Deterministic story selection via jq (`select_next_story`, line 332)
- Per-story prompt construction with sanitized PRD fields (lines 240-325)
- One Claude invocation per story with 30-minute timeout
- Checkpoint after each iteration for resumability
- Completion detection via jq (primary) and output grep (secondary)

**What works well:**
- Shell-controlled story ordering prevents agent cherry-picking
- Stateless invocations (fresh Claude session per story) prevent context window exhaustion
- Checkpoint/resume handles crashes and rate limits gracefully
- Signal traps (INT, TERM, HUP) mark interrupted runs properly

**What's missing:**
- **No worktree management.** All implementation happens on a single branch in the main working tree. The `archive/` directory suggests worktree support was explored in v0.1.x and removed during simplification. This prevents concurrent runs.
- **No commit verification.** After each Claude invocation, the pipeline doesn't check if a commit actually happened. It saves the checkpoint and moves on regardless.
- **No scope verification.** The pipeline doesn't diff what files changed to verify they're reasonable for the target story.
- **The implementation prompt has a known heredoc expansion issue** (documented in `docs/PIPELINE-ANALYSIS.md:210-227`). While PRD-derived fields are now sanitized (`lib/run.sh:254-257`), the sanitization was added as a fix — the underlying pattern (unquoted heredoc for variable expansion) remains fragile. A quoted heredoc with explicit variable injection (e.g., `sed` or `envsubst`) would be structurally safer.
- **No retry on story failure.** If the agent fails to implement a story, the pipeline moves to the next iteration and picks the same story again (because `passes` is still `false`). This is actually reasonable behavior — the next attempt gets fresh context. But there's no retry limit per story, so a permanently-failing story can consume all remaining iterations.

### Stage 5: VERIFY

**Status: Not implemented. Conceptual only.**

The pipeline has zero post-implementation verification. After each Claude invocation:
1. The raw output is saved to `iteration-N.log`
2. The iteration summary is extracted (agent's self-report)
3. The checkpoint is saved
4. The PRD schema is re-validated (warn-only)
5. That's it. No tests run, no commit check, no diff analysis.

The `testCommand` config field is auto-detected in `lib/init.sh` and stored in config, but `lib/run.sh` never reads or executes it. This is the most significant wasted asset in the codebase.

**Can the verification skill run autonomously and produce machine-parseable output?**
No. The verification-workflow SKILL.md describes a 6-step workflow but is designed for interactive Claude sessions, not programmatic invocation. It doesn't produce a machine-parseable result — it generates a markdown report with emoji checkmarks. The scripts (`detect_project.sh`, `detect_server.sh`) are automatable, but the test generation and analysis steps require Claude's judgment.

**What about the retry loop?**
It does not exist. The marching orders document (`docs/MARCHING_ORDERS_2026-02-09.md`) describes an "observe before enforce" approach: start with logged warnings (commit check, test run, scope check), graduate to checkpoint annotations, then promote to hard gates. This is sound advice that hasn't been acted on yet.

**The gap between "all tests pass" and "the feature actually works":**
This is the user's core concern, and it's a real one. Even with a robust test suite, bugs slip through because:
- Tests verify the implementation against itself (the agent wrote both)
- E2E tests can assert HTTP 200 without verifying the actual rendered content
- Visual/layout bugs are invisible to assertion-based testing
- Multi-step user flows may work step-by-step but fail in sequence (state management bugs)
- The agent may "pass" tests by weakening assertions or skipping edge cases

### Stage 6: SHIP

**Status: Partially implemented (PR creation). No feedback loop.**

`lib/pr-create.sh` handles:
- `git push -u origin $branch`
- Building a validation checklist from PRD acceptance criteria
- Creating a GitHub PR via `gh pr create` with structured body
- Retry without labels on failure (handles missing label edge case)
- Draft PR if stories are incomplete

**What works:**
- The validation checklist is directly derived from acceptance criteria — reviewers see exactly what to check
- The commit log is included for quick overview
- Draft PR support is graceful degradation

**What's missing:**
- **No CI status check.** The pipeline creates the PR and exits. It doesn't wait for CI, report results, or react to failures.
- **No feedback loop.** If a reviewer rejects the PR, there's no mechanism to feed rejection reasons back into the pipeline. The user would need to manually write new requirements and re-run.
- **No link to verification report.** When a verification step is eventually added, its results should be included in the PR body.
- **Validation instructions are human-only.** The checklist is checkbox markdown — useful for manual review but not for automated verification.

---

## Architecture Assessment

### Orchestration

**Current state:** The orchestrator is `lib/run.sh:run_pipeline()` — a linear function that executes planning, implementation loop, and PR creation sequentially. It works well for single-requirement, foreground runs.

**What's needed for overnight autonomous operation:**

The current architecture is actually close to sufficient for Tier 1 autonomous runs. The `launch` command already handles detached execution with `nohup`. The completion hook provides extensibility for notifications. What's missing is the verify-retry loop between implementation and PR creation.

**Recommended orchestrator evolution:**
1. **Keep Bash for the CLI and pipeline orchestration.** The current shell architecture is a strength — it's portable, has no runtime dependencies beyond bash/jq/git/gh, and the user runs it on both Windows/MSYS2 and Linux VPS. Rewriting in Node/Python would add dependency management overhead with no clear benefit.
2. **Add a `verify` phase between implementation and PR creation** in `run.sh`. This is a natural extension: after the implementation loop, run the test command, check results, optionally retry.
3. **Add `reqdrive plan` as a standalone PRD generator** (currently stubbed). This separates the expensive planning step from implementation, allowing user review of the PRD before committing to implementation.

### Artifact Flow

```
User-authored:
  docs/requirements/REQ-XX-name.md   →  run.sh (sanitized, embedded in prompts)
  reqdrive.json                       →  config.sh (parsed, exported as env vars)

Pipeline-generated:
  .reqdrive/runs/<slug>/prd.json     ←  Claude (planning phase)
                                      →  run.sh (story selection, implementation prompts)
                                      →  pr-create.sh (validation checklist)

  .reqdrive/runs/<slug>/checkpoint.json  ←  run.sh (after each iteration)
                                          →  run.sh (on --resume)

  .reqdrive/runs/<slug>/run.json     ←  run.sh (status tracking)
                                      →  bin/reqdrive status (display)

  .reqdrive/runs/<slug>/progress.txt ←  run.sh (init), Claude (append)
                                      →  Claude (context for next iteration)
```

**Format consistency:** Good. JSON for machine-parseable state (prd.json, checkpoint.json, run.json, iteration summaries). Markdown for human-readable context (progress.txt, prompts). Clear separation.

**Contracts:** The PRD JSON schema (`lib/schema.sh:validate_prd_schema`) is the main contract between planning and implementation. It's validated but could be stricter (missing `priority` type check, no story count bounds, no acceptance criteria content validation).

### State Management

The flat-file approach (JSON files in `.reqdrive/runs/<slug>/`) is appropriate for this use case:
- Each requirement gets its own directory (per-requirement isolation since v0.3.0)
- `run.json` tracks lifecycle with PID for liveness checking
- `checkpoint.json` enables resume at the right iteration
- Iteration logs provide full audit trail

**Gap: No commit SHA tracking.** Checkpoints record iteration number and completed stories but not git commit SHAs. If the repository state diverges from checkpoint state (manual intervention, failed push, etc.), resume will proceed from a potentially inconsistent state. Adding `last_commit_sha` to checkpoint.json would close this.

**Gap: No file locking.** Two concurrent `reqdrive run` commands targeting the same REQ-ID would race on shared files. The PID check in `launch` prevents double-launching, but there's no lock on the run directory itself.

### Parallelism

**Current state:** None. The `archive/` directory suggests worktree-based parallelism was explored in v0.1.x and removed during simplification. The per-requirement run directory structure (`runs/<slug>/`) is designed to support concurrent runs for different requirements, but the implementation operates on the main working tree, so only one requirement can run at a time.

**What would be needed:**
1. Git worktrees for branch isolation (`git worktree add`)
2. Working directory management (each Claude invocation runs in its worktree)
3. Merge conflict detection when worktrees are merged back
4. The `orchestrate` command (currently stubbed) would manage this

### Error Handling

Error handling is comprehensive for anticipated failures:
- 9 semantic exit codes with human-readable messages
- Signal traps for clean interrupt handling
- Completion hook fires on both success and failure
- PR creation retries without labels on first failure
- Planning retries up to 2 times on PRD generation failure
- Schema validation is warn-only in most contexts (doesn't block progress)

**Gap: No story-level retry limit.** A permanently-failing story will be selected every iteration until `maxIterations` is exhausted. Adding a per-story attempt counter (tracked in prd.json or checkpoint.json) with a max retry count would prevent this.

**Gap: No rollback.** If the agent makes bad commits, the only recovery is manual `git reset`. The marching orders document correctly advises deferring rollback until the observation layer provides data on failure patterns.

### Configurability

Good. The config schema supports different stacks via `testCommand` (auto-detected for Node, Python, Rust, Go), `model` (any Claude model), and `maxIterations`. All fields have sensible defaults — an empty `{}` config works.

**Gap:** The verification-workflow skill supports specific stacks (React/Next.js, Expo, Spring Boot) but the pipeline config doesn't have a `projectType` field. Adding one would let the pipeline invoke stack-specific verification automatically.

---

## The QA Gap (Deep Dive)

### Categories of Bugs That Slip Through Tests

| Category | Example | Agent-Written Tests Catch It? | Why Not |
|----------|---------|-------------------------------|---------|
| Visual/layout bugs | Button overlaps form field at mobile breakpoint | No | Tests assert DOM presence, not visual position |
| Wrong data displayed | Dashboard shows stale cached data after update | Unlikely | Agent tests the happy path with fresh data |
| Race conditions | Double-submit creates duplicate records | No | Agent tests sequential flows, not concurrent ones |
| Broken flows returning 200 | Login succeeds but redirects to wrong page | Unlikely | Agent tests login success, not post-login destination |
| Edge cases in real data | Unicode characters in username break layout | No | Agent uses `testUser123`, not `José García 🇲🇽` |
| Accessibility violations | Missing ARIA labels, broken tab order | No | Agent doesn't test accessibility unless explicitly required |
| Performance degradation | List view takes 8s with 10k records | No | Agent tests with 3 items |
| State management bugs | Back button shows inconsistent state | No | Agent tests forward flows, not navigation patterns |
| Integration seam failures | API returns different shape than frontend expects | Possibly | If agent tests both sides, yes; often only tests one |

### What Vision-Based QA Would Catch

**High confidence (Playwright + Claude vision would reliably catch):**
- Visual/layout bugs — Claude can see overlapping elements, broken layouts, missing content
- Wrong data displayed — Claude can read screen text and compare against expected values
- Broken flows returning 200 — Claude can follow the flow visually and notice wrong destinations
- State management bugs in multi-step flows — Claude can navigate sequences and notice inconsistencies

**Medium confidence (would sometimes catch):**
- Accessibility violations — Claude can identify missing labels, low contrast, small touch targets visually, but can't test screen reader behavior or keyboard navigation
- Edge cases in real data — Only if the test scenarios include edge case data. Claude would notice visual breakage but can't generate edge cases autonomously.

**Low confidence (unlikely to catch):**
- Race conditions — Timing-dependent, hard to reproduce visually
- Performance degradation — Claude can notice slow loading (via screenshot timing) but can't measure precise thresholds
- Integration seam failures — May manifest visually (error messages, empty states) but root cause identification requires code-level analysis

### Architecture for the Vision-Based QA Agent

```
┌─────────────────────────────────────────────────┐
│                  QA Orchestrator                 │
│  (Shell script, similar to run.sh)              │
├─────────────────────────────────────────────────┤
│                                                  │
│  Inputs:                                         │
│    - prd.json (acceptance criteria per story)    │
│    - Implementation branch (deployed/running)    │
│    - testCommand results (pass/fail)             │
│                                                  │
│  For each user story in prd.json:                │
│    1. Generate test scenario from AC             │
│    2. Execute scenario via Playwright            │
│    3. Capture screenshots at each step           │
│    4. Send screenshots + AC to Claude Vision     │
│    5. Claude evaluates: does screenshot          │
│       satisfy the acceptance criterion?          │
│    6. Collect results into verification report   │
│                                                  │
│  Output:                                         │
│    - verification-report.json                    │
│    - screenshots/ directory                      │
│    - Pass/fail per story, per criterion          │
│                                                  │
└─────────────────────────────────────────────────┘
```

**Control flow detail:**

1. **Scenario generation** (Claude text, not vision):
   - Input: acceptance criterion text, e.g., "Filter dropdown with options: All | High | Medium | Low"
   - Output: Playwright script steps: `goto('/tasks')`, `click('[data-testid=priority-filter]')`, `screenshot('filter-open.png')`, `click('High')`, `screenshot('filter-applied.png')`

2. **Scenario execution** (Playwright, no Claude):
   - Run the generated Playwright script against the dev server
   - Capture screenshots at each designated step
   - Log any Playwright errors (element not found, timeout, etc.)

3. **Visual evaluation** (Claude Vision API):
   - For each screenshot + criterion pair, send to Claude with prompt: "Does this screenshot show [criterion]? Respond with PASS, FAIL, or UNCLEAR with explanation."
   - Aggregate results per story

4. **Reporting:**
   ```json
   {
     "storyId": "US-002",
     "status": "fail",
     "criteria": [
       {
         "criterion": "Each task card shows colored priority badge",
         "status": "pass",
         "screenshot": "screenshots/us002-badges.png",
         "notes": "Red, yellow, and gray badges visible on task cards"
       },
       {
         "criterion": "Priority visible without hovering or clicking",
         "status": "fail",
         "screenshot": "screenshots/us002-visibility.png",
         "notes": "Badge only appears on hover, not visible by default"
       }
     ]
   }
   ```

5. **Integration with retry loop:**
   - If verification fails, feed the failure report back into a new implementation prompt
   - "Story US-002 failed verification. Issue: Priority badge only appears on hover. Fix: Make badge always visible. See screenshot at screenshots/us002-visibility.png."
   - Importantly, spin up a *new* Claude session (stateless) with the failure context, not a continuation

### Feasibility and Risks

**Feasible today:**
- Playwright browser control is mature and reliable
- Claude Vision API can evaluate screenshots against natural-language criteria
- The prd.json format provides structured acceptance criteria to drive test generation
- The overall architecture (generate scenario → execute → evaluate) is straightforward

**Risks and failure modes:**
1. **False positives** — Claude Vision may flag correct implementations as failures due to subjective visual interpretation. Mitigation: require FAIL + explanation, allow "UNCLEAR" as a non-blocking result.
2. **False negatives** — Claude Vision may approve broken implementations that look superficially correct. Mitigation: use multiple screenshots from different states (hover, click, type).
3. **Flaky browser state** — Dev servers may have inconsistent state between runs. Mitigation: seed database, clear caches, use deterministic test data.
4. **Scenario generation quality** — Claude may generate Playwright scripts that don't accurately test the criterion. Mitigation: use simple, well-structured acceptance criteria; provide Playwright pattern examples.
5. **Cost** — Vision API calls per screenshot per criterion could be expensive for many stories. Mitigation: batch screenshots, use haiku for simple pass/fail evaluations.
6. **Non-visual criteria** — Some acceptance criteria ("Typecheck passes") can't be evaluated visually. Mitigation: classify criteria as visual vs. programmatic and route accordingly.

**Minimum viable version:**
1. For each story marked `passes: true` in prd.json, run the `testCommand`
2. If tests fail, report which tests and mark the story for retry
3. Save test output to `iteration-N.test-results.txt`
4. This requires zero new infrastructure — just execute the existing `testCommand` config value

### Relationship to Existing Tests

Vision-based QA should **complement** assertion-based tests, not replace them:

```
Layer 1: Static analysis      (tsc, eslint)        — catches type errors, lint issues
Layer 2: Unit tests            (vitest/jest)        — catches logic errors in isolation
Layer 3: Integration tests     (API, database)      — catches seam failures
Layer 4: E2E assertion tests   (Playwright asserts) — catches flow breakage
Layer 5: Vision-based QA       (Playwright + Claude) — catches visual/UX issues
```

Each layer catches bugs the previous layers miss. Vision-based QA is the final gate after all programmatic tests pass. It answers: "Tests say it works, but does it actually look right?"

---

## Critical Issues (Must Fix Before Overnight Runs)

1. **`testCommand` is never executed by the shell.** The pipeline trusts the agent's self-report that tests pass. Wire up `testCommand` execution after each implementation iteration, even if initially warn-only. (`lib/run.sh`, after line 662)

2. **No commit verification after implementation iterations.** The pipeline doesn't check if a commit actually happened. Add `git log --oneline -1` check after each Claude invocation. If the most recent commit doesn't match the expected `feat: [US-XXX]` pattern, log a warning. (`lib/run.sh`, after line 662)

3. **No per-story retry limit.** A permanently-failing story consumes all remaining iterations. Add an attempt counter per story (in checkpoint.json or a map in prd.json) and skip stories that have failed N times. (`lib/run.sh:select_next_story`, `save_checkpoint`)

4. **`priority` field not schema-validated.** `select_next_story` sorts by priority, but `validate_prd_schema` doesn't check that priority is a number. A non-numeric priority produces undefined sort behavior. (`lib/schema.sh:validate_prd_schema`)

5. **Checkpoint doesn't track commit SHA.** Resume can proceed from inconsistent git state. Add `last_commit_sha` from `git rev-parse HEAD` to checkpoint.json and verify it on resume. (`lib/run.sh:save_checkpoint`, `load_checkpoint`)

---

## Tier 1 Recommendations (Build Now)

*Goal: `reqdrive launch REQ-01` produces a mergeable PR overnight, even if imperfectly.*

**1. Wire up `testCommand` execution (effort: 1-2 hours)**

After line 662 in `lib/run.sh` (after `extract_iteration_summary`), add:

```bash
if [ -n "${REQDRIVE_TEST_COMMAND:-}" ]; then
  log_info "Running test command: $REQDRIVE_TEST_COMMAND"
  if ! eval "$REQDRIVE_TEST_COMMAND" > "$agent_dir/iteration-$i.test.log" 2>&1; then
    log_warn "Tests failed after iteration $i (see iteration-$i.test.log)"
  fi
fi
```

Start warn-only. Promote to a hard gate after observing failure rates.

**2. Add post-iteration commit check (effort: 1 hour)**

After each Claude invocation, verify a commit happened:

```bash
local latest_commit
latest_commit=$(git log --oneline -1 --format='%s')
if [[ "$latest_commit" != feat:\ \[${next_story}\]* ]]; then
  log_warn "Expected commit for $next_story, latest commit is: $latest_commit"
fi
```

**3. Add `priority` schema validation (effort: 30 minutes)**

In `validate_prd_schema`, add a check that `priority` is a number for each story.

**4. Add per-story retry limit (effort: 1-2 hours)**

Track attempt count per story in the prd.json (add `attempts` field) or in the checkpoint. After 3 failed attempts at a story, skip it and move to the next priority.

**5. Add commit SHA to checkpoint (effort: 30 minutes)**

Record `git rev-parse HEAD` in checkpoint.json. On resume, verify the current HEAD matches. If not, warn (don't abort — the user may have intentionally amended).

**6. Implement `reqdrive plan` command (effort: 2-3 hours)**

Unwire Phase 1 into a standalone command: `reqdrive plan REQ-01` runs only the planning phase and exits. This lets users review the PRD before committing to implementation:

```
reqdrive plan REQ-01        # generates prd.json, exits
# User reviews prd.json, edits if needed
reqdrive run REQ-01         # detects existing prd.json, skips to implementation
```

---

## Tier 2 Recommendations (Build Next)

*Goal: The pipeline is trustworthy enough that you'd merge most PRs without extensive review.*

**1. Add a `verify` phase between implementation and PR creation (effort: 4-6 hours)**

After the implementation loop completes and before PR creation, add a verification phase:
- Run `testCommand` (full test suite, not just the story's tests)
- Run static analysis (`tsc --noEmit`, `eslint`, etc.) if project type is detected
- Generate a verification report (JSON) with test results, lint results, and story status
- Include the verification report in the PR body
- If critical failures: retry the last story, or mark PR as draft with failure notes

**2. Build the scope check (effort: 2-3 hours)**

After each implementation iteration, run `git diff --name-only HEAD~1` and log the changed files. Compare against a reasonable heuristic (e.g., files in `src/` are expected, files in `lib/` or config files may indicate scope creep). Start as logged observations.

**3. Enrich the PR body with verification data (effort: 2-3 hours)**

The current PR body has a human-operated validation checklist. Add:
- Test results section (test count, pass/fail, last run timestamp)
- Static analysis section (type errors, lint warnings)
- Story completion summary (which stories passed, which were skipped)
- Iteration log summary (how many iterations, any retries, any warnings)

**4. Add `reqdrive verify` command (effort: 4-6 hours)**

Standalone verification: `reqdrive verify REQ-01` runs the test suite, static analysis, and (optionally) E2E tests against the implementation branch. Produces a verification report. This could reuse the verification-workflow skill's detection scripts.

**5. Add per-story scope tracking to prd.json (effort: 2-3 hours)**

Extend prd.json stories with an optional `expectedFiles` or `scope` field that the planning phase generates. The implementation phase can then verify that the agent's changes are within scope.

**6. Heredoc structural fix (effort: 1-2 hours)**

Replace the unquoted heredoc in `build_implementation_prompt` with a quoted heredoc + explicit `sed` replacements for story variables. This eliminates the entire class of shell expansion bugs regardless of sanitization quality.

---

## Tier 3 Recommendations (Build Eventually)

*Goal: Full autonomous QA agent, multi-feature parallelism, self-improving pipeline.*

**1. Vision-based QA agent (Playwright-as-hands, Claude-as-eyes)**
Generate Playwright test scenarios from acceptance criteria, execute them, capture screenshots, evaluate with Claude Vision API. See "Architecture for the QA Agent" section above for detailed design.

**2. Multi-requirement parallelism via git worktrees**
Implement `reqdrive orchestrate` to run multiple requirements concurrently, each in its own worktree. Requires: worktree management, merge conflict detection, dependency ordering between requirements.

**3. Feedback loop from PR rejection**
When a PR is rejected (detected via `gh pr view --json state`), parse reviewer comments, generate a "fix requirements" document, and re-run the implementation phase targeting specific stories.

**4. Self-improving test suites**
After a bug is found manually that the pipeline missed, generate a regression test and add it to the project's test suite. Track which bugs escaped, categorize them, and adjust test generation strategies.

**5. Adaptive retry policies**
Track failure rates per story type, per project, and per model. Adjust `maxIterations`, retry limits, and model selection based on historical success rates.

**6. CI integration**
After PR creation, poll CI status via `gh pr checks`. If CI fails, parse the failure, create a fix iteration, push, and wait for CI again. Exit after N CI cycles.

**7. Cost tracking and budgets**
Track token usage per iteration (parse Claude billing info or estimate from output length). Set cost budgets per requirement. Alert when approaching budget limits.

---

## Suggested reqdrive CLI Design

### Proposed Commands (Evolution)

```
reqdrive init                  # Interactive setup (exists)
reqdrive validate              # Validate config (exists)
reqdrive plan <REQ-ID>         # Generate PRD only (Tier 1, currently stubbed)
reqdrive run <REQ-ID>          # Full pipeline (exists)
  --interactive                # Require permission prompts (default)
  --unsafe                     # Skip permission prompts
  --force                      # Skip preflight checks
  --resume                     # Resume from checkpoint
  --verify                     # NEW: Run verification after implementation
  --no-pr                      # NEW: Stop after implementation, don't create PR
reqdrive verify <REQ-ID>       # Standalone verification (Tier 2)
reqdrive launch <REQ-ID>       # Background run (exists)
reqdrive status [REQ-ID]       # Show run status (exists)
reqdrive logs <REQ-ID>         # Tail background output (exists)
reqdrive migrate               # Schema migration (exists)
reqdrive orchestrate           # Multi-requirement sequencing (Tier 3)
```

### Directory Structure (No Change Needed)

The current structure is well-designed:

```
project-root/
├── reqdrive.json                      # Configuration
├── docs/requirements/
│   └── REQ-01-feature-name.md         # Requirement documents
├── .reqdrive/
│   └── runs/
│       └── req-01/                    # Per-requirement isolation
│           ├── run.json               # Lifecycle status
│           ├── prd.json               # Generated PRD
│           ├── checkpoint.json        # Resume state
│           ├── progress.txt           # Agent progress log
│           ├── prompt.md              # Current prompt
│           ├── iteration-N.log        # Raw agent output
│           ├── iteration-N.summary.json # Structured summary
│           ├── iteration-N.test.log   # NEW: Test results per iteration
│           ├── verification-report.json # NEW: Tier 2 verification report
│           ├── output.log             # Background run stdout/stderr
│           └── screenshots/           # NEW: Tier 3 visual QA captures
```

### Config Format (Minimal Extension)

```json
{
  "version": "0.3.0",
  "requirementsDir": "docs/requirements",
  "testCommand": "npm test",
  "model": "claude-sonnet-4-20250514",
  "maxIterations": 10,
  "baseBranch": "main",
  "prLabels": ["agent-generated"],
  "projectName": "My Project",
  "completionHook": "",
  "maxStoryRetries": 3,
  "verifyAfterImplementation": false,
  "projectType": "nextjs"
}
```

New fields (all optional with defaults):
- `maxStoryRetries` (default: 3) — max attempts per story before skipping
- `verifyAfterImplementation` (default: false) — run testCommand after each iteration
- `projectType` (default: auto-detect) — used by verification for stack-specific checks
