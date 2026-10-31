# Status

The living status of the repository. The state summary is rewritten in place each session. The
session log below it is appended newest first.

## State summary

- **TL;DR:** the Rust story harness (`reqdrive story <work-order.json>`) is built and tested
  offline against a fake agent. The final whole-branch review is done and its findings are fixed.
  The live check against the real `claude` CLI has not run: it waits for the owner's go-ahead.
- **Branch:** `feat/story-harness-rust`, not merged. No pull request is open yet.
- **Readiness:** the three checks (`cargo fmt --check`, `cargo clippy --all-targets -- -D warnings`,
  `cargo test`) pass on Windows. The first CI run on Linux has not happened, so the Unix-only code
  and tests are not yet compiled there; that run is the merge gate.
- **Known gaps:** see [`ROADMAP.md`](../ROADMAP.md) (deferred scope, open questions Q4 to Q14,
  planned improvements, known minor issues).
- **Next steps:**
  1. Push, open a PR, and confirm CI is green on Linux and Windows.
  2. Run the live check once the owner gives the go-ahead (ROADMAP, Next).

Design: [`docs/superpowers/specs/2026-10-30-story-harness-mode-design.md`](superpowers/specs/2026-10-30-story-harness-mode-design.md).
Plan: [`docs/superpowers/plans/2026-10-30-story-harness-rust.md`](superpowers/plans/2026-10-30-story-harness-rust.md).
Roadmap: [`ROADMAP.md`](../ROADMAP.md).

## Session log

### 2026-10-31: final review fixes

- **Fixed:** a leftover process holding the agent's stdout no longer hangs the run (the reader is
  abandoned after the grace, with `usage_incomplete`); a closed stdout stops the run as
  `halted`/`interrupted` while `events.jsonl` and `result.json` are still written; a commit made
  by the test command is caught (`scope_violation`) and never pushed, and Deliver pushes exactly
  the commit Check ran on. Also: turns gate only agent calls, forge CI paths are denied,
  repository-locating `GIT_*` vars are removed for every child, residue unknowns are `null`, and a
  set of smaller validation, git-config and documentation items.
- **State delta:** review findings closed; spec section 10 and the README updated to match. Not
  done: CI on Linux, a PR, the live check.

### 2026-10-30: the Rust story harness

- **Built:** the Bash tree moved unchanged to `archive/bash-v0.3/`. A cargo workspace with one
  package, `crates/reqdrive`, now holds the harness: work-order validation, the event emitter,
  path and criterion rules, prompts, the stream-json usage parser, the inference policy, supervised
  child processes, git operations, the claude-code adapter and the driver (Red, Green, Check,
  Deliver), plus the test-only `fake-claude` binary. README, CLAUDE.md, this file and the roadmap
  were written fresh for it.
- **Reviewed:** built in 12 tasks, each implemented and then reviewed independently, with fix rounds
  on the five tasks whose review found problems (Tasks 3, 5, 7, 10 and 11) and automated security
  review findings handled on Tasks 3, 5 and 7. Eleven rulings were recorded along the way (R1 to
  R11), covering test plumbing, path-rule hardening, git-config hardening, an accepted residual
  isolation risk, push outcomes and evidence pushes. The spec was amended with the three that
  change its wording: R7, R10 and R11.
- **State delta:** v1 built and tested offline. Not done: the live check, the final whole-branch
  review, CI on Linux, a PR.
