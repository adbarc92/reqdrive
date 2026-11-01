# Convention: sanitization (canon)

## Rule

All user- and agent-supplied content passes through `sanitize_for_prompt`
before reaching a prompt; PR labels pass through `sanitize_label`; requirement
content is scanned against `DANGEROUS_PATTERNS`. CLAUDE.md:56 declares this a
**security boundary** covering "shell injection, path traversal, and dangerous
commands".

## Applies to

`lib/**`, `bin/**`

## Examples

- PRD fields sanitized before token substitution: lib/run.sh:299-302
- Requirement content sanitized: lib/run.sh:738
- Labels sanitized before `gh`, then expanded as a quoted array: lib/pr-create.sh:200,210,265
- Both prompt heredocs quoted, so nothing is re-expanded: lib/run.sh:213, :324
- The prompt file reaches the agent by stdin redirect, never `eval`: lib/run.sh:465

## Exceptions

**The boundary is narrower than the docs claim. Treat the following as true:**

- **No path-traversal protection exists at runtime.** `validate_file_path` (lib/sanitize.sh:112) has zero callers in `lib/` or `bin/`, and none of the 15 `DANGEROUS_PATTERNS` (lib/sanitize.sh:8-30) matches `../`, `..\`, a leading `/`, `~/`, or a symlink. Verified by execution: traversal probes pass the scan clean. → [drift CLD-006](../requirements/drift-report.md#CLD-006)
  - *Correctly scoped:* requirement **content** is never used as a filesystem path — it is only `cat`'d into the prompt — so scanning it for traversal would protect nothing. The genuine gap is the unvalidated **REQ-ID argument**, which reaches both the requirement-file glob (lib/run.sh:704) and `mkdir -p` (lib/run.sh:691,729). Verified: a REQ-ID of `../../../../pwndir` creates a directory outside the project root. That is operator-triggered, not attacker-reachable — the operator already has shell access.
- **Content scanning is unconditionally warn-only.** The single caller omits the `strict` argument (lib/run.sh:721), making the strict branch and the `--force` bypass that guards it both dead code. → [drift CLD-110](../requirements/drift-report.md#CLD-110)
- **`sanitize_for_prompt` now corrupts two of its three consumers.** Its `$`→`\$` escaping was needed for unquoted heredocs; the implementation prompt reverses it (lib/run.sh:317-321), but `build_planning_prompt` (lib/run.sh:276) and the PR review body (lib/pr-create.sh:52) do not. Measured: `Budget is $500 for ${TEAM}` reaches `prompt.md` as `Budget is \$500 for \${TEAM}`. The backtick→`'` rule also destroys code spans in published PR text. → [drift SANITIZE-PLANNING](../requirements/drift-report.md#SANITIZE-PLANNING)
- **One agent-controlled value reaches a glob unquoted.** `lib/run.sh:1077` interpolates the PRD-authored story id into a `[[ == ]]` pattern, and `lib/schema.sh:159` puts no charset constraint on `.id`. Verified: an id of `US-*` credits a stale prior-iteration commit. Blast radius is a reporting counter only — nothing gates on it. → [drift COMMIT-CHECK-FORGEABLE](../requirements/drift-report.md#COMMIT-CHECK-FORGEABLE)
- **Config strings are executed by design**: `eval "$REQDRIVE_TEST_COMMAND"` (lib/run.sh:1062, lib/verification.sh:85) and `bash -c` on `completionHook` (lib/run.sh:502) and `reviewCommand` (:646). A repo-local `reqdrive.json` is therefore arbitrary code execution — and the agent can write that file.
- `realpath` is used with inconsistent guards (lib/sanitize.sh:124 fails closed, :130 unguarded); unreachable today because the function is dead.
