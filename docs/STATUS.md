# Status

The living status of the repository. The state summary is rewritten in place each session. The
session log below it is appended newest first.

## State summary

- **TL;DR:** the Rust story harness (`reqdrive story <work-order.json>`) is built and tested
  offline against a fake agent. The live check against the real `claude` CLI has not run: it waits
  for the owner's go-ahead. The final whole-branch review has not yet happened.
- **Branch:** `feat/story-harness-rust`, not merged. No pull request is open yet.
- **Readiness:** the three checks (`cargo fmt --check`, `cargo clippy --all-targets -- -D warnings`,
  `cargo test`) pass on Windows. The first CI run on Linux has not happened, so the Unix-only
  process-group code is unverified there.
- **Known gaps:** see [`ROADMAP.md`](../ROADMAP.md) (deferred scope, open questions Q4 to Q14, known
  minor issues). A short list of review findings is being fixed before merge.
- **Next steps:**
  1. Fix the findings from the build review, then run the final whole-branch review.
  2. Push, open a PR, and confirm CI is green on Linux and Windows.
  3. Run the live check once the owner gives the go-ahead (ROADMAP, Next).

Design: [`docs/superpowers/specs/2026-10-30-story-harness-mode-design.md`](superpowers/specs/2026-10-30-story-harness-mode-design.md).
Plan: [`docs/superpowers/plans/2026-10-30-story-harness-rust.md`](superpowers/plans/2026-10-30-story-harness-rust.md).
Roadmap: [`ROADMAP.md`](../ROADMAP.md).

## Session log

### 2026-10-30: the Rust story harness

- **Built:** the Bash tree moved unchanged to `archive/bash-v0.3/`. A cargo workspace with one
  package, `crates/reqdrive`, now holds the harness: work-order validation, the event emitter,
  path and criterion rules, prompts, the stream-json usage parser, the inference policy, supervised
  child processes, git operations, the claude-code adapter and the driver (Red, Green, Check,
  Deliver), plus the test-only `fake-claude` binary. README, CLAUDE.md, this file and the roadmap
  were written fresh for it.
- **Reviewed:** built task by task (12 tasks) with an implementer and an independent review per
  task, fix rounds where the review found problems, and an automated security review. Eleven
  rulings were recorded along the way (R1 to R11), covering test plumbing, path-rule hardening,
  git-config hardening, an accepted residual isolation risk, push outcomes and evidence pushes.
  The spec was amended with the two that change its wording.
- **State delta:** v1 built and tested offline. Not done: the live check, the final whole-branch
  review, CI on Linux, a PR.
