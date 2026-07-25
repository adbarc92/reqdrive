# Convention: shell conventions (canon)

## Rule

The entry point sets `set -euo pipefail` (bin/reqdrive:6); libraries are
**sourced into that process**, never executed, so errexit governs all of them
regardless of their own headers. Libraries are nominally required to set `set -e`
(CLAUDE.md:230). Every modified `.sh` must pass `bash -n` before commit
(CLAUDE.md:231).

## Applies to

`bin/**`, `lib/**`, `tests/**`, `scripts/**`, `install.sh`

## Examples

- Entry point: `set -euo pipefail` (bin/reqdrive:6)
- Compliant libraries: `lib/run.sh:6`, `lib/validate.sh:5`, `lib/init.sh:4`, `lib/policy.sh:10`, `lib/verification.sh:54`
- Sourcing model — every reference is `source`, never `bash lib/x.sh` (bin/reqdrive:14,83,169-193,343-344,433-436,476-541)
- Logging: `log_info`/`log_warn`/`log_error` are defined in `lib/run.sh:15-17`; `bin/reqdrive:482-483` defines its own shims for `cmd_verify`, which never sources run.sh
- Errors: named `EXIT_*` constants from `lib/errors.sh:7-17`, not bare integers

## Exceptions

- **Six of eleven libraries set no shell mode** — `lib/config.sh`, `lib/errors.sh`, `lib/pr-create.sh`, `lib/preflight.sh`, `lib/sanitize.sh`, `lib/schema.sh` (measured). No concrete bug follows, because sourcing means the entry point's `set -euo pipefail` already applies. This is a documentation-conformance gap, not a defect. → [drift CLD-098](../requirements/drift-report.md#CLD-098)
- The inverse hazard is more real: the five libraries that *do* `set -e` at file top level mutate their sourcer's options. `tests/simple-test.sh` runs with `set +e` and works around this with a `(set -e; source …)` subshell at :374.
- `errexit` does **not** propagate into command substitutions without `shopt -s inherit_errexit`, which this repo never sets — so `x=$(failing_function)` continues silently. This is load-bearing: it is why a failing `select_next_story` does not abort the pipeline. (verified by execution)
- `set -e` is suppressed inside `if` conditions, which is how an agent timeout at `lib/run.sh:465` becomes a warning rather than an abort.
- `bash -n` coverage in CI omits `tests/**` and `scripts/**` (.github/workflows/ci.yml:31-44), which is how `scripts/setup-validation-env.sh` rotted undetected — though only semantically; it still parses. → [drift CLD-099](../requirements/drift-report.md#CLD-099)
- `lib/config.sh:36-39` calls `exit`, not `return`, so a sourcing caller cannot recover from a config failure.
- bash 4+ is assumed (`declare -A` at lib/errors.sh:21) but never version-checked. → [drift RDM-005](../requirements/drift-report.md#RDM-005)
