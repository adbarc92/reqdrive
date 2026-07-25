# Architecture — reqdrive (canon)

Stamped at commit `7420d69`, 2026-07-24. Requirements are canon; where the code
contradicts them the requirement is recorded as intended and the divergence is
logged in [requirements/drift-report.md](requirements/drift-report.md).

reqdrive is a **Bash orchestration monolith**, not a service or a library: one
entry point (`bin/reqdrive`, 727 lines) sourcing eleven `lib/*.sh` modules
(2,683 lines), with a 3,242-line assertion suite and a freeze gate around it. It
takes one markdown requirement file and produces one GitHub pull request, using
the `claude` CLI as a stateless subprocess per story.

## Routing table

| Path pattern | Module doc |
|--------------|------------|
| `bin/**` | [modules/cli.md](modules/cli.md) |
| `lib/run.sh` | [modules/pipeline.md](modules/pipeline.md) |
| `lib/verification.sh`, `lib/policy.sh` | [modules/evidence.md](modules/evidence.md) |
| `lib/pr-create.sh` | [modules/pr.md](modules/pr.md) |
| `lib/config.sh`, `lib/schema.sh`, `lib/validate.sh`, `lib/init.sh`, `templates/**` | [modules/config.md](modules/config.md) |
| `lib/sanitize.sh`, `lib/preflight.sh`, `lib/errors.sh` | [modules/safety.md](modules/safety.md) |
| `tests/**` | [modules/test-harness.md](modules/test-harness.md) |
| `.github/**`, `install.sh`, `scripts/**` | [modules/ci-and-install.md](modules/ci-and-install.md) |
| `skills/**`, `archive/**` | [modules/skills-and-archive.md](modules/skills-and-archive.md) |
| *(additive)* any shell file | [conventions/shell-conventions.md](conventions/shell-conventions.md) |
| *(additive)* `lib/**`, `bin/**` | [conventions/sanitization.md](conventions/sanitization.md), [conventions/artifact-contracts.md](conventions/artifact-contracts.md) |
| *(additive)* `tests/**`, `.github/**` | [conventions/testing-and-freeze.md](conventions/testing-and-freeze.md) |

## System overview

`bin/reqdrive` parses arguments and dispatches to one of ten commands
(`bin/reqdrive:679-727`); everything that touches an agent flows into
`run_pipeline` (`lib/run.sh:855`). That function runs pre-flight gates
(`lib/preflight.sh:165`), cuts `reqdrive/<slug>` from the configured base branch
(`lib/run.sh:911`), then **Phase 1** invokes `claude` once to write `prd.json`
(`lib/run.sh:962-997`, hard-aborting with exit 5 if no PRD appears). **Phase 2**
loops: `select_next_story` picks the highest-priority incomplete story by jq
(`lib/run.sh:413`), a quoted-heredoc prompt is built with `@@TOKEN@@`
substitution (`lib/run.sh:281`), one fresh `claude` process implements it
(`lib/run.sh:465`), then `testCommand` and a commit-format check run as
observation-only counters (`lib/run.sh:1059-1082`) and the scope check runs as
the loop's only hard gate (`lib/run.sh:1088-1093`). **Phase 3** re-runs the test
suite for real (`lib/verification.sh:85`) and writes `verification-summary.json`
(`lib/verification.sh:98`). The draft decision is taken at `lib/run.sh:1177-1178`
and passed to `create_pr` (`lib/pr-create.sh:78`), which assembles the body and
calls `gh`. **Phase 4** review is off by default and runs *after* the PR exists,
so it cannot influence the draft flag (`lib/run.sh:1195`).

State is per requirement under `.reqdrive/runs/<lowercased req-id>/`
(`lib/run.sh:685,691`); each Claude call is stateless and carries context only
through files (`lib/run.sh:447-478`).

## Requirement governance

Canonical docs: `tests/BEHAVIOR-SPEC.md` (202 stories),
`docs/superpowers/specs/2026-07-23-…-design.md` (140 reqs), `README.md` +
`docs/INTEGRATION.md` (150), `CLAUDE.md` (110) — **602 requirements** total. See
[requirements/register.md](requirements/register.md) for coverage and the nine
canon-vs-canon conflicts, and [requirements/drift-report.md](requirements/drift-report.md)
for **48 confirmed drift findings plus 8 confirmed defects that no requirement
covers**. [claims-audit.md](claims-audit.md) grades the project's stated
capabilities (summary and README claims) against this canon.

## Coverage & freshness

Read, not inferred: all of `bin/`, `lib/`, `.github/`, `install.sh`,
`templates/`, `skills/`, `archive/`, and the harness files under `tests/`;
`tests/simple-test.sh` was sampled structurally rather than line-by-line.
`bash tests/simple-test.sh` was executed on this machine: **202 passed, 0 failed,
exit 0**. Every drift entry carries an adversarial verifier verdict; 3 candidate
findings were refuted and are listed in the drift report so they are not
re-raised. Files matched by no module glob: the repo-root docs (`README.md`,
`CLAUDE.md`, `ROADMAP.md`, `LICENSE`, `docs/**`, dotfiles) — these are canon
*sources*, not code, and are governed rather than governing.
