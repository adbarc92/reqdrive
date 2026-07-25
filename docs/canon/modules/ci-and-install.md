# ci-and-install (canon)

`.github/**`, `install.sh`, `scripts/**` — 30 governing requirements.

## Purpose

Runs the enforcement gates on every push/PR to `main`, and installs the CLI onto
a developer's PATH.

## Public interface

| Symbol | Kind | Anchor | Notes |
|--------|------|--------|-------|
| `lint` job | ci | .github/workflows/ci.yml:10 | shellcheck over an **explicit hand-maintained file list** (:29) |
| `syntax-check` job | ci | .github/workflows/ci.yml:31 | `bash -n` on `bin/`, `lib/`, `install.sh` only |
| `test-simple` job | ci | .github/workflows/ci.yml:46 | `bash tests/simple-test.sh` |
| `test-bats` job | ci | .github/workflows/ci.yml:55 | unit → e2e → assert zero e2e skips (:69-75) |
| `oracle-gate` job | ci | .github/workflows/ci.yml:77 | `oracle-gate.sh` + `gate-selftest.sh` |
| `launch-lifecycle` job | ci | .github/workflows/ci.yml:89 | LAUNCH-TEST-PLAN cases 1/4/6 |
| `install.sh` | cli | install.sh:1 | prereq loop, clone-or-pull, chmod, rc-file PATH append |
| `scripts/shellcheck` | cli | scripts/shellcheck:1 | docker wrapper pinning `koalaman/shellcheck:stable` |
| `scripts/setup-validation-env.sh` | cli | scripts/setup-validation-env.sh:1 | **dead code** — see gotchas |

## Invariants

- All six jobs run on `ubuntu-latest`, none declares `needs:`, so they run in parallel and any failure fails the build. (.github/workflows/ci.yml:12,33,48,57,79,91)
- CI never swallows a test exit code: `continue-on-error` appears zero times, and the only `|| true` absorbs `grep`'s zero-match status on a step already covered by an unmasked one. (.github/workflows/ci.yml:73)
- CI triggers only on push to `main` and PRs targeting `main` — no tag, schedule, or manual dispatch. (.github/workflows/ci.yml:3-7)
- The three README doc-coverage rules are frozen in the oracle lock as US-DOC-01/02/03, so weakening them trips the gate. (tests/simple-test.sh:2962-3021)
- `install.sh`'s PATH append is idempotent. (install.sh:47-48)
- `install.sh` checks tool **presence** only — never version, never authentication — for all five tools. (install.sh:12-17)

## Data flows

- **CI**: push/PR → 6 parallel jobs → `test-simple` runs the suite; `oracle-gate` runs it again inside `oracle-gate.sh:46` and compares against `tests/oracle.lock.json`
- **install**: install.sh:12 prereq loop → :25 clone/ff-pull → :29 chmod +x → :33-57 rc-file PATH append (zsh/bash/fish only)

## Dependencies

Internal: the whole `test-harness` module (its scripts are the CI steps),
`bin/`+`lib/` (lint and chmod targets), `README.md` (asserted against).
External: GitHub Actions `ubuntu-latest`, `actions/checkout@v4`, apt
`shellcheck` and `bats`, `jq`/`git`/`sha256sum`/`timeout`, `gh` (presence only),
`claude` (required by install.sh, **absent from CI**), docker (scripts/shellcheck).

## Gotchas

- `tests/oracle.lock.json` records `environment.claude: true`, but CI installs no `claude` and the gate never reads the `environment` field — the lock was generated where it is not enforced, contradicting design decision D8. (tests/oracle-gate.sh:64,69) → [drift DES-008](../requirements/drift-report.md#DES-008)
- `scripts/setup-validation-env.sh` would fail at runtime: it copies `templates/prompt.md.tpl` (:212, gone), sources `lib/prd-gen.sh`/`agent-run.sh`/`verify.sh` (:262,270,275, all archived), calls `reqdrive_load_config_path` (:299, undefined), and emits a v0.1.x manifest. It passes `bash -n` — the rot is semantic, so extending CI's syntax check would **not** catch it. → [drift CLD-099](../requirements/drift-report.md#CLD-099)
- `scripts/**` is invisible to both the shellcheck list (:29) and the `bash -n` job (:37-44).
- `install.sh` clones `https://github.com/user/reqdrive.git` — a literal placeholder matching README.md:30. (install.sh:25)
- `install.sh` demands `claude` before installing anything, inverting the CLI's own deliberate deferral. (install.sh:12 vs bin/reqdrive:26-39)
- `reqdrive launch` never calls `check_claude`; the detached child does, so the dependency error lands in `output.log` while `launch` exits 0 reporting success. (bin/reqdrive:588,641)
- The e2e skip assertion runs bats a third time and pipes into `grep`, so an empty bats output makes the check pass vacuously. (.github/workflows/ci.yml:69-75)
- No job sets `timeout-minutes`.
- `install.sh` writes no rc file for shells outside {zsh, bash, fish}. (install.sh:34-39)

## Requirement coverage

30 governing reqs: **15 satisfied · 11 drifted · 2 intent-met ·
1 unimplemented (roadmap) · 1 not-code-verifiable**. This module has the highest
drift density in the repo, and it is almost entirely *unenforced prerequisites*.

| REQ | Status | Canon (intended) | Link |
|-----|--------|------------------|------|
| RDM-008 / INT-006 | drifted | `gh` is authenticated with push and PR-create permission | [drift-report](../requirements/drift-report.md#RDM-008) |
| RDM-009 | drifted | `claude` is needed only for `run`/`launch` | [drift-report](../requirements/drift-report.md#RDM-009) |
| RDM-010 | drifted | `timeout` and `sha256sum` are required prerequisites | [drift-report](../requirements/drift-report.md#RDM-010) |
| RDM-005 | drifted | bash 4.0+ is required | [drift-report](../requirements/drift-report.md#RDM-005) |
| INT-007 | drifted | `claude` is installed **and authenticated** | [drift-report](../requirements/drift-report.md#RDM-008) |
| CLD-058 / CLD-106 | drifted | the documented dependency set is the real one | [drift-report](../requirements/drift-report.md#CLD-058) |
| CLD-099 | drifted | every modified `.sh` passes `bash -n` | [drift-report](../requirements/drift-report.md#CLD-099) |
| DES-008 | drifted | the lock is generated in the CI environment | [drift-report](../requirements/drift-report.md#DES-008) |
| DES-120 | drifted | the WORKFLOW.md L2→L0 correction is applied | [drift-report](../requirements/drift-report.md#DES-120) |
| CLD-095 | unimplemented | `gh pr checks` polling | roadmap — index.json#unbuilt_features |

**Coverage hole:** there is no Windows/MSYS2 or macOS runner. All six jobs are
`ubuntu-latest`, yet MSYS2 is the design doc's primary platform and README.md:25
promises Git-Bash/WSL2 support. Nothing verifies it.

## Pointers

What the gates enforce: [test-harness.md](test-harness.md). Prerequisite
contract: [safety.md](safety.md).
