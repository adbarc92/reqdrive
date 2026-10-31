# safety (canon)

`lib/sanitize.sh`, `lib/preflight.sh`, `lib/errors.sh` — 113 governing
requirements. **Declared security boundary** (CLAUDE.md:56) — read
[../conventions/sanitization.md](../conventions/sanitization.md) alongside this.

## Purpose

Sanitizes user/agent content before it reaches a prompt or `gh`, gates the run
on pre-flight conditions, and owns the exit-code vocabulary.

## Public interface

| Symbol | Kind | Anchor | Notes |
|--------|------|--------|-------|
| `DANGEROUS_PATTERNS` | config | lib/sanitize.sh:8 | 15 shell-injection/dangerous-command regexes |
| `sanitize_for_prompt` | function | lib/sanitize.sh:36 | backtick→`'`, `$`→`\$` — **exactly two** substitutions |
| `sanitize_label` | function | lib/sanitize.sh:50 | ≤50 chars, strips `$ \ ; \| & > < "` and backtick |
| `validate_requirement_content` | function | lib/sanitize.sh:79 | `<content> [strict]`; strict is unreachable in production |
| `validate_file_path` | function | lib/sanitize.sh:112 | **dead code — zero runtime callers** |
| `run_preflight_checks` | function | lib/preflight.sh:165 | 5 blocking + 2 advisory checks |
| `EXIT_*` / `EXIT_MESSAGES` / `get_exit_message` | config/function | lib/errors.sh:7 / :21 / :38 | codes 0–10, incl. 9 `VERIFICATION_FAILED`, 10 `CONCURRENT_RUN` |
| `die` / `die_on_error` | function | lib/errors.sh:44 / :58 | **dead code — zero callers in lib/ or bin/** |

## Invariants

- `sanitize_for_prompt` transforms exactly two character classes and leaves everything else untouched. (lib/sanitize.sh:40,43 — verified by execution)
- `sanitize_label` output is ≤50 chars and contains no shell metacharacters. (lib/sanitize.sh:58-69)
- `run_preflight_checks` short-circuits: once a blocking check fails no later check runs, so only the first failure is reported. (lib/preflight.sh:176-192)
- `--force` skips preflight **wholesale** rather than relaxing individual checks. (lib/run.sh:694-700)
- Every exit code 0–10 has both a constant and an `EXIT_MESSAGES` entry, with `"Unknown error"` as the fallback. (lib/errors.sh:7-33,40)
- No sanitizer output is re-parsed by a shell: the prompt heredocs are quoted and the prompt file reaches `claude` via stdin redirect. (lib/run.sh:324, :465)
- Blocking preflight checks: git repo (:176), clean tree (:179), base branch exists (:183), requirements dir (:187), requirement file (:191). Advisory (cannot fail): branch conflicts (:196), testCommand configured (:200).

## Data flows

- **requirement content**: lib/run.sh:719 `cat` → :721 `validate_requirement_content` (warn-only) → :738 `sanitize_for_prompt` → prompt.md
- **PRD fields**: lib/run.sh:299-302 `sanitize_for_prompt` → :306-310 strip `@@` → :317-321 reverse `\$` → :399-403 token substitution
- **labels**: lib/config.sh `REQDRIVE_PR_LABELS` → lib/pr-create.sh:200,210 `sanitize_label` → :265 quoted array → `gh`

## Gotchas

- `validate_file_path` is defined and tested but **never called** from `lib/` or `bin/` — the documented path-traversal protection does not exist at runtime. (lib/sanitize.sh:112) → [drift CLD-006](../requirements/drift-report.md#CLD-006)
- `die`/`die_on_error` are likewise dead code. (lib/errors.sh:44,58)
- `validate_requirement_content`'s strict mode is unreachable: the only caller omits the `strict` argument, so the failure branch and the `--force` bypass guarding it are both dead. (lib/sanitize.sh:100-105 ← lib/run.sh:721) → [drift CLD-110](../requirements/drift-report.md#CLD-110)
- `sanitize_for_prompt`'s `$`→`\$` escaping is now **output corruption** everywhere it is not manually reversed — the implementation prompt reverses it, the planning prompt and the PR review body do not. (lib/run.sh:276, lib/pr-create.sh:52) → [drift](../requirements/drift-report.md#SANITIZE-PLANNING)
- The commit-verification signal is agent-forgeable: `lib/run.sh:1077` interpolates the PRD-authored story id unquoted into a `[[ == ]]` glob, and `schema.sh:159` puts no charset constraint on `.id`. (lib/run.sh:1077) → [drift COMMIT-CHECK-FORGEABLE](../requirements/drift-report.md#COMMIT-CHECK-FORGEABLE)
- `--force` also suppresses the "all PRs will be drafts" warning, because it skips `run_preflight_checks` entirely. (lib/run.sh:694-700)
- `realpath` is called twice with inconsistent guards — :124 fails closed with a misleading message on non-GNU hosts, :130 is unguarded and could fail *open*. Unreachable today only because the function has no callers. (lib/sanitize.sh:124,130)
- None of the three files sets a shell mode; inert because they are only sourced into `bin/reqdrive`, which sets `set -euo pipefail`. (lib/sanitize.sh:1)

## Requirement coverage

113 governing reqs: **98 satisfied · 14 drifted · 1 intent-met**. The drift
concentrates in two clusters — the security-boundary claims and the exit-code
contract. Canon (intended) behavior:

| REQ | Status | Canon (intended) | Link |
|-----|--------|------------------|------|
| CLD-006 / CLD-108 / RDM-070 | drifted | content is scanned for shell injection **and path traversal** | [drift-report](../requirements/drift-report.md#CLD-006) |
| CLD-110 | drifted | content validation is warn-only, with `--force` as the sole full bypass | [drift-report](../requirements/drift-report.md#CLD-110) |
| INT-013 | drifted | exit 3 = bad config / missing requirement file | [drift-report](../requirements/drift-report.md#INT-013) |
| INT-014 | drifted | exit 4 = git operation failed | [drift-report](../requirements/drift-report.md#INT-014) |
| INT-015 | drifted | exit 5 = Claude invocation failed | [drift-report](../requirements/drift-report.md#INT-015) |
| INT-016 | drifted | exit 6 = PR creation failed after retry | [drift-report](../requirements/drift-report.md#INT-016) |
| INT-017 | drifted | exit 7 = user sent SIGINT | [drift-report](../requirements/drift-report.md#INT-017) |
| INT-005 | drifted | clean working tree **on baseBranch** | [drift-report](../requirements/drift-report.md#INT-005) |
| DES-116 | drifted | block-mode findings reach the checkpoint | [drift-report](../requirements/drift-report.md#DES-116) |
| CLD-106 / RDM-009 / RDM-010 | drifted | the documented prerequisite set is enforced | [drift-report](../requirements/drift-report.md#RDM-008) |
| CLD-098 | drifted | library scripts set `set -e` | [drift-report](../requirements/drift-report.md#CLD-098) |

Verified good: `sanitize_label` is applied to every label reaching `gh`;
`sanitize_for_prompt` is applied to all four PRD fields and to requirement
content; the prompt heredocs are quoted; codes 9 and 10 exist with messages.

## Pointers

Where the sanitizers are called from: [pipeline.md](pipeline.md),
[pr.md](pr.md). Boundary analysis:
[../conventions/sanitization.md](../conventions/sanitization.md).
