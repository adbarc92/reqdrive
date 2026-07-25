# cli (canon)

`bin/reqdrive` — 101 governing requirements.

## Purpose

The single entry point: parses arguments, enforces the tool preconditions,
dispatches ten commands, and implements every command that does **not** invoke
the agent (`status`, `logs`, `migrate`, `verify`, `launch`, `orchestrate`).

## Public interface

| Symbol | Kind | Anchor | Notes |
|--------|------|--------|-------|
| `reqdrive init` | cli | bin/reqdrive:680 | interactive wizard → [config.md](config.md) |
| `reqdrive run <REQ-ID>` | cli | bin/reqdrive:86 | `-i/--interactive` (default), `--unsafe`, `--dangerously-skip-permissions`, `--force`, `--resume` |
| `reqdrive launch <REQ-ID>` | cli | bin/reqdrive:588 | `nohup … run <ID> --unsafe` (:641); prints PID, exits 0 |
| `reqdrive status [REQ-ID]` | cli | bin/reqdrive:196 | PID liveness via `kill -0` (:256-259) |
| `reqdrive logs <REQ-ID>` | cli | bin/reqdrive:650 | tails `output.log` |
| `reqdrive validate` | cli | bin/reqdrive:176 | exit 3 on failure |
| `reqdrive migrate` | cli | bin/reqdrive:342 | adds `version` to pre-0.3.0 config/PRD |
| `reqdrive plan <REQ-ID>` | cli | bin/reqdrive:394 | Phase 1 only; **does** require `claude` (:395) |
| `reqdrive verify <REQ-ID> [--ref B]` | cli | bin/reqdrive:440 | exits 0 pass / 9 fail / 3 missing / 4 branch mismatch / 10 run live |
| `reqdrive orchestrate` | cli | bin/reqdrive:579 | pure stub: prints "Coming soon", exits 0 |
| `--version` / `--help` | cli | bin/reqdrive:716 / :719 | prints `reqdrive 0.3.0` |
| `check_tool` / `check_claude` | function | bin/reqdrive:18 / :31 | presence probes only |

## Invariants

- Every dispatch label is documented in README — machine-enforced by a doc-coverage rule. (bin/reqdrive:679-727 / tests/simple-test.sh:2963-2976)
- Every flag label accepted anywhere in the file is documented in README — likewise gated. (tests/simple-test.sh:3005-3021)
- Interactive is the default agent mode; only an explicit unsafe flag clears it, and the consumer fails safe when the variable is unset. (bin/reqdrive:92,102-105 / lib/run.sh:458)
- `launch` can never run in a permission-prompting mode: `--unsafe` is a hardcoded literal on the nohup line. (bin/reqdrive:641)
- All run-state paths are `.reqdrive/runs/<lowercased REQ-ID>/`, computed identically here and in `pipeline`. (bin/reqdrive:241,486,603,663 / lib/run.sh:685,691)
- `cmd_verify` performs every refusal check *before* sourcing `lib/verification.sh`, so no refusal path can write a summary. (bin/reqdrive:490-539 precede :541)
- `jq`, `git` and `gh` are required for every invocation, including offline ones. (bin/reqdrive:26-28)

## Data flows

- **dispatch**: bin/reqdrive:679 → `cmd_*` → `reqdrive_load_config` (lib/config.sh:34) → `run_pipeline` (lib/run.sh:855) for run/plan only
- **launch**: bin/reqdrive:632 (duplicate-PID check) → :641 `nohup "$reqdrive_bin" run "$ID" --unsafe > output.log` → child re-enters `cmd_run`
- **verify**: bin/reqdrive:491 (run dir) → :496 (summary) → :509 (live PID → 10) → :519-537 (branch/`--ref` → 4) → :541 source verification.sh → :566/570 exit 0/9

## Dependencies

Internal: `safety` (errors.sh sourced unconditionally at :14), `config`,
`pipeline`, `evidence`. External: bash 4+ (associative array in errors.sh),
`jq`/`git`/`gh` (hard-required at startup), `claude` (deferred to run/plan),
`nohup`, `kill`, `tail`, `tr`.

## Gotchas

- `VERSION` is duplicated: `bin/reqdrive:11` (what `--version` prints) and `lib/schema.sh:4` (what stamps artifacts). Nothing asserts they agree.
- `cmd_run`/`cmd_plan` call `check_claude` **before** parsing arguments, so `--help`-style mistakes on a claude-less machine fail with a dependency error. (bin/reqdrive:88,395)
- `launch` and `logs` are dispatched with only `"${1:-}"`, silently discarding extra arguments where `run`/`plan`/`verify` reject them. (bin/reqdrive:710,714)
- `reqdrive verify --ref <branch>` runs a real `git checkout` and never restores the caller's original branch. (bin/reqdrive:519)
- The same "no reqdrive.json" condition yields **two different exit codes**: 3 from `cmd_validate`, 1 from `reqdrive_load_config`. (bin/reqdrive:183 vs lib/config.sh:38) → [drift INT-013](../requirements/drift-report.md#INT-013)
- `kill -0` liveness cannot distinguish a recycled PID, and is unreliable under MSYS2. (bin/reqdrive:256-259)
- `cmd_migrate` rewrites files with `echo "$tmp" > "$file"` — truncate-then-write, not atomic. (bin/reqdrive:363-364,383-384)
- `gh` is a startup hard dependency even for wholly offline commands (`validate`, `migrate`, `status`, `logs`). (bin/reqdrive:26-28)
- The unsafe confirmation prompt only fires on a TTY, so piped/CI `run --unsafe` proceeds unprompted. (bin/reqdrive:159-166)

## Requirement coverage

101 governing reqs: **92 satisfied · 5 drifted · 1 unimplemented (roadmap) ·
1 intent-met · 2 not-code-verifiable**. Canon (intended) behavior for the
drifted ones — all of them exit-code or prerequisite contracts owned by
[safety](safety.md) and [ci-and-install](ci-and-install.md):

| REQ | Status | Canon (intended) | Link |
|-----|--------|------------------|------|
| INT-013 | drifted | exit 3 means bad `reqdrive.json` or missing requirement file | [drift-report](../requirements/drift-report.md#INT-013) |
| INT-014 | drifted | exit 4 means a git operation failed | [drift-report](../requirements/drift-report.md#INT-014) |
| INT-017 | drifted | exit 7 means the user sent SIGINT | [drift-report](../requirements/drift-report.md#INT-017) |
| RDM-009 | drifted | `claude` is needed only for `run` and `launch` | [drift-report](../requirements/drift-report.md#RDM-009) |
| CLD-106 | drifted | require bash 4.0+, jq, git, and an **authenticated** gh | [drift-report](../requirements/drift-report.md#RDM-008) |
| CLD-093 | unimplemented | `orchestrate` builds multi-requirement parallelism | roadmap — index.json#unbuilt_features |

Verified-good, and worth stating because they are commonly assumed broken:
`--version` prints `reqdrive 0.3.0` (measured); `orchestrate` exits 0 (measured);
`verify`'s five exit codes match the documented 0/9/3/4/10 exactly; every
documented command exists and every existing command is documented.

## Pointers

Pipeline internals: [pipeline.md](pipeline.md). Exit-code vocabulary:
[safety.md](safety.md). Config loading: [config.md](config.md).
