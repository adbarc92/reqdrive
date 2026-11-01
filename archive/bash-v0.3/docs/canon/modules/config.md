# config (canon)

`lib/config.sh`, `lib/schema.sh`, `lib/validate.sh`, `lib/init.sh`,
`templates/**` — 128 governing requirements.

## Purpose

Finds and loads `reqdrive.json` into the `REQDRIVE_*` environment contract,
provides the JSON schema predicates for config/PRD/checkpoint, backs the
`validate` command, and writes the initial config in `init`.

## Public interface

| Symbol | Kind | Anchor | Notes |
|--------|------|--------|-------|
| `reqdrive_find_manifest` | function | lib/config.sh:11 | walks upward from `pwd` to `/` |
| `reqdrive_load_config` | function | lib/config.sh:34 | exports 12 `REQDRIVE_*` vars + 2 derived; **exits**, never returns non-zero |
| `reqdrive_get_req_file` | function | lib/config.sh:97 | first `<REQ-ID>*.md` glob match |
| `REQDRIVE_SCHEMA_VERSION` | config | lib/schema.sh:4 | `"0.3.0"` |
| `check_schema_version` | function | lib/schema.sh:10 | major-only compatibility |
| `validate_config_schema` | function | lib/schema.sh:50 | pure predicate; **not called at load time** |
| `validate_prd_schema` | function | lib/schema.sh:125 | top-level then per-story checks |
| `validate_checkpoint_schema` | function | lib/schema.sh:191 | soft-ignored by the resume path |

**Config fields actually read** (lib/config.sh:53-91), with real defaults:
`version` (no default), `requirementsDir` `docs/requirements`, `testCommand` `""`,
`model` `claude-sonnet-4-20250514`, `maxIterations` `10`, `baseBranch` `main`,
`prLabels` `["agent-generated"]`, `projectName` `""`, `completionHook` `""`,
`maxStoryRetries` `3`, `reviewCommand` `""`, `policy` `{}` (`scopeCheck` `warn`).
All twelve match the README table exactly; `maxStoryRetries` and `policy` are
absent from the CLAUDE.md table.

## Invariants

- The manifest is discovered by walking upward and terminating at the filesystem root. (lib/config.sh:15-29)
- `REQDRIVE_PROJECT_ROOT` is always `dirname(REQDRIVE_MANIFEST)`. (lib/config.sh:42-43)
- Every config field is optional — every schema check is `has()`-guarded, so a minimal `{}` config validates. (lib/schema.sh:62-81)
- Schema functions are pure predicates: they print to stderr and return 0/1, never `exit`. Enforcement is the call site's choice. (lib/schema.sh:117,183,219)
- Version compatibility is major-only: any `0.x.x` loads. (lib/schema.sh:33-42)
- `REQDRIVE_POLICY_SCOPE_CHECK` is CR-stripped after extraction because native Windows `jq` emits CRLF. (lib/config.sh:89-91)
- Both `validate.sh` failure paths exit `EXIT_CONFIG_ERROR` (3), never a bare 1. (lib/validate.sh:22,76 — measured)
- `passes` and `priority` are optional in the PRD schema; the pipeline compensates with `select(.passes != true)`. (lib/schema.sh:165-170, lib/run.sh:424)

## Data flows

- **load**: bin/reqdrive:170 → `reqdrive_find_manifest` lib/config.sh:11 → `check_schema_version` lib/config.sh:46 → 12 `jq -r … // default` reads :53-91 → exported env
- **validate**: bin/reqdrive:176 → lib/validate.sh:22 (`jq empty`) → :27 `validate_config_schema` → :76 exit 3

## Dependencies

Internal: `safety` (errors.sh for `EXIT_CONFIG_ERROR`), consumed by every other
module through the `REQDRIVE_*` contract. External: `jq` (every read and every
validation), coreutils `dirname`/`basename`/`cut`/`find`/`wc`.

## Gotchas

- `reqdrive validate` reports "Validation PASSED" and exits 0 for a manifest whose version `reqdrive run` refuses — `validate.sh` never calls `check_schema_version`. Measured. (lib/validate.sh:19-36) → [drift VALIDATE-FALSE-PASS](../requirements/drift-report.md#VALIDATE-FALSE-PASS)
- `validate` always prints "(1 errors)" regardless of violation count: `ERRORS` is incremented once per failed *check group*, and only one group exists. Cosmetic — each violation is still printed and the exit code is right. (lib/validate.sh:27-36)
- `reqdrive init` performs **no JSON escaping**; an answer containing `"` yields a `reqdrive.json` that fails `jq empty` while init prints "Done!". A crafted answer can also inject sibling keys. Measured. (lib/init.sh:57-68) → [drift RDM-012](../requirements/drift-report.md#RDM-012)
- `attempts` is never schema-validated, yet `select_next_story` compares it numerically — `"attempts": "lots"` makes a story permanently unselectable and the loop then logs "All stories complete!". Measured. (lib/schema.sh:125-184) → [drift ATTEMPTS-UNVALIDATED](../requirements/drift-report.md#ATTEMPTS-UNVALIDATED)
- `validate_config_schema` type-checks 9 fields but not `version` and not `maxStoryRetries`. (lib/schema.sh:70-81)
- PRD story-level validation is gated on the top-level checks passing, so one missing top-level key silently skips all per-story checks. (lib/schema.sh:154)
- `policy.riskTiers` keys are unrestricted, so a tier name the matcher never probes validates clean. (lib/schema.sh:105-113)
- Because `validate_config_schema` is not wired into load (deliberate — CLD-075), an out-of-enum `policy.scopeCheck: "blocking"` loads and silently degrades the gate to warn. Measured. (lib/policy.sh:82)
- `reqdrive_get_req_file` returns the **first** glob match, so `REQ-1` can match `REQ-10-*.md`. (lib/config.sh:101-106)
- `reqdrive_load_config` calls `exit`, not `return` — anything sourcing it cannot recover. (lib/config.sh:36-39)

## Requirement coverage

128 governing reqs: **122 satisfied · 5 drifted · 1 intent-met**.

| REQ | Status | Canon (intended) | Link |
|-----|--------|------------------|------|
| RDM-012 / CLD-030 | drifted | `init` creates a valid `reqdrive.json` | [drift-report](../requirements/drift-report.md#RDM-012) |
| INT-013 | drifted | exit 3 means a bad `reqdrive.json` | [drift-report](../requirements/drift-report.md#INT-013) |
| CLD-091 | drifted | `pr-create.sh` consumes the policy exports | [drift-report](../requirements/drift-report.md#CLD-091) |
| DES-081 | drifted | `DOC_EXEMPT` holds the specified 2–3 names | [drift-report](../requirements/drift-report.md#DES-081) |
| CLD-098 | drifted | library scripts set `set -e` | [drift-report](../requirements/drift-report.md#CLD-098) |
| RDM-038 | intent-met | `version` defaults to `"0.3.0"` — code warns on absence instead of silently defaulting, which is stronger; amend the req. See the register's spec-stale table |

`CLD-075` (config-load-time validation stays deferred) is **satisfied**: the
omission is a recorded decision at CLAUDE.md:187, not drift.

## Pointers

Consumers of the env contract: [pipeline.md](pipeline.md),
[evidence.md](evidence.md). Artifact versioning:
[../conventions/artifact-contracts.md](../conventions/artifact-contracts.md).
