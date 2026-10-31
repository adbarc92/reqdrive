# Design — Story-harness mode

**Date:** 2026-10-30
**Status:** The owner has ruled on Q1–Q3 (below). It passed three rounds of adversarial critique
on the seam design, and a fourth on the Rust implementation; all are logged at the end.

**Owner rulings, 2026-10-30:**

- **Q1:** Build it in Rust. It is a standalone story harness in a new cargo workspace, and the Bash
  tree is archived. It does not execute the factory M0/M1 plans and does not depend on
  `command-center`.
- **Q2:** The CLI with JSON lines, for now. The transport will be revisited later.
- **Q3:** The orchestrator opens PRs. v1 has one deliver route, a push. The `pr` field and the
  `github` and `forgejo-agit` routes (§2.1, §3.7.1) are not built.

§10 describes the Rust implementation. The following parts of §3 are written for Bash and are
replaced by §10: the emitter and `run_child` in §3.1, the shell pipeline in §3.6, the signal
mechanics in §3.7, the file list in §3.11, and the phases in §5. Everything else in §3 stands:
the work order, stages, Red and the freeze, the events, the outcome table, usage semantics, limits
semantics, policy, parallel-safety guarantees and permissions.
**Scope:** How reqdrive could run as a coding harness that an external orchestrator drives: one
story in, one pull request out. It covers a gap analysis against the orchestrator's provisional
seam, the parts of that seam that do not fit reqdrive, a design for a `story` mode, an assessment
of two transports, and a build order. The seam is the orchestrator's. This document proposes
changes to it and does not make them.

---

## 0. Summary

- reqdrive meets about a third of the seam today. Six gaps were expected going in, and five are
  real. The sixth, "preflight assumes a clean main checkout", is half wrong: preflight never
  requires `main`, but it does write to shared refs and pick a fixed branch name, and both break
  parallel runs. §1 also finds gaps that were not expected: stdout is not clean, and there are no limits
  except an iteration count and a fixed 30-minute timeout per call.
- Recommended shape: a new command, `reqdrive story <work-order.json>`, in a new `lib/story.sh`.
  Events go out as JSON lines on stdout, and human logs go to stderr. Story mode has its own short
  loop: **Red** (tests only), then **Green**, **Check** and **Deliver**. The shell owns every
  counter and makes every commit; the agent only edits files and runs the test command. It reuses
  reqdrive's sanitization and its safe prompt-template pattern, and adds its own `-p` agent call
  so that usage can be captured. It does not
  reuse the requirement-driven loop in `run.sh`, whose state the agent can edit (§3.3 says why).
- Three parts of the seam need a ruling before building (§2): who opens the PR on a forge that is
  not GitHub; what "local-only" inference means for a Claude Code harness; and how the seam reports
  usage that cannot be tied to a single call.
- Recommended transport: the CLI with JSON lines now. `harness-protocol` 0.1 has no field for
  acceptance criteria, base commit, inference policy, token limits or per-call usage. Its
  conformance kit also rejects any method outside the protocol, so a heartbeat cannot be added on
  the harness side alone (§4).
- Where it lands is the owner's call (§8, Q1). The Rust rebuild's plans have not started
  executing, and the first task of their M0 plan archives the Bash tree. Story mode in Bash is about
  10 days of work, including the test scaffolding the frozen suite requires, and gives the
  orchestrator a working harness now. Its event and result shapes are
  written to carry over to the Rust harness.

## 1. Measured starting state (gap analysis)

Measured on `origin/main` at `d341ec9`. Line numbers are from that commit.

### 1.1 Seam item by seam item

| Seam item | Today | Evidence |
|---|---|---|
| **One story in** | **No.** reqdrive takes a requirement document and has the agent plan 3–8 stories itself | Requirement found by file glob, `lib/run.sh:702-714`; planning phase `lib/run.sh:950-1005`; the prompt says "Target 3-8 user stories", `lib/run.sh:247` |
| **Take the criteria as given** | **No.** The agent writes the criteria, as plain strings with no ids, and may edit `prd.json` later | Criteria are `["..."]`, `lib/run.sh:237`; the implementer is told to "update priorities in prd.json", `lib/run.sh:366`; the schema only checks that criteria is an array, `lib/schema.sh:161-163` |
| **Every criterion maps to a test** | **No.** There is no link from criterion to test | Criteria are rendered as a PR checklist for humans, `lib/pr-create.sh:112-121` |
| **Tests first, published as a ref** | **No.** One agent call implements and commits together, and the only commit check is the message prefix | Implementation instructions, `lib/run.sh:339-348`; commit check on `feat: [ID]`, `lib/run.sh:1075-1082` |
| **Stop at the PR, no merge** | **Yes**, on GitHub. reqdrive never merges | `create_pr`, `lib/pr-create.sh:78-304`. After the PR, an optional review step edits the PR body, `lib/run.sh:1195`, `lib/pr-create.sh:69` |
| **Forge-neutral** | **No.** GitHub only, through `gh`, and `gh` is required even by commands that do not use it | `for tool in jq git gh`, `bin/reqdrive:26`; `gh pr create`, `lib/pr-create.sh:261-290`; `gh pr view`/`edit`, `lib/pr-create.sh:65,69,295` |
| **Work order: attempt id, workspace, repo, base commit, branch** | **No.** The branch is always `reqdrive/<slug>`. The base is a branch name. The workspace is found by walking up from the current directory | `lib/run.sh:689-691`; `lib/config.sh:11-29` |
| **Work order: failure evidence** | **No.** Context between calls is only `progress.txt` and git history, within one run | `lib/run.sh:341`, `lib/run.sh:922-928` |
| **Work order: inference policy** | **No.** Claude only, through the `claude` CLI. One `model` field | `claude` is hard-coded, `lib/run.sh:456-465`; `check_claude`, `bin/reqdrive:31-41`; `model`, `lib/config.sh:58-59` |
| **Work order: limits (turns, wall clock, tokens)** | **Partly.** There is an iteration cap and a per-story retry cap. Each call has a fixed 30-minute timeout. There is no turn, token or overall wall-clock limit | `maxIterations`, `lib/config.sh:61-62`; `timeout 1800`, `lib/run.sh:465`; `maxStoryRetries`, `lib/config.sh:75-76` |
| **Events streamed** | **No.** Logs are free text on stderr. Agent output is copied to stdout. State is a `run.json` file you have to poll | `log_*`, `lib/run.sh:15-17`; `… 2>&1 \| tee`, `lib/run.sh:465`; `write_run_status`, `lib/run.sh:24-84` |
| **`progress{stage}`** | **Partly.** Phases exist and are logged as text banners | `lib/run.sh:950-955`, `1011-1014`, `1126-1129` |
| **`heartbeat{waiting_on}`** | **No.** | Each call blocks silently for up to 30 minutes, `lib/run.sh:465` |
| **`usage{…}` per model call** | **No.** The CLI is run without `-p` in its default text form, so no usage leaves it. The decision log's reason for deferring this is now out of date (§1.3) | `lib/run.sh:456-465`; "The `claude` CLI does not surface per-invocation tokens", `CLAUDE.md:181-182` |
| **`error{category?, retryable}`** | **Partly.** Exit codes 0–8 are a category without a retry flag | `lib/errors.sh`; table at `CLAUDE.md:108-120` |
| **`artifact`** | **Partly.** Files are written to the run directory, but no event announces them | `CLAUDE.md:63-77` |
| **Result `{attempt_id, outcome, head_sha?, tests_defective?, failure?}`** | **Partly.** `run.json` has status, exit code and PR URL. It has no head SHA, no attempt id and no tests verdict. The captured PR URL has two lines (known drift INT-030) | `lib/run.sh:71-83`; `lib/pr-create.sh:95` echoes into the captured value at `lib/run.sh:1193`; `docs/canon/requirements/drift-report.md:69-71` |
| **The result is a claim** | **Yes, in spirit.** The draft gate already distrusts the agent's own report and requires `testCommand` to pass | `lib/run.sh:1176-1190`; `CLAUDE.md:272` |
| **Parallel-safe** | **No.** Details in §1.2 | — |

### 1.2 Parallel safety, item by item

One expected gap was "preflight assumes a clean main checkout and one branch per requirement". It
is half right.

- **Clean tree:** checked in whatever checkout the command runs in, not in `main`
  (`lib/preflight.sh:13-33`). In a fresh workspace this is correct and should stay.
- **Shared refs are written:** if the base branch is missing locally, preflight runs
  `git fetch origin "$base_branch:$base_branch"` (`lib/preflight.sh:72`). Worktrees share refs, so
  two instances race on the same local branch. git also refuses the fetch if that branch is checked
  out in another worktree.
- **Fixed branch name:** `reqdrive/<slug>` (`lib/run.sh:689`). Two attempts at one story collide.
  An existing branch is checked out and reused (`lib/run.sh:906-908`), so a second attempt would
  silently build on the first attempt's commits.
- **Config by walking up:** `reqdrive_find_manifest` climbs from the current directory to the
  filesystem root (`lib/config.sh:11-29`). A workspace nested under another project would pick up
  that project's `reqdrive.json`.
- **State inside the work tree:** `.reqdrive/runs/<slug>/` sits under the project root
  (`lib/run.sh:691`). It is untracked unless `init` added it to `.gitignore`, and `init` only asks
  (`lib/init.sh:81-90`). An agent that runs `git add -A` can commit it.
- **No lock on the run directory**, as documented (`CLAUDE.md:282`).
- **Remote named `origin`** is assumed by push and preflight (`lib/pr-create.sh:96`, which also
  sets an upstream with `-u`; `lib/preflight.sh:48,69`).
- **Interactive by default:** `run` starts with `REQDRIVE_INTERACTIVE=true` (`bin/reqdrive:92`) and
  prompts on a TTY (`bin/reqdrive:160`). An orchestrator has no TTY and must pass `--unsafe`.
- **Not global, and fine:** run state is per project, logs are per run, and the `launch` PID check
  is per requirement.

### 1.3 Facts checked outside this repository

Tool facts go stale, so each one is cited (§9).

1. **Per-call usage is available from the `claude` CLI.** `claude -p --output-format stream-json
   --verbose` emits one `assistant` message per step with a message `id` and `usage`. Steps that
   ran tools in parallel share an `id` and should be counted once. Input and cache counts on these
   messages are accurate. **Their `output_tokens` is a placeholder**, taken at `message_start`.
   The real per-response output count comes from the `message_delta` stream events, which only
   appear with `--include-partial-messages`, or from the result message's totals. The result
   message also carries `modelUsage` per model and `total_cost_usd`. Both are client-side
   estimates. [S-COST], [S-HEADLESS]
2. **Thinking tokens are not reported separately.** No field in the documented `usage` objects
   separates them, so `thinking` is unknown for this CLI. [S-COST]
3. **The result's `usage` leaves out subagent calls; `modelUsage` includes them.** If the agent
   starts subagents, a per-call ledger built from the main stream is incomplete. [S-COST]
4. **Limits.** `--max-turns` (print mode only) and `--max-budget-usd` (print mode only, an
   estimate) exist. There is no token-limit flag. [S-CLI]
5. **Non-interactive form and signals.** The documented way to run unattended is `-p`. reqdrive
   pipes a prompt into `claude` without `-p` (`lib/run.sh:465`), which the docs do not describe.
   From v2.1.302, a `-p` run with no permission mode set starts in Manual mode and denies anything
   that would prompt; the CLI on the author's machine is 2.1.296. SIGTERM ends a `-p` run with code
   143 and records no result for the turn in progress; SIGINT ends the turn first. [S-HEADLESS]
6. **Permission modes.** `acceptEdits` approves file edits and common filesystem commands
   (`mkdir`, `touch`, `mv`, `cp`). Other shell commands, `git commit` among them, need an
   `--allowedTools` entry; in `-p` anything left to prompt is denied. [S-HEADLESS]
7. **`--bare` hermeticity has a cost.** It skips user hooks, plugins, skills, MCP servers and
   CLAUDE.md, which is what a parallel harness wants. But it never reads OAuth credentials, so it
   cannot run on a subscription login and needs an API key or a cloud provider's credentials.
   [S-HEADLESS]
8. **Non-Claude models.** Claude Code can be pointed at a gateway with `ANTHROPIC_BASE_URL`, but
   Anthropic "doesn't support routing Claude Code to non-Claude models through any gateway".
   [S-GATEWAY] Ollama has offered an Anthropic-compatible API since v0.14.0 and documents running
   Claude Code against it [S-OLLAMA]. A Claude Code issue reports that setup hanging [S-HANG].
   A local-only policy therefore needs a second agent CLI, not a model flag.
9. **Forgejo can open a PR from a plain push** (AGit flow):
   `git push <remote> HEAD:refs/for/<base>/<topic> -o title=… -o description=…`. Multi-line
   descriptions must be base64-encoded. The `draft` option is ignored. The PR's head is a
   forge-managed ref, not a branch the harness names. [S-AGIT]
10. **`harness-protocol` on `command-center` `main` is version 0.1.** Its methods are
    `initialize`, `unit/start`, `unit/event`, `gate/request`, `unit/halt`, `unit/resume`,
    `unit/abandon` and `unit/result`, with no heartbeat. The conformance kit fails a harness that
    sends any other method (`UnknownMethod`). [S-PROTO]
11. **This repository's Rust-rebuild plans** (`docs/superpowers/plans/2026-10-04-factory-m0-foundations.md`,
    `…-m1-harness.md`) target protocol 0.2 at tag `contracts-v0.2.0`. No such tag exists in
    `command-center` today, and neither repository has a `factory/m0` branch, so execution has not
    started. The M1 plan's harness already has the shape this seam asks for: stages Provision, Red,
    Plan, Green, Check, Review, Deliver, and a test freeze before implementation.

## 2. Where the provisional seam does not fit reqdrive

Each of these needs the owner's ruling. Each has a proposed alternative. The design in §3 uses the
proposal and marks the places a different ruling would change.

**2.1 "One PR out" on a forge without `gh`.** reqdrive could add a Forgejo route: AGit push, or the
REST API with a token. Either way every harness would need forge credentials and forge-specific
code, and the orchestrator holds both already, because it merges.
*Proposal:* the harness's obligation becomes "one pushed attempt branch out, with its head SHA".
The PR is optional, and a work-order field `pr` chooses: `orchestrator` (the default: the harness
pushes only), `github` (a `gh` route), or `forgejo-agit`. This removes forge coupling from every
harness.

**2.2 Inference policy "local-only" for a Claude Code harness.** The supported routes for Claude
Code all reach Claude: Anthropic, a cloud provider, or a gateway in front of them (§1.3 item 8). An
Ollama endpoint works in practice but is unsupported and has a reported hang.
*Proposal:* reqdrive declares which policies it can satisfy. Given one it cannot satisfy, it refuses
at once with `error{category:"policy_unsatisfiable", retryable:false}` and a `failed` result, and
spends nothing. Local-only support comes later through an agent-adapter seam (§3.8). The rebuild's
plans already name OpenCode for that role.

**2.3 "One usage row per model call" when some calls cannot be tied to a call.** Subagent calls and
the CLI's own helper calls show up in `modelUsage` but not as main-loop messages (§1.3 item 3).
*Proposal:* story mode turns off the tools that start subagents (`Agent` and `Skill`, since a
forked skill also runs as a subagent), so the main stream covers the agent's own calls. The CLI's
helper calls remain, and they are what the residue rows below are for. At the end of each agent call, reqdrive compares the sum of its rows with `modelUsage` per
model. It emits any difference as one extra `usage` row per model, with `call_seq: null` and
`attributed: false`. The alternative, dropping the difference, under-reports spend.

**2.4 Smaller points the seam leaves open.** Each appears as a question in §8.

- Does the harness wait for the orchestrator to confirm "red" before implementing? A CLI transport
  has no channel back. The proposal is no: the orchestrator checks in parallel and kills the attempt
  if the tests are not red.
- What does `tests_defective` claim? Proposed reading: during implementation, the agent concluded
  that a frozen test contradicts its criterion. The harness stops instead of editing the test.
- The `outcome` values. Proposed: `pr_open` (or `pushed`, under 2.1), `no_change`, `failed`, and
  `halted` (a limit or a signal).
- `usage.prompt` and cache writes. Proposed: `prompt` = input + cache-creation + cache-read tokens,
  and `cached_prompt` = cache-read. A `cache_write` field is worth adding, because cache writes are
  priced differently.
- The work order names a base commit. Opening a PR needs a base **branch** as well, so the
  work order should carry both. Protocol 0.1's `Repo` already has `base_branch`.

## 3. Design: `reqdrive story`

### 3.1 Shape, and the one event writer

```
reqdrive story <work-order.json>
  stdout: events, one JSON object per line; the last line is the result
  stderr: human logs, in today's format
  exit:   0 once a result line has been written, whatever the outcome; non-zero only if the
          event writer itself failed, so that no result could be written
```

**One writer owns stdout.** At entry, `story` saves the real stdout as file descriptor 3 and points
its own stdout at stderr (`exec 3>&1 1>&2`). It then starts the **emitter**, a single jq process,
behind a process substitution on file descriptor 4:

```
exec 4> >(jq -nRc --unbuffered --arg aid "$attempt_id" \
  'foreach (inputs | fromjson? // empty | select(type == "object")) as $e (0; .+1;
     $e + {v:1, attempt_id:$aid, seq:., ts:(now|todate)})' \
  | tee -a "$state_dir/events.jsonl" >&3)
emitter_pid=$!
trap '' PIPE
```

**How producers write:**

- Every producer writes one event body as one line to fd 4 with one `printf`. Producers are the
  main shell, the heartbeat loop and the usage parser (§3.6).
- Bodies are kept under 4 KB, the size below which a pipe write is atomic, so lines from different
  producers never interleave.

**What the emitter guarantees:**

- Only the emitter adds `seq` and `ts`, so numbering is total and ordered.
- The envelope is added last, so a body cannot overwrite `seq` or `attempt_id`.
- `fromjson? // empty` and the object filter drop a malformed or non-object line instead of ending
  the stream.
- With SIGPIPE ignored, a write to a dead emitter fails visibly instead of killing the shell, and
  that failure is the one case that ends with a non-zero exit.
- `events.jsonl` in the state directory is a durable copy.

**Every child starts through one helper,** `run_child`, which runs
`( trap - PIPE; exec "$@" ) 3>&- 4>&-`. It covers the agent, `test_command`, git and `gh`. The
helper does two things:

- **It closes fd 3 and fd 4.** Otherwise a test the agent wrote could print a forged event or
  result straight to the orchestrator. A leftover background process, such as a dev server, would
  also hold the pipe open, so the orchestrator would never see end-of-file.
- **It restores SIGPIPE before `exec`.** An ignored signal is inherited across `exec`, and a child
  bash cannot undo it. Without the reset, `yes | head -1` inside a test script exits 1 with
  "Broken pipe" instead of 141, and an endless producer piped into `head` never stops.

**Exactly one result, and it is last.** Stages and traps never write the result. They set
`pending_result` (outcome, category, detail) and exit. Only the `EXIT` trap writes the result, in
this order:

1. It stops the heartbeat loop and the current agent pipeline, each by its recorded PID, and waits
   for them. Every other holder of fd 4 must be gone before the result is written, or a late
   heartbeat could follow it.
2. It writes the result from `pending_result`. If nothing set it (a `set -e` abort, or any path
   that calls `exit`), it writes `failed`, category `harness_error`.
3. It closes fd 4 and runs `wait "$emitter_pid"`, so the emitter drains.

The `run` pipeline and every existing file format are left as they are. The changes to shared
files are listed in §3.11.

### 3.2 The work order, as reqdrive reads it

```json
{
  "schema": "story-work-order/0",
  "attempt_id": "a-7f3c",
  "story": {
    "id": "S-12",
    "title": "…",
    "description": "…",
    "acceptance_criteria": [{"id": "AC-1", "text": "…"}, {"id": "AC-2", "text": "…"}]
  },
  "workspace": "/abs/path/to/worktree",
  "state_dir": "/abs/path/outside/the/worktree",
  "repo": {"remote": "origin", "url": "…"},
  "base_commit": "<40-hex sha>",
  "base_branch": "main",
  "attempt_branch": "attempt/S-12/a-7f3c",
  "tests_ref": "refs/heads/attempt/S-12/a-7f3c.tests",
  "failure_evidence": [{"attempt_id": "a-11aa", "summary": "…", "detail": "…"}],
  "inference": {"allow": [{"provider": "anthropic", "models": ["claude-sonnet-5-5"]}]},
  "limits": {"turns": 200, "wall_clock_secs": 3600, "tokens": 4000000},
  "test_command": "npm test",
  "test_paths": ["test/"],
  "frozen_paths": ["package.json", "jest.config.js"],
  "isolation": "container",
  "agent_allow": ["Bash(npm run typecheck)"],
  "pr": "orchestrator"
}
```

The fields from `state_dir` onward, apart from the seam's own, are reqdrive's additions:

- **`state_dir`** is required. The orchestrator owns its lifetime, so evidence outlives
  `git worktree remove`. It must be outside the workspace.
- **`base_branch`** is needed only when `pr` opens a PR (§2.4).
- **`test_command`** is required, because Red and Check cannot run without one. It may come from
  `<workspace>/reqdrive.json` instead.
- **`test_paths`** and **`frozen_paths`** feed §3.4. Both are path prefixes, in `lib/policy.sh`'s
  prefix semantics.
- **`isolation`** and **`agent_allow`** set the agent's permissions (§3.9).
- **`pr`** is §2.1.

**Validation, before anything is spent:**

- The shape, checked with jq, and that criterion ids are unique.
- `base_commit` exists locally, checked first so that a missing commit is reported as
  `base_missing`.
- `workspace` is a git work tree, `HEAD` is `base_commit`, and `git status --porcelain` is empty,
  untracked files included. A dirty tree would be carried onto the new branch and then wiped by the
  first post-test reset. The commit is not fetched (it is
  not fetched).
- `state_dir` is empty, writable and outside the workspace. The empty requirement makes each work
  order run once. Re-running one would append to `events.jsonl`, restart `seq`, and count old
  usage against the token limit. A retry is a new attempt, with a new id, branch, tests ref and
  state directory (§3.5.1).
- The inference policy is one reqdrive can satisfy.
- Any failure here produces `error` + a `failed` result, and no agent call.

**Sanitization.** Story text and failure evidence are untrusted. They go through
`sanitize_for_prompt`, and failure evidence is capped at 8 KB per attempt. They are inserted into a
quoted template with `@@TOKEN@@` substitution, exactly as `build_implementation_prompt` does
(`lib/run.sh:287-405`): `@@` is stripped from values first, and the `\$` escaping is reversed. The
sanitizer also turns backticks into quotes. That mangles code in failure logs, and is accepted as
the price of injection defence. `validate_requirement_content` runs over the same text in its
default warn-only form (`lib/sanitize.sh:79-109`), and its warnings become `log` events, as in
`run`. It does not block, consistent with "warn before enforce".

**Config.** In priority order: the work order, then `<workspace>/reqdrive.json` only, then the
defaults. There is no walk-up.

### 3.3 Stages, and why story mode has its own loop

| Stage (`progress.stage`) | What happens |
|---|---|
| `validate` | §3.2 |
| `provision` | Creates `attempt_branch` at `base_commit` with `git -C "$ws" switch -c`, or accepts it if it already points at `base_commit` with a clean tree. Refuses an existing branch at any other commit (`branch_conflict`). Runs `test_command` at the base and requires it to pass (`base_broken` if not), so a broken environment is caught before any agent spend and a later red failure means something |
| `red` | One agent call writes tests. The shell commits them and checks them (§3.4) |
| `red_published` | The shell pushes the red commit: `git push <remote> <red_sha>:<tests_ref>` |
| `green` | Up to N agent calls (default 5, and always bounded by `limits`). After each call the shell commits any change, runs the freeze check, then runs `test_command`. It stops on the first pass. A call that changes nothing is logged and counted, and the tests are not re-run |
| `check` | `test_command` once more at a clean `HEAD`, recorded as evidence |
| `deliver` | `git push <remote> <head_sha>:refs/heads/<attempt_branch>`, with an explicit refspec and no `-u`. Then a PR only if `pr` asks (§3.7.1). The branch is pushed on failure and on halt too, as evidence, but no PR is opened |
| `done` | The result (§3.10) |

**The loop is new, not `run.sh`'s.** `run_pipeline`'s loop takes its stop condition and its story
text from `prd.json`. The agent can edit that file:

- `passes` ends the loop: `select_next_story` (`lib/run.sh:1028-1033`).
- `attempts` is the retry cap: `lib/run.sh:423-428`.
- The prompt is built from `prd.json`'s copy of the story: `lib/run.sh:1036-1043`.
- It never stops because tests passed; `lib/run.sh:1062` only counts the result.

Story mode needs the opposite: criteria the agent cannot touch, and a stop condition the shell
observes. So `lib/story.sh` has its own short loop. The shell holds every counter and the
work-order copy of the story, and it ignores anything the agent writes about its own progress
except the `testsDefective` claim. Shared with `run` are `sanitize.sh` and the template pattern.
The agent call is story mode's own `-p` invocation (§3.6, §3.8). `run_pipeline` is not touched.

**The shell makes every commit.** Under the default permissions the agent cannot run `git commit`
(§1.3 item 6), and should not need to. After each agent call the shell stages everything with
`git add -A` and checks the staged paths (`git diff --cached --name-only`) **before** it commits:

- **A denied path is staged:** the shell saves the staged diff as a patch in `state_dir`, runs
  `git reset --hard HEAD` and `git clean -fd`, and ends with `scope_violation`. A commit that
  touches a denied path is never made, so it can never be pushed.
- **Otherwise:** it commits, if anything changed:
  - `test: [<story>] failing tests for <ids>` for Red;
  - `feat: [<story>] green <n>` for Green.

The freeze check (§3.4) also reads the staged paths, so it is decided before the commit too.

Four rules keep those commits clean and keep them from failing:

- **Test byproducts are kept out.** Every test run, the shell's and the agent's, runs with
  `CI=true`. That is the common signal for test runners not to write snapshots, and the shell also
  passes it to the agent's environment. After each test run of its own, the shell resets the tree
  to the last commit with `git checkout -- .` and `git clean -fd`, so nothing that run wrote reaches
  the next commit. The order is: agent call, stage, check, commit, then test run, then reset, so
  the reset never touches uncommitted work by the agent. The clean respects `.gitignore`, so
  installed dependencies survive. A test run that writes byproducts which are not gitignored is a
  property of the target repository; this is part of question Q11.
- **Identity and hooks are fixed.** Commits use
  `git -c user.name=reqdrive -c user.email=<configurable> -c commit.gpgsign=false commit --no-verify`,
  and pushes use `--no-verify`. A fresh container has no identity. A repository's pre-commit or
  pre-push hook would reject the deliberately red tests commit. The orchestrator, not the harness,
  runs the checks that matter. This bypass is question Q14.
- **Some paths are always denied.** Red and Green may never change `.github/`, `.forgejo/`,
  `.gitea/`, `.gitlab-ci.yml`, `.husky/`, `.claude/`, `.mcp.json` or `.gitmodules`. A violation is
  `scope_violation`. A pushed workflow file would run in CI, and a `.claude/` or `.mcp.json` file
  would load into the next agent call (§3.9).
  The work order can add paths to this list.
- **The agent's prompts say not to run git.**

Story mode keeps no state files in the workspace. The context that `progress.txt` carries in `run`
goes into each Green prompt directly, from the shell:

- the frozen test list;
- the tail of the last test run;
- the failure evidence;
- a few shell-written lines on earlier Green calls.

### 3.4 Red, and the test freeze

The **Red prompt** tells the agent:

- write or change tests only, one or more per criterion;
- put the criterion id in each test's name or in a comment beside it;
- do not touch other files and do not run git;
- print a `json:criteria-map` block (`{"AC-1": ["test name", …]}`), which is its claim.

The **shell then commits and checks**:

1. Something changed.
2. Every changed path is under `test_paths` or `frozen_paths`. If `test_paths` is not set, this
   check only warns.
3. Every criterion id appears as a whole word in the commit's added lines
   (`git diff -U0 base..red | grep -wF -- "<id>"`). Whole-word matching stops `AC-10` satisfying
   `AC-1`. This is the mechanical criterion-to-test map. The agent's map is recorded as an artifact
   and not trusted.
4. `test_command` fails at the red commit with an ordinary test failure: a non-zero exit other
   than 126 or 127 ("cannot run" and "not found"). Because `provision` proved the suite passes at
   the base, a failure here is caused by the new tests. It may still be a compile error in them
   rather than a failing assertion, which the harness cannot tell apart. This is reported as
   `red_observed`; the orchestrator re-checks it.

Red has a budget of two attempts in total. After a failed attempt, the branch is reset to
`base_commit`, and the next attempt gets that attempt's failures appended to its prompt. If the last
attempt fails, its own failure gives the outcome (§3.5.1):

- **1–3 failed:** `red_invalid`.
- **4 failed because the tests pass at the red commit:** `red_not_failing`. Either the new tests do
  not exercise new behaviour, or the story is already satisfied.
- **The test command exits 126 or 127:** `harness_error`.

**The freeze.** After every Green call, the shell checks the staged Green change before it commits
(§3.3), using `git diff --cached --name-only <red>`. That change covers everything since the red
commit. It must not touch:

- any file the red commit touched;
- any path under `test_paths`;
- any path under `frozen_paths`, where the orchestrator lists runner configuration such as the test
  script's manifest and the test framework's config.

A violation means `failed`, category `tests_modified`.

If the agent's final text carries `"testsDefective": {"test": …, "reason": …}` and the tests did
not pass after that call, Green stops and the result says `tests_defective: true`, with the reason
in `failure`. If the tests passed, what the shell observed wins: the claim is recorded as a `log`
event and delivery goes ahead.

**What the freeze cannot catch.** An edit to a runner file the orchestrator did not list, such as a
setup file that registers skips, still slips through. The harness's check narrows that gap and does
not close it. The orchestrator should run the frozen tests with its own command, as the seam's
"never trusted" rule already implies.

**Why these checks are hard gates, given "warn before enforce".** That rule exists so that reqdrive
does not enforce a check before data shows what it catches. These checks are the seam's own rules,
and the orchestrator rejects their violation anyway. Failing in the harness only fails sooner and
spends less. The one check with no such backing, `test_paths` without config, stays a warning.

### 3.5 Events

The emitter adds the envelope `{"v":1,"attempt_id":…,"seq":n,"ts":"<RFC 3339>"}`. Producers
write only the body.

| `type` | Fields | When |
|---|---|---|
| `progress` | `stage` | Each stage in §3.3 begins |
| `heartbeat` | `waiting_on`: `agent`, `tests`, `push` or `forge` | Every 30 s while a child runs |
| `usage` | `call_seq`, `model_id`, `provider`, `prompt`, `cached_prompt`, `cache_write`, `output`, `thinking`, `attributed` | One per API response (§3.6) |
| `log` | `stream` (`agent`, `test`, `system`), `line` | Selected lines only, such as warnings and test tails. Full logs are files, announced by `artifact` |
| `artifact` | `kind` (`tests_ref`, `branch`, `pr`, `criteria_map`, `log_file`), `ref`, `sha?` | When produced |
| `error` | `category?`, `retryable`, `detail` | Each failure, fatal or not |
| `result` | §3.10 | Once, last |

**Unknown is `null`, never 0.** Producers build every body with `jq -nc` and `--argjson`, from a
value that is either a number read from the CLI or the literal `null`. A test asserts that a fixture
with the counts missing yields `null`.

#### 3.5.1 Outcomes and categories, by stage

This is the one place that says which condition produces which result. `pushed` means the branch
was delivered without a PR, which is the default route (`pr: "orchestrator"`). `pr_open` means a PR
was also opened. Two categories never end an attempt, `usage_incomplete` and `forge_failed`; both
are emitted as non-fatal `error` events.

**"Retryable"** means that a new attempt may succeed, with a fresh `attempt_id`, branch, tests ref
and `state_dir`. It never means re-running the same work order, which validation refuses (§3.2).

| Stage | Condition | Outcome | Category | Retryable |
|---|---|---|---|---|
| `validate` | `base_commit` is absent locally (checked first) | `failed` | `base_missing` | yes |
| `validate` | The work order is malformed, `HEAD` ≠ `base_commit`, the tree is not clean, or `state_dir` is not empty and writable | `failed` | `work_order_invalid` | no |
| `validate` | The inference policy cannot be satisfied | `failed` | `policy_unsatisfiable` | no |
| `provision` | `attempt_branch` exists at another commit | `failed` | `branch_conflict` | no |
| `provision` | `test_command` fails at the base | `failed` | `base_broken` | no |
| `red` | The last attempt fails checks 1–3 | `failed` | `red_invalid` | yes |
| `red` | The tests pass at the red commit | `no_change` | `red_not_failing` | no |
| `red`, `green`, `check` | The test command exits 126 or 127 | `failed` | `harness_error` | yes |
| `red`, `green` | A denied path is changed | `failed` | `scope_violation` | yes |
| `red_published`, `deliver` | A push fails | `failed` | `push_failed` | yes |
| `green` | The freeze is broken | `failed` | `tests_modified` | yes |
| `green` | `testsDefective` is claimed and the tests did not pass | `failed` | `tests_defective` | no |
| `green` | N calls were made without a pass | `failed` | `tests_failed` | yes |
| `red`, `green` | The agent CLI exits non-zero, other than at max turns, a limit or a signal | `failed` | `agent_error` | yes |
| any | Turns, tokens or wall clock are exhausted (including the CLI stopping at `--max-turns`) | `halted` | `limit_reached` | no |
| any | INT, TERM or HUP | `halted` | `interrupted` | yes |
| `check` | Tests fail at a clean `HEAD` after Green passed | `failed` | `tests_failed` | yes |
| `deliver` | The PR route fails after a successful push | `pushed` | `forge_failed` (non-fatal) | yes |
| `deliver` | Success | `pushed` or `pr_open` | — | — |
| any | An unexpected abort (the EXIT trap) | `failed` | `harness_error` | yes |
| any | A call's usage could not be reconciled (§3.6) | (none) | `usage_incomplete` (non-fatal) | — |

### 3.6 Usage capture

Each agent call is one background pipeline:

```
{ timeout -s INT -k 30 <remaining> claude -p --output-format stream-json --verbose \
    --include-partial-messages --model <m> --max-turns <remaining> --disallowedTools Agent,Skill \
    <permission flags> < prompt 3>&- 4>&- &
  echo $! > "$state/call-<n>.pid"; wait $! && rc=0 || rc=$?; echo "$rc" > "$state/call-<n>.rc"; } \
  | tee "$state/call-<n>.jsonl" \
  | jq -nRc --unbuffered --argjson base <next call_seq> -f usage.jq >&4 &
pipeline_pid=$!
```

- The PID that signals go to is `timeout`'s, which is written to `call-<n>.pid`. The `$!` of the
  whole pipeline is its last element, the usage parser, and is used only to wait for the pipeline
  to finish.
- The exit code goes to a file, because a background pipeline's `$?` is the last command's. The
  group runs as a subshell that inherits `set -e`, so a bare `wait $!` with a non-zero result would
  end the group before the file is written. `wait $! && rc=0 || rc=$?` keeps it alive, and a P1
  test has the fake agent exit 1.
- In this sketch every command is started through `run_child` (§3.1); it is left out to keep the
  sketch readable.
- Before a child starts, a remaining wall-clock budget of zero or less is treated as
  `limit_reached`, and so is a turn budget of zero before an agent call. Only agent calls spend
  turns, so the test runs and pushes after the last call still happen. `timeout 0` and
  `--max-turns 0` must never be passed, because `timeout 0` disables the timeout.
- `usage.jq` reads each line with `fromjson? // empty`, so a non-JSON line is skipped instead of
  ending jq (and killing `tee` and the CLI with SIGPIPE).
- In a `foreach`, it pairs each `message_start` with its `message_delta`. The first gives the model
  and the input and cache counts; the second gives the output count. It emits one `usage` body per
  pair.
- At the `result` message, it compares its rows with `modelUsage` and emits residue rows (§2.3).
- If the call ended without a `result` message (killed, or crashed), the reconciliation cannot
  run, and the shell emits `error{category:"usage_incomplete"}`.

`provider` is not reported by the CLI. reqdrive writes it from its own launch environment:
`anthropic`, `bedrock`, `vertex`, `foundry`, or `gateway:<host>` when `ANTHROPIC_BASE_URL` is set.
`thinking` is always `null` (§1.3 item 2). The final text the shell needs (the criteria map and the
`testsDefective` claim) is the `result` message's `result` field, read from `call-<n>.jsonl`
afterwards.

The jq filter is written against a recorded stream, not against the docs alone. Spike S1 (§5)
records one.

### 3.7 Limits, heartbeat and signals

- **Turns:** each call gets `--max-turns` set to the remaining budget, which is lowered by the
  turn count in each `result`. The field path is confirmed in S1.
- **Wall clock:** a deadline is set at `validate`. Each child gets `timeout -s INT -k 30` with the
  remaining time, instead of the fixed 1800. SIGINT is used rather than TERM so that the CLI ends
  its turn and writes its result (§1.3 item 5).
- **Tokens:** the heartbeat loop is a background subshell that writes a `heartbeat` every 30 s.
  Each time, it also sums the `usage` rows in `events.jsonl`. When the sum passes `limits.tokens`,
  it sends SIGINT to the PID in `call-<n>.pid`, and after a grace period, KILL. The sum counts
  uncached input, cache writes and output, so `prompt − cached_prompt + output`. It leaves out cache
  reads: every turn re-reads the whole context, so cache reads grow with turns × context size, and a
  limit that included them would trip early in any long call. Which counts the seam's token limit
  means is question Q8.
- **Any limit reached:** `error{category:"limit_reached", retryable:false}`, outcome `halted`, and
  the branch is pushed so the orchestrator can inspect it.

`--max-budget-usd` is not used, because it is an estimate in dollars and the seam's limit is in
tokens.

**Signals.** Bash runs a trap only after a foreground child exits, so every child runs in the
background, and the shell waits for it.

- **Waiting:** a trapped signal makes `wait` return early with a code above 128 while the child is
  still running. So the wait is a loop: `while kill -0 "$pid" 2>/dev/null; do wait "$pid" || rc=$?;
  done`.
- **The traps:** the INT, TERM and HUP traps send SIGINT to the PID in `call-<n>.pid` (or to the
  test or git child), wait a grace period, send KILL, set `pending_result` to `halted` and
  `interrupted`, and exit. The EXIT trap then writes it (§3.1). In the Rust build the grace applies
  to the process-group leader: once the leader exits after an interrupt, the whole group is killed
  at once (§10.2).
- **Telling a limit from an interruption:** a token-limit SIGINT and an outside SIGINT look alike
  to the child. So before signalling, the watchdog writes `<state_dir>/limit_hit`. When it exists,
  the stage sets `pending_result` to `halted` and `limit_reached`.
- **What P6 verifies:** a non-interactive bash starts background jobs with SIGINT ignored. GNU
  `timeout` installs its own handler and passes a signal it receives on to its command. Two things
  are verified in P6, on Linux first because MSYS2's signal handling is weaker (`CLAUDE.md:274`):
  - that `timeout` receives and forwards SIGINT when it was started in the background;
  - that the CLI under it then ends its turn.
- **Fallback:** if either fails, it is TERM then KILL, with `usage_incomplete`.
- **`set -e`:** `wait` on a killed heartbeat loop is `wait … || true`, so `set -e` does not abort.

#### 3.7.1 Deliver routes

| `pr` | What Deliver does |
|---|---|
| `orchestrator` | Pushes the branch only |
| `github` | Pushes the branch, then `gh pr create --base <base_branch> --head <attempt_branch>`, with the title and body built from the work order and not from any file the agent can write. `create_pr` is not reused: it pushes to `origin` with `-u`, builds its body from `prd.json`, and leaks a line into its captured URL |
| `forgejo-agit` | `git push <remote> <head>:refs/for/<base_branch>/<attempt_id>` with base64 `-o description` |

`bin/reqdrive:26` stops requiring `gh` at startup and checks for it only where it is used.

### 3.8 Inference policy and the agent seam

Story mode calls the agent through `run_agent_call <adapter> …`. Its only adapter, `claude-code`,
is the §3.6 invocation, and it stays the only one until the owner rules on §2.2. `run`'s
`run_claude_iteration` is left alone.

- **What `claude-code` can satisfy:** any `allow` entry whose provider is `anthropic`, `bedrock`,
  `vertex`, `foundry` or a named gateway, with only Claude models.
- **Environment:** reqdrive sets the environment for the chosen entry and clears the provider
  variables of entries it did not choose.
- **Auditing:** usage rows let the orchestrator check afterwards that every `model_id` was allowed.
  This matters because the CLI makes some helper calls with a smaller model, and those show up in
  `modelUsage` too.

### 3.9 Parallel safety and permissions

What reqdrive guarantees about **its own** writes:

- Its state lives in `state_dir`, never in the workspace or a shared git directory.
- The only refs it writes are `attempt_branch` and `tests_ref`, both unique to the attempt. It does
  not fetch into local branches, and it does not use `push -u`, so it never writes the shared
  `.git/config`.
- Every git command runs as `git -C "$workspace"`, and the agent's working directory is the
  workspace. Story mode never runs `cd`, `checkout` or `switch` outside it.
- Pushes go to the work order's remote, so `origin` is not assumed. Config is not looked up by
  walking up the directory tree.

What it **cannot** guarantee: worktrees share the object store, refs, hooks and config. An agent
running with `bypassPermissions` can write any of them, and so can a test command. Isolating the
agent is the orchestrator's job (a container per attempt), and reqdrive states this assumption
rather than claiming more.

**Permissions** follow from that:

- **`isolation: "container"`:** `--permission-mode bypassPermissions`.
- **Otherwise:** `--permission-mode acceptEdits`, plus
  `--allowedTools "Bash(<test_command>),Bash(<test_command> *)"` and whatever `agent_allow` lists.
  The prefix form lets the agent run a single test file. The agent then cannot write `.git` (a
  protected path) or run git, which story mode does not need it to (§3.3).

**What the CLI loads, and how long it stays.**

- **User level:** parallel CLI runs share the user's `~/.claude`. Without `--bare`, each call loads
  the user's hooks and plugins, and a hook that waits on a person stalls the attempt.
- **Project level:** without `--bare`, a `-p` run also executes the workspace's own
  `.claude/settings.json` hooks and connects its `.mcp.json` servers, even in a folder that was never
  trusted [S-HEADLESS]. The denied paths in §3.3 stop the agent from planting these for its next
  call. A repository that already has them still loads them.
- **`--bare`:** avoids both, but needs an API credential (§1.3 item 7). This is question Q10.
- **Background work:** a background command the agent starts, such as a dev server, can keep a
  `-p` run open after the turn ends. Story mode sets `CLAUDE_CODE_DISABLE_BACKGROUND_TASKS=1`.

### 3.10 The result

The result is the last event, and it is also written to `<state_dir>/result.json`:

```json
{"type":"result","outcome":"pushed","head_sha":"…","tests_ref_sha":"…",
 "red_observed":true,"tests_defective":false,"failure":null,
 "evidence":{"test_command":"npm test","exit_code":0,"criteria_map":"<state_dir>/criteria-map.json"}}
```

- `tests_ref_sha`, `red_observed` and `evidence` are reqdrive's additions.
- Every field is a claim that the orchestrator re-reads from git and from its own test run.
- `failure` is `{category, retryable, detail}`, copying the fatal `error`.

### 3.11 What stays as it is

These are unchanged:

- `run`, `launch`, `plan`, `verify`, `status` and `logs`, including `run_pipeline` and `create_pr`;
- every existing file format and schema;
- the frozen suite's existing 202 assertions;
- the policy module and the scope check;
- sanitization.

**Files story mode adds:**

- `lib/story.sh` and `lib/usage.jq`;
- `tests/lib/story-harness.sh` and `tests/story-lifecycle.sh`;
- the S1 stream fixture.

**Existing files it changes:**

- `bin/reqdrive`: a `story` case and the help text. `gh` becomes a lazy check, which also changes
  `run`'s startup: `run` now fails at PR creation, not at startup, when `gh` is missing.
- `tests/oracle-gate.sh` and the lock's format: one more locked file, and a hash field for it.
  `oracle-gate.sh` is itself locked, so this is a re-lock.
- `tests/simple-test.sh`, `tests/BEHAVIOR-SPEC.md` and `tests/oracle.lock.json`: new assertions,
  stories and the re-lock.
- `.github/workflows/ci.yml`: the lifecycle job, and the new files in the shellcheck list.
- `README.md`, `CLAUDE.md` and the affected `docs/canon/` pages.

The review phase and the completion hook do not run in story mode, because the orchestrator
verifies.

## 4. Transport assessment

| | CLI, work order in, JSON lines out | `harness-protocol` 0.1 |
|---|---|---|
| Fits Bash | Well: one emitter, one file descriptor | Poorly: stdin must be read while the agent runs (a reader process and a FIFO) to answer `unit/halt` and `unit/abandon` |
| Work order | Ours (§3.2) | `WorkOrder` lacks attempt id (it has `unit_id`), criteria with ids, base commit, failure evidence, inference policy, turn and token limits. Its caps are USD and wall clock |
| Heartbeat | Defined here | None, and the conformance kit's `UnknownMethod` rule rejects an added method |
| Per-call usage | Defined here, with `null` for unknown | `Metric` carries running increments of `tokens_in`, `tokens_out` and `cost_usd`, all required numbers: no model, no cache counts, and no way to say "unknown" |
| Stages | `progress{stage}` | A fixed `Observation` enum (`provisioned`, `oracle_frozen`, `build_finished`, …), which is close to our stages |
| Errors | `category` + `retryable` | `scope` (a fixed enum: `docker`, `github`, `agent`, `system`, `harness`) + `retryable` |
| Outcomes | `pr_open`/`pushed`, `no_change`, `failed`, `halted` | `pr_open`, `no_change`, `failed` |
| Artifacts | `tests_ref`, `branch`, `pr`, … | `branch`, `pr`, `diff` |
| Tests first | A ref plus an event; no wait | `gate/request{oracle}` blocks for approval, which is a good fit if the owner wants a wait (Q4) |
| Cancellation | Signals (§3.7) | `unit/halt` and `unit/abandon`, which are cleaner |
| Conformance | None yet. A JSON Schema for events and a recorded-run test would be ours to write | A kit exists and runs in CI |
| Forge | Neutral | `ErrorScope` has `github` and no other forge; delivery is `bundle` or `push` |

**Recommendation:** the CLI now. The two shapes are close but do not map one to one. A later
protocol version would need these additions to carry this seam:

- a heartbeat;
- per-call usage with a model id and nullable counts;
- criteria with ids;
- `halted`, `pushed` and a tests-ref artifact;
- a free-form error category beside `scope`.

Those are changes to `command-center`, listed as a request in Q2 and not made here. Until then, the
CLI's events are the contract, and an adapter or the Rust harness can translate them.

## 5. Build order

Each phase is test-first. Its new assertions go into `tests/simple-test.sh` with one
`tests/BEHAVIOR-SPEC.md` story each, and the lock is regenerated in that phase's PR, so every
change to the frozen suite is visible in review.

The freeze constrains where tests can go:

- **The frozen files:** `simple-test.sh`, `oracle-gate.sh`, `pipeline-harness.sh` and `spec-map.sh`
  are hash-locked.
- **Skips:** the gate accepts a locked test being skipped for one reason only, a missing `claude`
  (`tests/oracle-gate.sh:152-163`).
- **No platform branches:** the frozen suite runs on MSYS2 without platform conditionals
  (`CLAUDE.md:274`).

So the platform-sensitive signal tests go in a new, unfrozen `tests/story-lifecycle.sh` that runs
in Linux CI, as `tests/launch-lifecycle.sh` does for `launch`. Story mode's fake `claude` and
fixtures go in a new `tests/lib/story-harness.sh`. That leaves `run`'s fake in
`pipeline-harness.sh` untouched, at the cost of one more file to add to the freeze.

| # | Phase | Exit criterion | Size |
|---|---|---|---|
| P0 | Test scaffolding: `tests/lib/story-harness.sh` (a fake CLI that replays a recorded stream and runs a scripted workspace edit), `tests/story-lifecycle.sh` and its CI job, and the freeze extended to the new helper (an `oracle-gate.sh` change, re-locked) | The gate passes with the new file locked; the lifecycle script runs in CI | 1 day |
| S1 | **Spike: record one real stream.** One trivial `claude -p --output-format stream-json --verbose --include-partial-messages` call on the cheapest model, saved as a fixture. Needs the owner's go-ahead, because it spends (cents) | Fixture committed. §3.6's field paths and the turn-count field confirmed or corrected | 1 h |
| P1 | The emitter, the fd switch, the EXIT trap, work-order validation, `reqdrive story --dry-run` (validates and emits, with no agent) | A malformed work order yields `error` + `failed` and makes no agent call. Stdout parses as JSON lines with consecutive `seq`. A child that writes to fd 3 or fd 4 fails to | 1 day |
| P2 | Provision and parallel safety (§3.9) | Two dry-run instances in two worktrees of one repo change no shared ref and no config (asserted by diffing `git for-each-ref` and `.git/config`) | ½ day |
| P3 | Usage capture (§3.6) over the S1 fixture | Rows equal the fixture's responses; missing counts are `null`; residue rows appear when `modelUsage` exceeds the sum; a stream with no `result` yields `usage_incomplete` | 1 day |
| P4 | Red, the tests ref, the freeze (§3.4) | Each of `red_invalid`, `red_not_failing` and `tests_modified` (including an edit under `frozen_paths`) is produced by a scripted fake agent; `AC-10` does not satisfy `AC-1` | 1½ days |
| P5 | Green and Check (§3.3) | A scripted fake agent goes red to green to `pushed`. A fake that sets `testsDefective` stops Green | 1 day |
| P6 | Limits, heartbeat, signals (§3.7), in `tests/story-lifecycle.sh` | Each limit yields `halted`. SIGTERM during a slow fake agent yields a `halted` result within the grace period, and no event follows it. The two signal questions in §3.7 are answered on Linux | 1½ days |
| P7 | Deliver routes (§3.7.1): `orchestrator` and `github`, then `forgejo-agit` if the owner wants it | Each route asserted against a local bare remote and a fake `gh` | ½–1 day |
| P8 | Inference-policy refusal (§3.8) | A local-only policy is refused before any spend | 2 h |
| P9 | The live proof, run by the owner: two attempts in parallel on a sandbox repository | Two branches, two tests refs, and a usage ledger that reconciles with `modelUsage` | owner's time |

Docs are updated in the phase that changes the behaviour they describe: README, CLAUDE.md, the
canon modules, and the decision log, including correcting `CLAUDE.md:181-182`. The doc-coverage
gates (US-DOC-01/02/03) already require every new command and flag to appear in the README.

## 6. Out of scope

- Changes to the seam or to `harness-protocol`.
- A Forgejo REST client.
- A non-Claude agent adapter.
- The review phase in story mode.
- Anything in the Rust plans.
- Fixing INT-030 in `create_pr`, which story mode does not use. It is a one-line `>&2` at
  `lib/pr-create.sh:95`, listed for separate work.

## 7. Risks

- **The stream format may change between CLI versions.** Mitigations: pin a minimum CLI version,
  read the `capabilities` field in `system/init` where it helps, and keep the replay fixture under
  test.
- **The mechanical criterion check is weak.** An id in a comment beside a test proves the id
  appears, not that the test covers the criterion. That judgement stays with the orchestrator.
- **The freeze is only as good as `frozen_paths`** (§3.4).
- **Bash and signals** (§3.7). P6 is Linux-first, as `launch` coverage already is.

## 8. Questions for the owner

Each question has a recommendation. They are ordered by how much of the design they change.

1. **Bash v0.3 or the Rust rebuild?** *Recommend Bash now.* The Rust plans have not started, and
   their first M0 task archives the Bash tree. Story mode in Bash is about 10 days of build work
   (§5) and gives the orchestrator a harness to integrate against. Its event and result shapes then
   become an input to the Rust harness plan, whose M1 stages already match.
2. **Which transport?** *Recommend the CLI with JSON lines* (§4). If `harness-protocol` is the
   long-term wire, it needs the additions listed in §4.
3. **Who opens the PR on a forge that is not GitHub?** *Recommend the orchestrator,* and changing
   "one PR out" to "one pushed branch out" (§2.1).
4. **Must the harness wait for the orchestrator to confirm red?** *Recommend no* for the CLI
   transport.
5. **Where is the tests ref published, and under what name?** *Recommend* that the work order names
   it in full and that it is pushed to the same remote as the branch.
6. **Is §2.4's reading of `tests_defective` right?**
7. **Which outcome values?** *Recommend* `pr_open`/`pushed`, `no_change`, `failed`, `halted`.
8. **Usage details:**
   - Are residue rows acceptable (§2.3)?
   - Should a `cache_write` field be added?
   - Is `thinking: null` acceptable when it is always unknown for this CLI?
   - Which counts does `limits.tokens` cover? *Recommend* uncached input + cache writes + output,
     with cache reads excluded (§3.7).
9. **A local-only policy:** should reqdrive refuse it, try Claude Code against an Anthropic-compatible
   local server (unsupported, with a reported hang), or wait for a second adapter? *Recommend
   refuse* (§2.2).
10. **Isolation, permissions and `--bare`:** will the orchestrator run each workspace in a container
    (§3.9)? Will attempts run on an API credential (allowing `--bare`) or on a subscription login?
    Without `--bare`, the user's hooks and plugins and the repository's own `.claude/` hooks and
    `.mcp.json` servers load in every agent call.
11. **Work-order additions and preconditions:**
    - Are these fields acceptable as seam fields: `state_dir`, `base_branch`, `test_paths`,
      `frozen_paths`, `isolation`, `agent_allow`, `pr`?
    - Who fills `frozen_paths`?
    - Are these preconditions on the orchestrator acceptable: a clean workspace at `base_commit`; an
      empty `state_dir`; one run per work order, with a retry as a new attempt with fresh ids; and
      a target repository whose test runs leave no byproducts that are not gitignored?
12. **Criterion-to-test convention:** is "the criterion id appears as a whole word in the test's name
    or in a comment beside it" acceptable as the mechanical check?
13. **Spike S1** spends a few cents of model usage. Go ahead?
14. **Repository hooks:** the shell commits and pushes with `--no-verify` (§3.3), because a pre-push
    hook would reject the deliberately red tests commit. Is bypassing the target repository's own
    hooks acceptable, given that the orchestrator runs its own checks?

## 9. Sources

- [S-HEADLESS] Claude Code docs, "Run Claude Code programmatically":
  https://code.claude.com/docs/en/headless (read 2026-10-30)
- [S-COST] Claude Agent SDK docs, "Track cost and usage":
  https://code.claude.com/docs/en/agent-sdk/cost-tracking (read 2026-10-30)
- [S-CLI] Claude Code docs, "CLI reference": https://code.claude.com/docs/en/cli-reference
  (read 2026-10-30); local `claude --version` = 2.1.296
- [S-GATEWAY] Claude Code docs, "Other LLM gateways": https://code.claude.com/docs/en/llm-gateway
  (read 2026-10-30)
- [S-OLLAMA] Ollama docs, "Anthropic compatibility":
  https://docs.ollama.com/api/anthropic-compatibility, and https://registry.ollama.ai/blog/claude
- [S-HANG] Claude Code issue #51239: https://github.com/anthropics/claude-code/issues/51239
- [S-AGIT] Forgejo docs, "AGit Workflow Usage":
  https://forgejo.org/docs/latest/user/git-cli/agit-support/
- [S-PROTO] `command-center` `main`, `crates/harness-protocol/` (README, `src/types.rs`,
  `src/rpc.rs`; `PROTOCOL_VERSION = "0.1"`), read 2026-10-30

## 10. The Rust implementation

### 10.1 Layout

The repository becomes a cargo workspace. Rust is pinned to 1.93.1 in `rust-toolchain.toml`. The
Bash tree moves unchanged to `archive/bash-v0.3/`. `docs/superpowers/` stays where it is.

```
Cargo.toml                    workspace with one member, crates/reqdrive
crates/reqdrive/              the `reqdrive` binary, plus a library half the tests use
  src/bin/fake-claude.rs      a test-only stand-in for the `claude` CLI, and a test checker.
                              It is a bin of this package so integration tests can find it
                              through CARGO_BIN_EXE_fake-claude
  src/main.rs                 parses `reqdrive story <work-order.json>`, runs it, exits
  src/workorder.rs            the work-order types; shape validation (pure)
  src/outcome.rs              Outcome, Category, retryable, the pending result
  src/events.rs               event bodies; the Emitter (envelope, seq, ts, stdout + events.jsonl)
  src/paths.rs                prefix rules: denied, frozen, test paths
  src/criteria.rs             the whole-word criterion-id check over added diff lines
  src/prompts.rs              Red and Green prompts; reading the agent's final text
  src/stream.rs               the stream-json parser: usage rows, final result, residue (pure)
  src/policy.rs               the inference-policy check and the agent's environment
  src/limits.rs               the deadline, turn budget and token counter
  src/proc.rs                 supervised child processes: deadline, interrupt, kill, signal flag
  src/git.rs                  git through `git -C <workspace>`, with a fixed identity
  src/agent.rs                the claude-code adapter: arguments, one call, its outcome
  src/story.rs                the driver: the stages, the pending result, the heartbeat
```

The external dependencies are `serde`, `serde_json`, `humantime` (for RFC 3339 times), `ctrlc`
with its `termination` feature (signals on Unix and Windows) and `libc` (Unix only, to send
SIGINT). `tempfile` is used for tests only. There is no async runtime and no argument-parsing
crate: std threads and channels are enough, and there is one subcommand.

### 10.2 What Rust changes in the mechanics

| Bash design (§3) | Rust |
|---|---|
| fd 3/fd 4, a jq emitter, `run_child` | One `Emitter` behind an `Arc<Mutex<…>>` owns stdout and `events.jsonl`. It adds `v`, `attempt_id`, `seq` and `ts` last, so a body can never set them. Every child is spawned with an explicit `stdout` (piped or a file) and `stdin` set to null. Without that, std would let the child inherit our stdout. A write error on stdout is the one case that ends with a non-zero exit |
| `trap '' PIPE` and restoring it | Rust ignores SIGPIPE in its own process, and std resets it to the default in spawned children on Unix |
| The EXIT trap and `pending_result` | `story::run` returns a `ResultEvent` on every path. Errors are values. Every failing path goes through one `end()` that also emits the fatal `error` event. `run` stops and joins the heartbeat thread before it returns. `main` wraps `run` in `catch_unwind`, then calls `Emitter::finish(result)`, which writes the result once, also writes `<state_dir>/result.json`, and refuses any later event. It then exits 0 |
| `timeout -s INT -k 30` and wait loops | `proc::supervise` polls `try_wait` every 100 ms. When the deadline passes, the interrupt flag is set, or the token limit is hit, it interrupts the child and kills it if it is still running 30 s later. It returns `Exit { code, ended_by: Normal \| Deadline \| Interrupted \| TokenLimit }`. On Unix every child is spawned in its own process group (`process_group(0)`), and SIGINT and SIGKILL go to the group, so grandchildren under `sh -c` stop too. On Windows only the direct child can be killed, so `REQDRIVE_CLAUDE_BIN` must name a real `.exe`, not a `.cmd` shim. Job Objects are deferred. The 30 s grace applies to the group's leader: once the leader exits, after an interrupt or not, the rest of the group is killed at once, because background grandchildren ignore SIGINT under a non-interactive `sh`. The agent's stdout reader gets the grace (at least 1 s) after the agent exits; a pipe still held open past that, by a process that left the group or by any descendant on Windows, is abandoned with a `usage_incomplete` error |
| Traps for INT, TERM and HUP | `ctrlc` with `termination` replaces the default action for SIGINT, SIGTERM and SIGHUP on Unix, and for Ctrl-C and Ctrl-Break on Windows. It sets an `AtomicBool` that the supervisor and the driver poll before every step. Closing the console on Windows ends the process without a result |
| Hooks bypassed with `--no-verify` | Every git call also passes `-c core.hooksPath=<state_dir>/no-hooks`, an empty directory. `--no-verify` alone leaves `prepare-commit-msg`, `post-checkout` and `reference-transaction` running |
| Exit 126/127 means the runner is missing | Unix only. On Windows `cmd` reports a missing command as exit 1, so a missing runner shows up as `base_broken` at provision instead |
| `limit_hit` file | `ended_by: TokenLimit` carries it |
| Summing `events.jsonl` for tokens | The stream reader thread adds each usage row's count to an `AtomicU64` in `Limits` |
| `sh` for `test_command` | `sh -c` on Unix and `cmd /C` on Windows, with `CI=true`, stdout and stderr captured to a log file in `state_dir`, and the same supervision |
| The criteria map in a fenced block | Unchanged: the `json:criteria-map` block, and `testsDefective` in a `json:iteration-summary` block, are read from the `result` message's text |

**Sanitization** keeps its two purposes from the Bash design, with mechanics suited to Rust.

- **No forged placeholders.** Templates are filled in one pass, by scanning for `@@NAME@@`, so text
  that was substituted in is never scanned again.
- **No breaking out of a fence.** Untrusted text sits inside fences of four backticks, and runs of
  three or more backticks inside it are broken up.
- **Dangerous patterns are still flagged, warn-only.** The patterns from
  `archive/bash-v0.3/lib/sanitize.sh` are checked as plain substrings, without the regex crate:
  `$(`, `` ` ``, `${`, `rm -rf /`, `chmod 777`, `eval `, and `curl`/`wget` with `| sh`. Each match
  becomes a `log` event.

### 10.3 Tests

- **Unit tests** sit next to each module. The parser is tested against a hand-written fixture in
  the documented stream format.
- **Integration tests** in `crates/reqdrive/tests/` run the real binary. Each one builds a temp
  repository with a bare remote, gives the binary a work order, and points it at `fake-claude`
  through `REQDRIVE_CLAUDE_BIN`.
- **`fake-claude`** is driven by a JSON script. For each call it can write files in its working
  directory, print stream lines, sleep, and exit with a code. Its `check-tests <dir>` subcommand
  checks `expect <file> <text>` lines in the test files, and it is the test command in the tests,
  so they run the same on Windows and Linux.
- **The heartbeat interval** is 30 s, and tests lower it with `REQDRIVE_HEARTBEAT_MS`.
- **Platform split:** signal tests are `#[cfg(unix)]`, and everything else runs on both platforms.
- **CI** runs `cargo fmt --check`, `cargo clippy -- -D warnings` and `cargo test` on
  `ubuntu-latest` and `windows-latest`.
### 10.4 Decisions the Rust build adds to §3

- **Two more work-order fields:** `green_max_calls` (default 5, from 1 to 20) and `denied_paths`
  (added to the defaults in §3.3).
- **`tests_ref` must start with `refs/`.**
- **Every name-only diff uses `--no-renames`,** so a rename reports both paths to the freeze and
  denied-path checks.
- **Remote-tracking refs.** §3.9's "only refs it writes" also covers the remote-tracking refs that a
  push updates, under `refs/remotes/<remote>/`. They are unique to each attempt too.
- **No evidence push after an interrupt.** It is still made after a halt caused by a limit. The
  orchestrator is stopping the attempt, and a network call would delay the exit.
- **No push without a deadline.** Pushes are supervised with the remaining wall clock, like every
  other child.
- **A push cut short by a limit or an interrupt** ends `halted` (`limit_reached` or `interrupted`),
  not `failed` with `push_failed`: the "any" rows of §3.5.1 outrank the push row.
- **`head_sha` on `failed` and `halted` results** is set only when the evidence push succeeded,
  because a local-only sha cannot be verified by the orchestrator. No evidence push follows a
  `push_failed`.
- **The driver owns the expected HEAD.** Only its own commits and resets move it. HEAD is checked
  after every agent call and every test run and before every push. A mismatch (an agent or a test
  command that ran git) saves a patch, resets to the expected commit and ends `scope_violation`.
  Deliver pushes exactly the commit Check ran on.
- **A dead stdout stops the run.** Every event is logged to `events.jsonl` first. The first failed
  stdout write sets the interrupt flag, so the attempt ends `halted`/`interrupted` at its next
  check, and `result.json` is still written; the process exits 1.
- **More shape checks:** `limits.wall_clock_secs` is at most 7 days; `attempt_branch` has no
  `refs/` prefix; `tests_ref` may not equal, contain or sit under `refs/heads/<attempt_branch>`.
  Without isolation, a comma in the test command or an `agent_allow` rule is `work_order_invalid`,
  because the rules are joined with commas into one `--allowedTools` value.
- **Red's test run killed by a signal** (no exit code) is `harness_error`, since it says nothing
  about the new tests. Green and Check count it as a failing run.
- **Repository-locating env vars** (`GIT_DIR`, `GIT_WORK_TREE`, `GIT_INDEX_FILE`,
  `GIT_COMMON_DIR`, `GIT_OBJECT_DIRECTORY`, `GIT_ALTERNATE_OBJECT_DIRECTORIES`) are removed for
  git, the agent and the test command. git also runs with `gc.auto=0` and
  `maintenance.auto=false`, and pushes with `push.followTags=false` and
  `push.recurseSubmodules=no`.

The Bash suite's freeze gate is archived with it. A hash lock over contract tests, as the factory
plans have it, is not part of v1.

### 10.5 Not in v1

- PR routes (Q3).
- A second agent adapter (§2.2).
- `harness-protocol` (Q2).
- Docker workspaces: isolation stays the orchestrator's (§3.9).
- The factory plans' crates and gates.

The live check is the last step and needs the owner's go-ahead (Q13). It is one tiny real
`claude -p` call, to confirm the stream fields the parser assumes, followed by one story run on a
sandbox repository.

## Design Critique Log

### Critique Round 1

An independent reviewer checked the draft against the code, the protocol crate and the live CLI
docs. It made 12 findings: 1 blocker, 7 major and 4 minor. All were accepted.

| Finding | Severity | Resolution |
|---|---|---|
| Under `acceptEdits` the agent cannot `git commit`. The draft's state directory was under `.git`, a protected path. The reused prompt told the agent to write `prd.json` and `progress.txt` | Blocker | The shell makes every commit. The agent never runs git or writes state. `state_dir` is required, comes from the orchestrator, and lies outside the worktree (§3.2, §3.3, §3.9) |
| Reusing a one-story `prd.json` let the agent end Green or reset the retry cap by editing it. The loop also never stopped when tests passed | Major | A new loop in `lib/story.sh` with counters the shell owns, and a stop on a pass the shell observes (§3.3) |
| fd 3 leaked to `test_command`, git hooks and the CLI. Tests could forge events, and stray children could hold the pipe open | Major | Every child runs with `3>&- 4>&-` (§3.1), and a P1 test asserts it |
| The `create_pr` claims were wrong. Its stray echo goes into the captured URL, not stdout. It pushes `-u origin`. Its body comes from `prd.json`. `gh` needs a base branch. `gh` was still required at startup | Major | Story mode does not use `create_pr`; it has its own Deliver routes (§3.7.1). `base_branch` added. `gh` checked lazily. INT-030 left for separate work (§6) |
| The event pipeline could not share `seq` across three writers. jq cannot write a tokens file. `inputs` stops at a non-JSON line, and `pipefail` then kills the CLI. "One printf" contradicted "jq --argjson" | Major | One emitter process owns `seq` and `ts`. Producers write bodies to fd 4. `fromjson? // empty`. The watchdog sums `events.jsonl` (§3.1, §3.6, §3.7) |
| Traps wait for the foreground child. Reused paths call `exit`, and `set -e` aborts left no result. `timeout`'s TERM loses the CLI's result. `wait` after `kill` aborted under `set -e` | Major | Children run in the background and are waited on. An EXIT trap writes the result. `timeout -s INT -k 30`. `wait … \|\| true`. The two signal behaviours are verified in P6 (§3.1, §3.7) |
| The freeze guarded only Red's files. Runner config and new skip markers could make tests pass | Major | Green may not touch Red's files, `test_paths` or `frozen_paths`. The remaining gap is stated, and the orchestrator runs its own command (§3.4) |
| Parallel-safety claims covered only reqdrive's own writes. `worktree remove` deleted state | Major | Scoped to reqdrive's own writes, with the isolation assumption stated. `state_dir` comes from the orchestrator (§3.9) |
| A substring criterion match let `AC-10` satisfy `AC-1` | Minor | `grep -wF` (§3.4) |
| Sanitization claims were wrong: `validate_requirement_content` only warns, and `sanitize_for_prompt` mangles logs | Minor | Corrected, with the template pattern stated (§3.2) |
| Two config citations were off by a few lines | Minor | Fixed |
| "Maps one to one" overstated the protocol fit | Minor | §4 now lists the mismatches in outcomes, error scope and artifact kinds |

### Critique Round 2

A fresh reviewer checked the round-1 revision. It ran the shell mechanics in Git Bash (bash 5.2,
jq 1.8.1, GNU timeout 8.32) and made 11 findings: 2 blockers, 6 major and 3 minor. All were
accepted.

| Finding | Severity | Resolution |
|---|---|---|
| The emitter could hang, end early, or be forged. In an experiment, the EXIT trap hung because the heartbeat loop still held fd 4. A non-object JSON line ended jq, and the next write killed the shell with SIGPIPE. `{envelope} + $e` let a body overwrite `seq` and `attempt_id` | Blocker | `emitter_pid=$!`. The EXIT trap stops the other fd-4 holders first, then writes the result, closes fd 4 and waits. An object filter, envelope applied last, `trap '' PIPE` (§3.1) |
| SIGINT went to the wrong process: `$!` of a background pipeline is its last element (the usage parser). A trapped signal makes `wait` return early. `timeout 0` disables the timeout | Blocker | `timeout`'s PID written to `call-<n>.pid` and signalled. A wait loop. A remaining budget ≤ 0 becomes `limit_reached` before any child starts (§3.6, §3.7) |
| Shell commits swept in test byproducts (snapshots, coverage, `.env`). There was no commit identity in a fresh container. Repo hooks would reject the red commit and loop on a retryable `push_failed`. A pushed workflow file would run in CI | Major | The tree is reset after every shell test run. Explicit identity, `--no-verify`. Denied paths for `.github/`, `.husky/`, `.claude/`, `.mcp.json`, `.gitmodules` (`scope_violation`). Q14 added (§3.3) |
| Outcomes and categories did not line up: no producer of `no_change`, `pr_open` vs `pushed` contradicting each other, and missing categories | Major | One table, stage × condition → outcome, category, retryable (§3.5.1). The default outcome is `pushed` |
| A red failure was never shown to be the right one: exit 127, syntax errors or a broken environment counted as red. "Pass on the base" was wrong (the tests ran at red). There was no shared retry budget | Major | `provision` requires the suite to pass at the base (`base_broken`). Exits 126/127 are `harness_error`. Two Red attempts in total, with the last failure deciding the category (§3.3, §3.4) |
| `limits.tokens` was undefined, and counting cache reads grows with turns × context | Major | The sum is defined without cache reads. Added to Q8 (§3.7) |
| The estimate ignored the frozen suite: only a `claude` skip is accepted, MSYS2 runs with no platform conditionals, and `pipeline-harness.sh` is locked and shared | Major | P0 added: a new story helper file added to the freeze, and platform-sensitive tests in an unfrozen `tests/story-lifecycle.sh` on Linux CI. Re-estimated to about 10 days (§5) |
| Without `--bare`, project `.claude/settings.json` hooks and `.mcp.json` servers load even untrusted, and background commands keep `-p` open | Major | Stated in §3.9 and Q10. Denied paths stop the agent planting them. `CLAUDE_CODE_DISABLE_BACKGROUND_TASKS=1` |
| Turning off `Agent` alone does not stop forked skills | Minor | `--disallowedTools Agent,Skill`; residue rows cover the rest (§2.3, §3.6) |
| `Bash(<test_command>)` matched only the exact command | Minor | The prefix form is added (§3.9) |
| An empty Green call re-ran the tests and used up a slot silently | Minor | It is logged and counted, and the tests are not re-run (§3.3) |

### Critique Round 3

A third fresh reviewer read the whole document for coherence and checked whether the round-2 fixes
introduced new bugs, with experiments in Git Bash. It made 11 findings: 2 blockers, 5 major and 4
minor. All were accepted. It confirmed that the §1 gap analysis and its sampled citations hold.

| Finding | Severity | Resolution |
|---|---|---|
| The call group inherits `set -e`, so a non-zero `wait` ended it before the exit-code file was written (shown by experiment). Exit codes 124, 130 and agent failures were invisible | Blocker | `wait $! && rc=0 \|\| rc=$?`, plus a P1 test with the fake agent exiting 1 (§3.6) |
| Denied paths were checked after `git add -A` and the commit, and Deliver pushes failed attempts as evidence, so a caught workflow-file change would still reach CI | Blocker | Denied paths and the freeze are checked on the staged set before any commit. A violation is saved as a patch, the tree is reset, and the commit is never made (§3.3, §3.4) |
| Nothing wrote the `halted` results. A trap writing them would race the heartbeat. A token-limit SIGINT could not be told apart from an outside one | Major | Stages and traps only set `pending_result`; the EXIT trap alone writes the result. The watchdog writes a `limit_hit` file before signalling (§3.1, §3.7) |
| A clean tree was never required. A dirty tree carried onto the branch was then wiped by the post-test reset (shown by experiment) | Major | Validation requires an empty `git status --porcelain`, untracked files included (§3.2) |
| Byproducts of the agent's own test runs were swept into commits, as false `tests_modified` or `red_invalid` | Major | `CI=true` for every test run and for the agent's environment. The order is stated: stage, check, commit, test, reset. Gitignored byproducts become a precondition in Q11 (§3.3) |
| `trap '' PIPE` reached every child across `exec` and could not be undone there (shown by experiment) | Major | Every child starts through `run_child`, which restores SIGPIPE and closes fd 3 and fd 4 (§3.1) |
| Re-running a work order was undefined: appended events, a restarted `seq`, old usage counted against the limit, and a `branch_conflict` after a "retryable" failure | Major | `state_dir` must be empty, so each work order runs once. "Retryable" is defined as "a new attempt with fresh ids may succeed" (§3.2, §3.5.1, Q11) |
| The "what stays as it is" lists were out of date (lazy `gh` changes `run`'s startup; `oracle-gate.sh`, the lock format and CI change) | Minor | §3.11 lists every added and changed file; §3.1 points to it |
| "Reuses its agent invocation" contradicted §3.6 and §3.8 | Minor | Corrected in §0 and §3.3 |
| Table errors: `forge_failed` is non-fatal too; Red agent failures had no row; `base_missing` was unreachable | Minor | All three fixed (§3.5.1, §3.2) |
| "The brief" and "the build machine" point at material a public reader cannot see | Minor | Reworded |

### Critique Round 4 (the Rust implementation)

A fresh reviewer checked §10 and the implementation plan together, with experiments in Rust
1.93.1 and Git Bash. It made 15 findings: 2 blockers, 7 major and 6 minor. All were accepted. It
confirmed that interface names line up across the plan's tasks, that the fixture arithmetic holds,
that `cmd` `raw_arg` quoting works with spaces, and that the reader thread prevents a pipe
deadlock.

| Finding | Severity | Resolution |
|---|---|---|
| `CARGO_BIN_EXE_*` is not set for unit tests inside `src/` (shown by experiment) | Blocker | Tests that run a bin are integration tests under `crates/reqdrive/tests/` |
| `#![forbid(unsafe_code)]` cannot be overridden by `#[allow]`, which breaks the Unix-only `kill` on Linux CI | Blocker | `#![deny(unsafe_code)]` |
| `--name-only` diffs hide a rename's old path, so a frozen test or a workflow file could be moved without detection | Major | `--no-renames` everywhere, with a test that a rename lists both paths (§10.4) |
| The token limit was checked only during a child process, and Red never checked budgets before a call | Major | The driver checks every budget before each agent call, test run and push, and tokens after each agent call |
| Only the direct child was signalled; npm under `sh -c`, or node under a Windows `.cmd` shim, survived | Major | Unix process groups; a real `.exe` required on Windows; spawn errors become `harness_error`; Job Objects deferred |
| `--no-verify` does not skip `prepare-commit-msg` and other hooks (shown by experiment) | Major | `-c core.hooksPath=<empty dir>` on every git call |
| The fatal `error` event, `result.json`, test-log events and stderr lines had no task | Major | A driver `end()` helper, `finish` writing `result.json`, and test-tail `log` and `log_file` events |
| Parallel-test refs were wrong: a push also creates remote-tracking refs | Major | The test assertion and §3.9 corrected (§10.4) |
| A global panic hook could fire from a thread and race the real result | Major | `catch_unwind` in `main`, with thread panics surfaced through `join` |
| Minor: Task 1's clean-tree check; the Windows console-close claim; Windows exit codes; the SIGTERM test's timing; spec/plan naming drift; test-helper file placement; `current_dir` for the agent; `tests_ref` format; process-wide env in a git test; machine paths in public docs | Minor | Each fixed in §10 or the plan |
