# CLAUDE.md

<!-- BEGIN: ACTIVE-SESSION-PICKUP — remove this block once the "Next steps" in docs/STATUS.md dated 2026-10-31 are under way -->
## Active session pickup

The last session (2026-10-31) ended with work left. Before anything else, read the **State
summary** and its **Next steps** at the top of [`docs/STATUS.md`](docs/STATUS.md), and the newest
session-log entry under it. They say:

- what is merged and what waits on the owner (PR #10, if `gh pr view 10` still shows it open),
- which owner decision unblocks the rest (Q10 in [`ROADMAP.md`](ROADMAP.md)), and
- assumptions the last session took that may need revisiting.

If those next steps are already done, this block is stale: delete it.
<!-- END: ACTIVE-SESSION-PICKUP -->

`reqdrive story <work-order.json>` runs one story to one pushed branch and reports it as JSON-lines
events on stdout. This file is for agents working in this repository. The user-facing description
is in [`README.md`](README.md).

**This repository is public.** Never name or describe a private project, client, employer, person,
machine or business plan in code, comments, docs, commits or PRs. Write the orchestrator generically
("an external orchestrator"). No machine-specific paths (drive letters, user names, local target
directories) in any file.

## Where things stand

- Design: [`docs/superpowers/specs/2026-10-30-story-harness-mode-design.md`](docs/superpowers/specs/2026-10-30-story-harness-mode-design.md).
  Section 3 is the behaviour, 3.5.1 the outcome table, 10 the Rust implementation. Where the
  design and a plan disagree, the design is right.
- Plan: [`docs/superpowers/plans/2026-10-30-story-harness-rust.md`](docs/superpowers/plans/2026-10-30-story-harness-rust.md)
- State and session log: [`docs/STATUS.md`](docs/STATUS.md)
- The only roadmap: [`ROADMAP.md`](ROADMAP.md). Add future work there, not in a new file.

The other plans in `docs/superpowers/plans/` (the factory M0 and M1 plans, the earlier roadmap
completion plan) are not the current path. `archive/bash-v0.3/` is frozen history.

## Architecture

One cargo workspace, one package, `crates/reqdrive`: a binary, a library the tests use, and a
test-only binary.

```
crates/reqdrive/src/
  main.rs            parses `reqdrive story <file>`, runs it under catch_unwind, writes the result
  workorder.rs       work-order types; shape validation (pure)
  outcome.rs         Outcome, Category, retryable, ResultEvent
  events.rs          event bodies; the Emitter (envelope, seq, ts; stdout + events.jsonl)
  paths.rs           prefix rules: denied, frozen, test paths
  criteria.rs        whole-word criterion-id check over added diff lines
  prompts.rs         Red and Green prompts; reading the agent's final text
  stream.rs          stream-json parser: usage rows, final result, residue (pure)
  policy.rs          inference-policy check and the agent's environment
  limits.rs          deadline, turn budget, token counter
  proc.rs            supervised children: process groups, deadline, interrupt, kill, signal flag
  git.rs             git through `git -C <workspace>` with a fixed identity
  agent.rs           the claude-code adapter: arguments, one call, its outcome
  story.rs           the driver: stages, the result on every path, the heartbeat
  bin/fake-claude.rs test-only stand-in for `claude`, plus the `check-tests`, `spew` and `hold` helpers
crates/reqdrive/tests/   integration tests that run the real binaries; common/ holds helpers
```

## Principles

- **The driver orchestrates; the agent implements.** The harness owns every counter and makes every
  commit. The agent edits files and runs the test command. It never runs git and never writes
  state. The driver owns the expected HEAD; HEAD is checked after every agent call and test run
  and before every push, and a mismatch is `scope_violation`.
- **Unknown is `null`, never 0.** Every count is an `Option<u64>`.
- **Children never inherit stdout.** Every `Command` sets `stdin` (null, or a file for the prompt)
  and an explicit `stdout`. A child must not be able to forge an event. On Windows std passes every
  inheritable handle to every child whatever its `Stdio`, so `main` first makes the harness's own
  std handles non-inheritable (`proc::stop_std_handle_inheritance`).
- **The seam rules are hard gates; everything else is warn-only.** Denied paths, the test freeze,
  the criterion-id check and the red check fail the attempt. Heuristics, such as the
  dangerous-pattern scan, become `log` events and never block.
- **Errors are values.** `story::run` returns a `ResultEvent` on every path. Exactly one result is
  written, last.

## Commands

```
cargo fmt --check
cargo clippy --all-targets -- -D warnings
cargo test
```

All three must pass before a commit. `CARGO_TARGET_DIR` may point outside the checkout (for example
to a fast disk). Run one cargo build at a time.
Integration tests find the bins through `CARGO_BIN_EXE_*`, which is not set for unit tests in
`src/`, so any test that runs a bin belongs under `crates/reqdrive/tests/`.

## Conventions

- Toolchain 1.93.1 (`rust-toolchain.toml`), edition 2021. `#![deny(unsafe_code)]` in `lib.rs`;
  in `src/`, only `proc.rs`'s Unix `kill` calls and its Windows `SetHandleInformation` call carry
  `#[allow(unsafe_code)]`. Do not use `forbid`.
- The work-order `schema` is exactly `"story-work-order/0"`. The event envelope is
  `{"v":1,"attempt_id","seq","ts"}`, applied after the body so a body cannot override it.
- Outcomes: `pushed`, `no_change`, `failed`, `halted`. There is no `pr_open` in v1.
- `test_command` runs through `sh -c` on Unix and `cmd` with `raw_arg("/S /C \"<cmd>\"")` on
  Windows, always with `CI=true`.
- Git runs as `git -C <workspace> -c core.hooksPath=<state_dir>/no-hooks …` with
  `GIT_TERMINAL_PROMPT=0`, fsmonitor, external protocols and auto gc/maintenance off, and
  `--no-ext-diff --no-textconv` on diffs. Commits use a fixed identity and `--no-verify`. Pushes are
  `-c push.followTags=false -c push.recurseSubmodules=no push --no-verify <remote> <sha>:<ref>`,
  never `-u`. Every `git diff … --name-only` carries `--no-renames`. git, the agent and the test
  command all run without `proc::REPO_ENV` (`GIT_DIR` and the other repository-locating vars).
- Unix children are spawned with `process_group(0)`; interrupt and kill go to the group. On Windows
  only the direct child can be killed, so `REQDRIVE_CLAUDE_BIN` must name a real `.exe`.
- A spawn error for the agent or the test command is a `HarnessError`, with the text in the detail.
- Defaults: heartbeat 30 000 ms (`REQDRIVE_HEARTBEAT_MS`), interrupt grace 30 000 ms
  (`REQDRIVE_GRACE_MS`), both capped at one hour, agent binary `claude` (`REQDRIVE_CLAUDE_BIN`), Green at most
  `green_max_calls` calls (default 5), Red two attempts. Failure evidence is capped at 8 192 bytes
  per entry on a char boundary, a test-log tail is 2 048 bytes, a `log` line 2 000 chars.
- Denied paths: `.github`, `.forgejo`, `.gitea`, `.gitlab-ci.yml`, `.husky`, `.claude`, `.mcp.json`,
  `.gitmodules`, plus the work order's.
- Tests must work with a workspace or state path that contains a space, skip non-JSON or partial
  agent output lines, keep test output in a log file with only a tail in events, and cope with a
  failing pre-commit hook and CRLF in diffs.
- Tests are written first. Match the surrounding style. Do not add a dependency without need.
- Commit messages and PR bodies carry no co-author line and no generated-by footer.
