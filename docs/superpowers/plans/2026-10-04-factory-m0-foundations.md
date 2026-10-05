# Factory M0: reqdrive foundations — Implementation Plan

> **For agentic workers:** steps use checkbox (`- [ ]`) syntax; tick each as you finish it. Each
> lane below is executed by one agent, alone, in its own worktree. Read "Global Constraints"
> and your own lane; you do not need the other lanes. Every code block is the exact content to
> write: do not paraphrase it, and do not "improve" it. If something here does not match what
> you find, stop and report; do not guess.

**Goal:** Archive the Bash implementation, stand up the Rust workspace with its test tiers,
gates and CI, and build a walking skeleton: `reqdrive harness --fake` drives one scripted unit
through all seven stages on protocol 0.2, with no agent, no container and no network, and
passes the control plane's conformance kit.

**Architecture:** `reqdrive` becomes a cargo workspace of small crates with one direction of
dependency: a pure stage machine (`engine`), seams with fakes for containers (`workspace`) and
agents (`runtime`), a protocol speaker over stdio (`speaker`), and a binary that only wires
them (`cli`). An `xtask` crate is the test runner and holds three structural gates (dependency
direction, registry parity, a hash lock over contract tests). The skeleton's machine and wire
are real; its stage bodies are fakes driven by a scenario file.

**Tech Stack:** Rust 1.93.1 (edition 2021, pinned in `rust-toolchain.toml`), cargo workspaces,
`clap` 4, `serde` 1, `serde_json` 1, `sha2` 0.10; std threads and channels, no async. The
contract crates `harness-protocol`, `factory-spec` and `factory-presets` come from
`https://github.com/adbarc92/command-center` at tag `contracts-v0.2.0`. GitHub Actions on
`ubuntu-latest` and `windows-latest`.

**Spec:** The ReqDrive factory design v0.4, in the private nexus repository: https://github.com/adbarc92/nexus/blob/main/docs/specs/2026-10-04-reqdrive-factory-design.md

## Global Constraints

**The lanes.** Four, with exclusive file ownership. A lane writes only what its "Owns" lists.

| Lane | Runs | Owns |
|---|---|---|
| RD-COORD | First, alone | Everything in the repository at that moment |
| RD-FORMS | After RD-COORD merges, and after the milestone 1 harness plan exists | `forms/<crate>.md` for milestone 1's crates, and their rows in `forms/registry.md` |
| RD-SKEL | After RD-COORD and RD-FORMS merge, and after the tag `contracts-v0.2.0` exists | `crates/speaker/**`, `crates/engine/**`, `crates/runtime/src/fake.rs`, `crates/workspace/src/fake.rs`, `crates/cli/**`, and the few shared lines its tasks name |
| SANDBOX | After RD-COORD merges | `docs/repo-config.md` here; `.reqdrive/config.toml` and its named companions in two sandbox repositories |

**Rules for every lane.**

- Work only in your worktree. Never edit, commit, stash or switch branches in the main checkout
  at `D:\MajorProjects\INFRASTRUCTURE\reqdrive`.
- Need a change in a file you do not own? Do not make it. Put it in your final report.
- Test first: write the test, run it, watch it fail, then write the code (doctrine C1).
- Finish by pushing your branch and opening a pull request against `factory/m0`. Do not merge,
  do not push to `main`, do not force-push.
- Commit messages and pull-request bodies carry **no `Co-Authored-By` line and no "Generated
  with" footer.**
- Spend nothing and reach nothing live: no model call, no deploy, no publish.
- Run every command under your lane's "Verify" and report its real output, failures included.
- This repository is **public**. The design is private. Never paste a sentence from it here.
- **Create and edit files with your file tool, never by typing a here-document into a command
  line**: quoting differs between shells and mangles content. (A script file that itself
  contains a here-document, run with `bash file.sh`, is fine.) Commands in
  this plan are for Git Bash; do not mix PowerShell syntax into them.

**Decisions this plan carries. They are settled; do not reopen them.**

1. **Crates.** `engine`, `workspace`, `runtime`, `oracle`, `map`, `controls`, `payload`,
   `ledger`, `speaker` are libraries under `crates/`, each with a `testkit` cargo feature. `cli`
   is the `reqdrive` binary (with a library half) and wires the others. `xtask` is the runner. A
   crate's package name is its directory name.
2. **Dependency direction**, checked by `cargo xtask deps` from `cargo metadata` and a source
   scan: `engine` depends on no I/O crate; only `workspace` may name a Docker client; a process
   may be started only in `workspace` and in `crates/runtime/src/adapters/`; only `cli` chooses
   implementations. Which workspace crate may depend on which is one table,
   `ALLOWED_INTERNAL` in `xtask/src/deps.rs`.
3. **Contract crates** are git dependencies pinned to the tag `contracts-v0.2.0`. RD-COORD's
   scaffold does not depend on them; RD-SKEL adds them as its first task.
4. **Six test tiers, one command each:** `cargo xtask test static | unit | contract |
   integration | e2e | live`.
   - `static`: format check, clippy with warnings denied, `deps`, `parity`.
   - `unit`: each crate's library tests, one crate at a time. No Docker, network or token.
   - `contract`: the freeze gate, every locked contract test target, and the conformance kit
     run against `reqdrive harness --fake`.
   - `integration`, `e2e`, `live`: exist, and print `no tests in this tier yet` while empty.

   **The tier naming rule.** It is the program's rule, the same in the control plane's
   repository, and it is stated here once. A test inside `src/` is a `unit` test. A test
   target under `crates/<crate>/tests/` is placed by its file name and by nothing else; the
   first row that matches wins:

   | File name under `tests/` | Tier |
   |---|---|
   | `e2e_*.rs` | `e2e` |
   | `live_*.rs` | `live` |
   | `*_it.rs` | `integration` |
   | `characterisation_*.rs` | `unit`: it runs with the crate's own tests |
   | any other name | `contract` |

   The rule is one function, `xtask::tier_of_test_target`. It is total, so no test target is
   left out of every tier. Two consequences: a test that needs Docker, a network or a token
   must be named for `integration`, `e2e` or `live`; and every other file under `tests/` is a
   contract test, hash-locked (decision 7). This plan's three are named `contract_*.rs` by
   convention, not because the name places them.
5. **CI** runs `static`, a per-crate `unit` matrix on `ubuntu-latest` and `windows-latest`, and
   `contract`. (This plan also runs `contract` on Windows: the harness's stdio is what the
   Windows control plane will use. It is one extra job and can be cut.)
6. **The conformance kit** is the binary `harness-conformance`, built from the control plane's
   repository at the same tag as the contract crates. The contract tier installs it once with

   ```bash
   cargo install --git https://github.com/adbarc92/command-center --tag contracts-v0.2.0 \
     harness-conformance --bin harness-conformance --locked --root .kit/contracts-v0.2.0
   ```

   and runs it as

   ```bash
   .kit/contracts-v0.2.0/bin/harness-conformance --wall-clock-secs 30 --grace-secs 5 -- \
     <absolute path>/target/debug/reqdrive harness --fake
   ```

   The kit's syntax is `harness-conformance [--wall-clock-secs N] [--grace-secs N] -- <harness
   command> [args...]`; it exits 0 only when no case failed and ends with one line,
   `<n> passed, <n> skipped, <n> failed`. `xtask` reads the tag from `cargo metadata`, so the
   kit can never be a different version from the wire types. A skipped case fails the tier.
7. **Locked contract tests** (doctrine B2, B3). `forms/contract.lock.json` holds the SHA-256 of
   every contract test target and of the gate's own source. `cargo xtask lock check` enforces it;
   `cargo xtask lock accept` rewrites it. Run `accept` only where a step says to, and name the
   lock's diff in your pull-request body: the owner's review of that diff is the approval.
8. **What the skeleton sends**, in order, for one unit:
   - `provisioned` is the first event, before anything that could be slow.
   - Each of the seven stages sends `stage{started}` and `stage{finished}`. The observation a
     stage produced follows that stage's `finished` and precedes the next `started`. So no
     `stage` event ever falls between `oracle_frozen` and `gate/request`, or after `empty_diff`.
   - `oracle_frozen` carries a freeze payload at every tier. At T2 and T3 `gate/request`
     follows it directly and the harness waits for the answer.
   - `build_finished`, then `checks_passed` (or `checks_failed`, or `empty_diff`), then
     `review_finished`. The harness loops Green, Check and Review until a review has zero
     unresolved blockers and the round count has reached the work order's `min_review_rounds`.
   - `unit/result` is last, and the process exits 0.
   - A `pr_open` result carries evidence. So does a `no_change` result: the protocol requires
     it, and its `branch` and `head_sha` name the commit that holds the frozen tests the
     harness wrote, which the control plane then runs against the base. In `no_change`
     evidence there are no control results and no review, because nothing was built.
   - A rejected gate ends `failed`, detail `oracle rejected`. `unit/halt` and `unit/abandon`
     are answered, and the process exits without a result. On `resume{oracle_frozen: true}`:
     `provisioned`, then Green, Check, Review and Deliver, with no freeze and no gate.
   - **A line from the control plane that cannot be read is fatal for the unit.** The
     protocol's reader reports two such lines: one that is not UTF-8 (`InvalidUtf8`) and one
     longer than `MAX_LINE_BYTES` (`LineTooLong`). The first might have been an abandon or a
     gate answer; the second leaves the reader in the middle of a line. So neither is
     skipped: the harness reads nothing further, writes the reason to stderr, and ends the
     unit as it does when stdin closes, with no result. A line that is readable text but not
     a JSON-RPC message is a different case and is dropped.
9. **Exit codes of `reqdrive harness`:** 0 when a result was sent, or the unit was interrupted
   and said so, or stdin closed or became unreadable; 1 for a fault in the harness; 2 for bad
   arguments or an unusable scenario; 3 when the handshake failed.

**Names from protocol 0.2 this plan relies on** (from `harness-protocol` at the tag; do not
rename them, and do not define your own copies): `PROTOCOL_VERSION`, `InitializeParams {
protocol_version, accepted_versions }`, `InitializeResult`, `HarnessInfo`, `Capabilities {
isolation, metering, gates, delivery, resume, halt, holdouts, controls, network, profiles,
kinds, presets }`, `Isolation`, `Metering`, `GateKind`, `Delivery`, `Network`, `ControlKind`,
`UnitKind`, `PresetInfo`, `WorkOrder` (with optional `kind`, `spec`, `source`, `scope`,
`config`, `controls`, `profile`, `parent`, `resume`), `Tier::requires_oracle`, `Observation`
(with `OracleFrozen { freeze: Option<OracleFreeze> }`), `OracleFreeze`, `FrozenFile`,
`UnitEvent::{Observed, Stage, Log}`, `Stage`, `StageStatus`, `LogStream`, `GateRequest::Oracle
{ test_files, hash, summary, holdout_files, holdout_hash }`, `GateReply`, `UnitResult {
outcome, evidence, failure, stop }`, `Outcome`, `Evidence` (with `spec_hash`, `map`,
`test_report`, `controls`, `review`), `DeliveryEvidence`, `TestRun`, `TestReport`,
`ControlResult`, `ControlStatus`, `ReviewEvidence`, `Failure`, `ErrorScope`, `Stop`,
`StopReason`, `Empty`, `RpcMessage`, `MessageKind`, `method`, `error_code`, `read_message`,
`write_message`, `ReadError` (five variants: `Eof`, `Malformed`, `InvalidUtf8`, `LineTooLong`,
`Io`), `MAX_LINE_BYTES`, `monitor::{ProtocolMonitor, Inbound}`, `file_sha256`, `bundle_hash`,
`negotiate`. From `factory-presets`: `PRESETS_VERSION`, `preset`. From `factory-spec`:
`sha256_hex`.

> **If the tagged crates differ.** The tag did not exist when this plan was written. Its code
> was compiled and tested against the three contract crates as the control plane's milestone 0
> plans build them, which is what the tag is meant to hold. If a struct at the real tag still
> has a field this plan does not set, or a name is spelt differently, the build fails at
> RD-SKEL Task 1 or soon after. Do not patch around it and do not edit a contract crate:
> stop, and report the exact compiler error. The fix is a decision for the owner.

## Owner actions this plan depends on

| # | Action | Unblocks |
|---|---|---|
| A1 | Merge this plan to `main`, and say go for RD-COORD | RD-COORD |
| A2 | Review and merge RD-COORD's pull request into `factory/m0` | RD-FORMS, SANDBOX |
| A3 | The milestone 1 harness plan (`docs/superpowers/plans/2026-10-04-factory-m1-harness.md`) exists on `main` | RD-FORMS |
| A4 | Approve the Forms: read RD-FORMS's pull request, then change each approved Form's `- status: draft` to `- status: frozen` (or tell the reviewing session to) and merge | RD-SKEL; milestone 1 |
| A5 | Approve documenting the Form, registry and repository-configuration formats in this public repository (`docs/forms.md`, `docs/repo-config.md`): the formats only, restated | Merging RD-COORD and SANDBOX |
| A6 | In `command-center`: merge its `factory/m0` to `main` and push the tag `contracts-v0.2.0` | RD-SKEL |
| A7 | Create the second sandbox repository: `gh repo create adbarc92/command-center-agent-sandbox-cargo --private --add-readme --description "Throwaway sandbox for reqdrive agent runs on the cargo preset"` | SANDBOX Task 3 |
| A8 | Read the findings of spikes S6 (test ids and reports) and S7 (offline runs) | SANDBOX Task 4 |
| A9 | Branch protection on `reqdrive`: require the check named `all checks` on `main` and on `factory/**` | Every check being required |
| A10 | Review each lock diff (`forms/contract.lock.json`) named in a pull-request body | Merging RD-SKEL |
| A11 | Watch the proof (`cargo xtask test contract` prints the kit's cases passing), then merge `factory/m0` to `main` | Milestone 1 |

## Review Focus

Five ways this can fail that an ordinary task list would not test. Each has a named test in the
task that owns it.

| # | Failure | Why it bites | Test, and where |
|---|---|---|---|
| 1 | **The harness deadlocks when its stdout pipe fills.** | Pipes hold a few kilobytes. A harness that stops reading stdin while it is blocked writing stdout, facing a control plane that is itself writing, hangs both for good | `a_flood_on_stdin_while_stdout_is_unread_does_not_deadlock`, RD-SKEL Task 8. It was checked by mutation: with a bounded inbound queue it fails with its deadlock message |
| 2 | **stdin closes in the middle of a unit.** | The control plane died. A harness that keeps going burns spend for nobody, and one that reports a result reports it to no one | `i6_a_closed_input_stops_the_unit_and_stays_stopped` (Task 6), `an_input_that_closes_mid_unit_ends_the_unit_quietly` (Task 7), `closing_stdin_mid_unit_ends_the_process_without_a_result` (Task 8) |
| 3 | **A work order arrives without the fields protocol 0.2 added.** | Every new field is optional on the wire, and the conformance kit's own work order has none of them. A harness that unwraps one crashes on the first real message | `i2_a_work_order_in_the_0_1_shape_is_accepted` (Task 6), `a_work_order_without_the_0_2_fields_runs_and_claims_no_spec` (Task 7) |
| 4 | **CRLF, or a byte-order mark, in a file this code parses.** | The owner's machine is Windows. A scenario saved by an editor there, or a Form or lock checked out with CRLF, must read the same as on Linux, and a locked file's hash must not change with the platform | `crlf_line_endings_and_a_byte_order_mark_change_nothing` (RD-SKEL Task 3), `a_scenario_saved_with_crlf_and_a_byte_order_mark_is_read_from_disk` (Task 8), `crlf_line_endings_parse_the_same` (RD-COORD Task 5), `the_hash_ignores_crlf_and_nothing_else` (RD-COORD Task 6) |
| 5 | **Windows path separators in evidence.** | Hashes are taken over repository paths. `tests\a.rs` and `tests/a.rs` must be one path, or the verifier on another platform computes a different hash and calls it tampering | `repository_paths_always_use_forward_slashes` (RD-SKEL Task 4), `a_windows_spelling_of_a_test_path_changes_neither_the_path_nor_a_hash` and `a_windows_host_path_survives_the_wire_unchanged` (Task 7) |

Two more are covered by exact-transcript tests in RD-SKEL Task 7 and are worth a reviewer's eye:
a `stage` event placed between `oracle_frozen` and `gate/request` (the supervisor allows only
logs, metrics, findings and errors there), and a harness that sends anything after `empty_diff`
except its result.

A third, found when the skeleton was first built against the real protocol crate: a line
from the control plane that the reader cannot decode. It is tested at three levels:
`a_line_that_is_not_utf8_ends_the_input_for_good` and
`a_line_over_the_limit_ends_the_input_for_good` (RD-SKEL Task 5), and
`a_line_that_is_not_utf8_ends_the_unit_without_a_result_and_says_why` (Task 8). And every
way a unit can end is replayed through the protocol's own monitor, the judge the control
plane uses, in `every_way_a_unit_ends_is_legal_to_the_protocols_own_monitor` (Task 7).

---

## Lane RD-COORD

**Owns:** everything in the repository when it starts. It moves the Bash tree, and creates
`Cargo.toml`, `Cargo.lock`, `rust-toolchain.toml`, `.cargo/config.toml`, `.gitignore`,
`.gitattributes`, `.github/workflows/ci.yml`, `xtask/**`, every `crates/<crate>/**` as an empty
skeleton, `forms/registry.md`, `forms/contract.lock.json`, `README.md`, `CLAUDE.md`,
`archive/README.md`, `docs/forms.md`, `docs/STATUS.md`, `docs/ROADMAP.md`.

**Reads:** this plan; the repository as it stands at `origin/main`.

**Worktree and branch:** worktree `D:\MajorProjects\.swarm-wt\m0-rd-coord`. It creates the
integration branch `factory/m0` from `origin/main` and pushes it, then works on
`feat/m0-scaffold` and opens a pull request against `factory/m0`.

**Needs:** owner action A1. `bash`, `jq` and `sha256sum` on the path (for one verification of
the archived suite); `rustup`.

**Blocks:** RD-FORMS, RD-SKEL, SANDBOX.

**Verify** (from the worktree root; every line must hold):

| Command | Expected |
|---|---|
| `git ls-files \| grep -c '^archive/bash-v0.3/'` | `103` |
| `cargo xtask test static` | ends `deps: OK (11 crates, 31 source files)` then `parity: OK (4 gates, 0 Forms)`; exit 0 |
| `cargo xtask test unit` | `xtask` reports `40 passed`, `cli` reports `1 passed`, the other nine `0 passed`; ends `unit: OK (11 crate(s), one at a time)` |
| `cargo xtask test contract` | `lock: OK (0 locked contract tests unchanged)` then `contract: no tests in this tier yet` |
| `cargo xtask test integration`, `e2e`, `live` | each prints `<tier>: no tests in this tier yet`; exit 0 |
| `cargo run -q -p cli --bin reqdrive -- harness; echo $?` | a line on stderr saying no command is built yet; `2` |
| `gh pr checks <the PR>` | `static`, 22 `unit` jobs, 2 `contract` jobs and `all checks` all pass |

### Task 1: Create the branches and archive the Bash tree

**Files:**
- Move: every tracked file except `LICENSE`, `.gitignore`, `.gitattributes` and plan files
  dated `2026-10-04`, to the same path under `archive/bash-v0.3/`
- Modify: `.gitattributes`
- Create: `archive/README.md`

**Interfaces:**
- Consumes: `origin/main`.
- Produces: the branch `factory/m0` on the remote; the directory `archive/bash-v0.3/`, in which
  every file keeps the relative path it had at the repository root.

- [ ] **Step 1: Create the worktree and the integration branch**

```bash
git -C /d/MajorProjects/INFRASTRUCTURE/reqdrive fetch origin
git -C /d/MajorProjects/INFRASTRUCTURE/reqdrive worktree add --no-track -b feat/m0-scaffold \
  /d/MajorProjects/.swarm-wt/m0-rd-coord origin/main
cd /d/MajorProjects/.swarm-wt/m0-rd-coord
git push origin origin/main:refs/heads/factory/m0
git ls-remote --heads origin factory/m0
```

Expected: the last command prints one line ending `refs/heads/factory/m0`. Every later command
in this lane runs from `/d/MajorProjects/.swarm-wt/m0-rd-coord`.

- [ ] **Step 2: Record what is there**

```bash
git ls-files | wc -l
git ls-files | grep -v -e '^docs/superpowers/plans/2026-10-04-' | wc -l
```

Expected: the second number is `106`. If it is not, the tree has changed since this plan was
written: stop and report the output of `git ls-files`.

- [ ] **Step 3: Move the tree**

The older `archive/` folder goes inside the new one, so the archived tree is a whole snapshot
and every relative reference in its documents and tests still holds.

```bash
mkdir -p archive/bash-v0.3/archive archive/bash-v0.3/.github archive/bash-v0.3/docs/superpowers/plans
git mv archive/docs archive/bash-v0.3/archive/docs
git mv archive/v1-complex archive/bash-v0.3/archive/v1-complex
git mv bin lib tests templates skills scripts install.sh README.md CLAUDE.md ROADMAP.md archive/bash-v0.3/
git mv .github/workflows archive/bash-v0.3/.github/workflows
git mv docs/INTEGRATION.md docs/LAUNCH-TEST-PLAN.md docs/MARCHING_ORDERS_2026-02-09.md \
  docs/PIPELINE-ANALYSIS.md docs/QUICKSTART.md docs/SIMPLIFICATION-SUMMARY.md docs/STATUS.md \
  docs/VERIFICATION-PLAN.md docs/audits docs/canon archive/bash-v0.3/docs/
git mv docs/superpowers/specs archive/bash-v0.3/docs/superpowers/specs
git mv docs/superpowers/plans/2026-07-23-reqdrive-roadmap-completion.md \
  archive/bash-v0.3/docs/superpowers/plans/
```

- [ ] **Step 4: Check that it is a pure move**

```bash
git ls-files | grep -c '^archive/bash-v0.3/'
git ls-files | grep -v '^archive/bash-v0.3/'
git status --short | grep -v '^R ' || echo "renames only"
```

Expected: `103`; then exactly `.gitattributes`, `.gitignore`, `LICENSE` and any plan file dated
`2026-10-04`; then `renames only`.

- [ ] **Step 5: Re-point the line-ending rule and describe the archive**

Replace `.gitattributes` with:

```
# The archived Bash suite compares this lock byte for byte.
archive/bash-v0.3/tests/oracle.lock.json text eol=lf
# Written by `cargo xtask lock accept`, always with LF.
forms/contract.lock.json text eol=lf
```

Create `archive/README.md`:

````markdown
# Archive

`bash-v0.3/` is the Bash implementation of reqdrive, version 0.3, exactly as it stood when the
Rust rebuild began: its code, its tests, its documents, its CI workflow and its own older
`archive/` folder. Every path inside it is the path the file had at the repository root, so
every relative reference in its documents and tests still holds.

It is the reference for how things used to behave. It is not maintained, nothing in the Rust
workspace depends on it, and CI does not run it. Do not edit it.

To run its suite (needs `bash`, `jq` and `sha256sum`; slow under Git Bash on Windows):

```bash
bash archive/bash-v0.3/tests/simple-test.sh
bash archive/bash-v0.3/tests/oracle-gate.sh
```
````

- [ ] **Step 6: Prove the archived suite still passes from its new home**

Both commands are slow under Git Bash on Windows; allow fifteen minutes for the pair, and run
them in the background if your tool has a time limit. The gate runs the suite a second time.

```bash
bash archive/bash-v0.3/tests/simple-test.sh | tail -3
bash archive/bash-v0.3/tests/oracle-gate.sh | tail -1
```

Expected: `Results: 202 passed, 0 failed, 0 skipped, 202 total` (on a machine without the
`claude` CLI: `200 passed, 0 failed, 2 skipped`), then
`oracle-gate: OK — 202/202 locked tests ran, suite exit 0` (or `200/202`). This was rehearsed
on a copy of the tree while this plan was written, with that result. A failure here means the
move broke a path: stop and report the failing test names.

- [ ] **Step 7: Commit**

```bash
git add -A archive .gitattributes
git commit -m "chore(archive): move the Bash implementation to archive/bash-v0.3"
```

### Task 2: The cargo workspace, the skeleton crates and the runner's shell

**Files:**
- Create: `Cargo.toml`, `Cargo.lock`, `rust-toolchain.toml`, `.cargo/config.toml`
- Modify: `.gitignore`
- Create: `crates/<crate>/Cargo.toml`, `crates/<crate>/src/lib.rs`, `crates/<crate>/src/testkit.rs`
  for `engine`, `workspace`, `runtime`, `oracle`, `map`, `controls`, `payload`, `ledger`,
  `speaker`; and `crates/workspace/src/fake.rs`, `crates/runtime/src/fake.rs`
- Create: `crates/cli/Cargo.toml`, `crates/cli/src/lib.rs`, `crates/cli/src/main.rs`, `crates/cli/src/testkit.rs`
- Create: `xtask/Cargo.toml`, `xtask/src/main.rs`, `xtask/src/lib.rs`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - a workspace in which `cargo build`, `cargo test --workspace` and `cargo xtask` run;
  - every library crate with a `testkit` feature and a `testkit` module compiled under
    `cfg(any(test, feature = "testkit"))`;
  - `cli::main_from<I, S>(args: I) -> std::process::ExitCode where I: IntoIterator<Item = S>, S: Into<std::ffi::OsString> + Clone`;
  - in `xtask`: `pub const TIERS: [&str; 6]`, `pub const USAGE: &str`,
    `pub fn tier_of_test_target(name: &str) -> &'static str` (the tier naming rule),
    `pub fn repo_root() -> PathBuf`,
    `pub fn cargo() -> Command`, `pub fn run(cmd: Command) -> Result<(), String>`,
    `pub fn relative(root: &Path, path: &Path) -> String`, `pub fn files_under(dir: &Path) -> Vec<PathBuf>`,
    `pub fn verdict(gate: &str, ok: String, problems: Vec<String>) -> Result<(), String>`,
    `pub fn main_from(args: Vec<String>) -> ExitCode`.

- [ ] **Step 1: Write the workspace manifest and the tool configuration**

Create `Cargo.toml`:

```toml
[workspace]
resolver = "2"
members = [
    "crates/engine",
    "crates/workspace",
    "crates/runtime",
    "crates/oracle",
    "crates/map",
    "crates/controls",
    "crates/payload",
    "crates/ledger",
    "crates/speaker",
    "crates/cli",
    "xtask",
]

[workspace.package]
edition = "2021"
version = "0.4.0"
license = "MIT"
repository = "https://github.com/adbarc92/reqdrive"
rust-version = "1.93"
publish = false

[workspace.dependencies]
# Internal crates. Which of them may depend on which is a table in xtask/src/deps.rs;
# `cargo xtask deps` fails on any edge that table does not list.
engine = { path = "crates/engine" }
workspace = { path = "crates/workspace" }
runtime = { path = "crates/runtime" }
oracle = { path = "crates/oracle" }
map = { path = "crates/map" }
controls = { path = "crates/controls" }
payload = { path = "crates/payload" }
ledger = { path = "crates/ledger" }
speaker = { path = "crates/speaker" }

# External crates. A lane that needs one that is not here asks the coordinating lane.
clap = { version = "4", features = ["derive"] }
serde = { version = "1", features = ["derive"] }
serde_json = "1"
sha2 = "0.10"

[workspace.lints.rust]
unsafe_code = "forbid"
```

Create `rust-toolchain.toml`:

```toml
[toolchain]
channel = "1.93.1"
components = ["rustfmt", "clippy"]
profile = "minimal"
```

Create `.cargo/config.toml`. The alias passes `--locked`: after a deliberate dependency change,
run a plain `cargo build` once to update `Cargo.lock`, and `cargo xtask` works again.

```toml
[alias]
xtask = "run --quiet --locked --package xtask --"
```

Replace `.gitignore` with:

```
# Build output
/target/

# The conformance kit, installed by `cargo xtask test contract`
/.kit/

# reqdrive run state in a target repository (the archived Bash CLI wrote these here too)
.reqdrive/runs/
.reqdrive/agent/
```

- [ ] **Step 2: Generate the nine library skeletons**

Each library crate starts as three files with nothing in them but a description and an empty
`testkit` module. Write this script to `gen-skeleton.sh` at the worktree root:

```bash
#!/usr/bin/env bash
# Writes the empty skeleton of every library crate. Run once from the repository root.
set -euo pipefail

crate() {
  local name="$1" description="$2" deps="$3" modules="$4"
  mkdir -p "crates/$name/src"
  cat > "crates/$name/Cargo.toml" <<EOF
[package]
name = "$name"
description = "$description"
edition.workspace = true
version.workspace = true
license.workspace = true
repository.workspace = true
rust-version.workspace = true
publish.workspace = true

[features]
# Builders for this crate's own types, for its tests and for other crates' tests.
testkit = []

[dependencies]
$deps
[lints]
workspace = true
EOF
  cat > "crates/$name/src/lib.rs" <<EOF
//! \`$name\`: $description
//!
//! Empty until its lane builds it. The interface this crate must offer is its Form,
//! \`forms/$name.md\`, once that Form exists.

$modules#[cfg(any(test, feature = "testkit"))]
pub mod testkit;
EOF
  cat > "crates/$name/src/testkit.rs" <<EOF
//! Builders for \`$name\`'s own types. Compiled for this crate's tests, and for other crates
//! that enable the \`testkit\` feature.
EOF
}

crate engine    "The unit's stage machine: decides the next action from stage outcomes. No I/O." "" ""
crate workspace "Agent and check containers behind one seam, with a fake for tests." "" "pub mod fake;
"
crate runtime   "The worker-runtime contract and its adapters, with a scripted fake." "serde.workspace = true
serde_json.workspace = true
" "pub mod fake;
"
crate oracle    "Freezing and hashing tests, the holdout bundle, and reading test reports." "" ""
crate map       "The deterministic repository map and its independent gauge." "" ""
crate controls  "The host-driven controls on a unit's diff." "" ""
crate payload   "What each role may see, and the prompt templates." "" ""
crate ledger    "The append-only event log per unit, evidence assembly and resume." "" ""
crate speaker   "The harness protocol over stdin and stdout." "serde.workspace = true
serde_json.workspace = true
" ""

cat > crates/workspace/src/fake.rs <<'EOF'
//! A workspace that exists only in memory. Empty until the walking skeleton fills it.
EOF
cat > crates/runtime/src/fake.rs <<'EOF'
//! A scripted worker runtime. Empty until the walking skeleton fills it.
EOF
```

Run it, look at one result, and remove the script:

```bash
bash gen-skeleton.sh
cat crates/runtime/Cargo.toml crates/runtime/src/lib.rs
rm gen-skeleton.sh
ls crates
```

Expected: `crates/runtime/Cargo.toml` names the package `runtime`, declares `testkit = []` and
depends on `serde` and `serde_json`; `crates/runtime/src/lib.rs` declares `pub mod fake;` and
the `testkit` module; `ls crates` lists the nine crates.

- [ ] **Step 3: Write the `cli` and `xtask` manifests and entry points**

Create `crates/cli/Cargo.toml`:

```toml
[package]
name = "cli"
description = "The reqdrive binary. Wiring only: the one place implementations are chosen."
edition.workspace = true
version.workspace = true
license.workspace = true
repository.workspace = true
rust-version.workspace = true
publish.workspace = true

[[bin]]
name = "reqdrive"
path = "src/main.rs"

[features]
# Builders for this crate's own types, for its tests and for other crates' tests.
testkit = []

[dependencies]
clap.workspace = true
engine.workspace = true
runtime.workspace = true
serde_json.workspace = true
speaker.workspace = true
workspace.workspace = true

[dev-dependencies]
speaker = { workspace = true, features = ["testkit"] }

[lints]
workspace = true
```

Create `crates/cli/src/main.rs`:

```rust
fn main() -> std::process::ExitCode {
    cli::main_from(std::env::args_os())
}
```

Create `crates/cli/src/testkit.rs`:

```rust
//! Builders for `cli`'s own types. Compiled for this crate's tests, and for other crates
//! that enable the `testkit` feature.
```

Create `xtask/Cargo.toml`:

```toml
[package]
name = "xtask"
description = "This repository's test runner and structural gates: cargo xtask <command>."
edition.workspace = true
version.workspace = true
license.workspace = true
repository.workspace = true
rust-version.workspace = true
publish.workspace = true

[dependencies]
serde_json.workspace = true
sha2.workspace = true

[lints]
workspace = true
```

Create `xtask/src/main.rs`:

```rust
fn main() -> std::process::ExitCode {
    xtask::main_from(std::env::args().skip(1).collect())
}
```

- [ ] **Step 4: Write the failing tests**

Create `crates/cli/src/lib.rs` with only its tests:

```rust
#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_scaffold_binary_refuses_every_command() {
        assert_eq!(main_from(["reqdrive", "harness"]), ExitCode::from(2));
    }
}
```

Create `xtask/src/lib.rs` with only its tests:

```rust
#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn an_unknown_command_is_a_usage_error() {
        assert_eq!(main_from(vec!["frobnicate".into()]), ExitCode::from(2));
        assert_eq!(main_from(vec![]), ExitCode::from(2));
    }

    #[test]
    fn relative_paths_use_forward_slashes() {
        let root = Path::new("repo");
        let path = root
            .join("crates")
            .join("engine")
            .join("src")
            .join("lib.rs");
        assert_eq!(relative(root, &path), "crates/engine/src/lib.rs");
    }

    #[test]
    fn a_gate_with_problems_fails_and_lists_each_one() {
        assert!(verdict("deps", "3 crates".into(), vec![]).is_ok());
        let failed = verdict("deps", String::new(), vec!["a".into(), "b".into()]).unwrap_err();
        assert!(
            failed.contains("2 problem(s)") && failed.contains("- a") && failed.contains("- b")
        );
    }

    #[test]
    fn a_test_target_is_sorted_into_a_tier_by_its_file_name_alone() {
        assert_eq!(tier_of_test_target("e2e_one_unit"), "e2e");
        assert_eq!(tier_of_test_target("live_models"), "live");
        assert_eq!(tier_of_test_target("docker_it"), "integration");
        assert_eq!(tier_of_test_target("integration_docker_it"), "integration");
        assert_eq!(tier_of_test_target("characterisation_store"), "unit");
        assert_eq!(tier_of_test_target("contract_speaker"), "contract");
        assert_eq!(tier_of_test_target("vectors"), "contract");
        // A prefix alone does not make an integration test: the suffix does.
        assert_eq!(tier_of_test_target("integration_docker"), "contract");
        // The first row that matches wins.
        assert_eq!(tier_of_test_target("e2e_full_it"), "e2e");
        assert_eq!(
            tier_of_test_target("characterisation_store_it"),
            "integration"
        );
        for name in ["", "it", "_it", "x"] {
            assert!(
                TIERS.contains(&tier_of_test_target(name)),
                "{name:?} has a tier"
            );
        }
    }
}
```

- [ ] **Step 5: Run them and watch them fail**

Run: `cargo test -p cli -p xtask`

Expected: it does not compile. The errors name what is missing: `main_from`, `relative`,
`verdict`, `tier_of_test_target`.

- [ ] **Step 6: Write the implementations**

In `crates/cli/src/lib.rs`, put this above the test module:

```rust
//! `cli`: the `reqdrive` binary's library half. Wiring only: it parses the command line and is
//! the one place where real or fake implementations of the other crates are chosen.
//!
//! No command is built yet.

use std::process::ExitCode;

#[cfg(any(test, feature = "testkit"))]
pub mod testkit;

/// The binary's whole behaviour, given its arguments (the program name first).
pub fn main_from<I, S>(args: I) -> ExitCode
where
    I: IntoIterator<Item = S>,
    S: Into<std::ffi::OsString> + Clone,
{
    let _ = args;
    eprintln!(
        "reqdrive {}: no command is built yet (milestone 0 scaffold)",
        env!("CARGO_PKG_VERSION")
    );
    ExitCode::from(2)
}
```

In `xtask/src/lib.rs`, put this above the test module. It is the runner's shell: helpers every
later module uses, and a `main_from` that knows no command yet.

````rust
//! `cargo xtask`: this repository's test runner and its structural gates.
//!
//! ```text
//! cargo xtask test <static|unit|contract|integration|e2e|live> [crate]
//! cargo xtask deps           dependency direction
//! cargo xtask parity         the gate registry agrees with the Forms and with CI
//! cargo xtask lock check     locked contract tests are unchanged
//! cargo xtask lock accept    re-lock them (a deliberate act; its diff is reviewed)
//! ```

/// The six test tiers, cheapest first.
pub const TIERS: [&str; 6] = ["static", "unit", "contract", "integration", "e2e", "live"];

use std::path::{Path, PathBuf};
use std::process::{Command, ExitCode};

pub const USAGE: &str = "usage:
  cargo xtask test <static|unit|contract|integration|e2e|live> [crate]
  cargo xtask deps
  cargo xtask parity
  cargo xtask lock <check|accept>";

/// The tier of a test target under `crates/<crate>/tests/`, decided by its file name and by
/// nothing else. `name` is the file name without `.rs`. This is the program's naming rule,
/// the same in the control plane's repository. It is total: every name has a tier, so no
/// test target can be left out of every tier.
///
/// | File name | Tier |
/// |---|---|
/// | `e2e_*.rs` | `e2e` |
/// | `live_*.rs` | `live` |
/// | `*_it.rs` | `integration` |
/// | `characterisation_*.rs` | `unit`: it runs with the crate's own tests |
/// | any other name | `contract` |
///
/// The first row that matches wins.
pub fn tier_of_test_target(name: &str) -> &'static str {
    if name.starts_with("e2e_") {
        "e2e"
    } else if name.starts_with("live_") {
        "live"
    } else if name.ends_with("_it") {
        "integration"
    } else if name.starts_with("characterisation_") {
        "unit"
    } else {
        "contract"
    }
}

/// The repository root: the directory above this crate.
pub fn repo_root() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR"))
        .parent()
        .expect("xtask sits one level below the repository root")
        .to_path_buf()
}

/// A `cargo` command that runs from the repository root.
pub fn cargo() -> Command {
    let mut cmd = Command::new(std::env::var_os("CARGO").unwrap_or_else(|| "cargo".into()));
    cmd.current_dir(repo_root());
    cmd
}

/// Echo a command, run it, and turn a failure into a one-line reason.
pub fn run(mut cmd: Command) -> Result<(), String> {
    let shown = format!("{cmd:?}");
    println!("xtask: running {shown}");
    let status = cmd
        .status()
        .map_err(|e| format!("could not start {shown}: {e}"))?;
    if status.success() {
        Ok(())
    } else {
        Err(format!("{shown} ended with {status}"))
    }
}

/// A repository-relative path with forward slashes, whatever the platform.
pub fn relative(root: &Path, path: &Path) -> String {
    path.strip_prefix(root)
        .unwrap_or(path)
        .to_string_lossy()
        .replace('\\', "/")
}

/// Every file under `dir`, recursively. A missing directory is an empty list.
pub fn files_under(dir: &Path) -> Vec<PathBuf> {
    let mut found = Vec::new();
    let mut pending = vec![dir.to_path_buf()];
    while let Some(next) = pending.pop() {
        let Ok(entries) = std::fs::read_dir(&next) else {
            continue;
        };
        for entry in entries.flatten() {
            let path = entry.path();
            if path.is_dir() {
                pending.push(path);
            } else {
                found.push(path);
            }
        }
    }
    found.sort();
    found
}

/// Join a gate's problems into one failure, or pass with a one-line summary.
pub fn verdict(gate: &str, ok: String, problems: Vec<String>) -> Result<(), String> {
    if problems.is_empty() {
        println!("{gate}: OK ({ok})");
        return Ok(());
    }
    let mut message = format!("{gate}: {} problem(s)", problems.len());
    for problem in &problems {
        message.push_str("\n  - ");
        message.push_str(problem);
    }
    Err(message)
}

pub fn main_from(args: Vec<String>) -> ExitCode {
    let _ = args;
    eprintln!("{USAGE}");
    ExitCode::from(2)
}
````

- [ ] **Step 7: Run everything**

```bash
cargo test --workspace 2>&1 | grep -E "^test result|^error"
cargo fmt --all -- --check && echo "fmt ok"
cargo clippy --workspace --all-targets --all-features -- -D warnings && echo "clippy ok"
cargo xtask; echo "exit $?"
```

Expected: among the `test result` lines, one `1 passed` (`cli`) and one `4 passed` (`xtask`),
no `FAILED`; `fmt ok`; `clippy ok`; the usage text and `exit 2`. The first `cargo` command
writes `Cargo.lock`.

- [ ] **Step 8: Commit**

```bash
git add Cargo.toml Cargo.lock rust-toolchain.toml .cargo .gitignore crates xtask
git commit -m "feat(workspace): cargo workspace, empty crate skeletons and the xtask shell"
```

### Task 3: `xtask` reads the dependency graph

**Files:**
- Create: `xtask/src/metadata.rs`
- Modify: `xtask/src/lib.rs` (one line)

**Interfaces:**
- Consumes: `xtask::cargo`.
- Produces, in `xtask::metadata`:
  - `pub enum Kind { Normal, Dev, Build }`
  - `pub struct Dep { pub name: String, pub kinds: Vec<Kind> }`
  - `pub struct Package { pub name: String, pub source: Option<String>, pub features: Vec<String>, pub dir: String, pub deps: Vec<Dep> }`
  - `pub struct Graph { pub packages: Vec<Package>, pub members: Vec<String>, pub target_dir: String }`
  - `Graph::parse(json: &str) -> Result<Graph, String>`, `Graph::load() -> Result<Graph, String>`,
    `Graph::package(&self, name: &str) -> Option<&Package>`, `Graph::is_member(&self, name: &str) -> bool`,
    `Graph::closure(&self, name: &str) -> BTreeSet<String>`
  - for tests in this crate: `metadata::tests::graph(members: &[&str], packages: &[Spec]) -> Graph`

- [ ] **Step 1: Write the failing tests**

In `xtask/src/lib.rs`, directly below the `//!` header, add the line `pub mod metadata;`
followed by a blank line. Create `xtask/src/metadata.rs` with only its tests:

```rust
#[cfg(test)]
pub(crate) mod tests {
    use super::*;

    /// One hand-written package: `(name, source, features, [(dependency, kind)])`.
    pub(crate) type Spec<'a> = (
        &'a str,
        Option<&'a str>,
        &'a [&'a str],
        &'a [(&'a str, Kind)],
    );

    /// A graph built by hand.
    pub(crate) fn graph(members: &[&str], packages: &[Spec]) -> Graph {
        Graph {
            packages: packages
                .iter()
                .map(|(name, source, features, deps)| Package {
                    name: name.to_string(),
                    source: source.map(str::to_string),
                    features: features.iter().map(|f| f.to_string()).collect(),
                    dir: if members.contains(name) && *name != "xtask" {
                        format!("/repo/crates/{name}")
                    } else {
                        format!("/elsewhere/{name}")
                    },
                    deps: deps
                        .iter()
                        .map(|(dep, kind)| Dep {
                            name: dep.to_string(),
                            kinds: vec![*kind],
                        })
                        .collect(),
                })
                .collect(),
            members: members.iter().map(|m| m.to_string()).collect(),
            target_dir: "/repo/target".into(),
        }
    }

    const SAMPLE: &str = r#"{
      "packages": [
        {"id": "path+file:///r/crates/cli#0.4.0", "name": "cli", "source": null,
         "manifest_path": "C:\\r\\crates\\cli\\Cargo.toml", "features": {"testkit": []}},
        {"id": "registry+https://x#serde@1.0.0", "name": "serde",
         "source": "registry+https://github.com/rust-lang/crates.io-index",
         "manifest_path": "/home/u/.cargo/registry/serde/Cargo.toml", "features": {}}
      ],
      "workspace_members": ["path+file:///r/crates/cli#0.4.0"],
      "resolve": {"nodes": [
        {"id": "path+file:///r/crates/cli#0.4.0", "deps": [
          {"name": "serde", "pkg": "registry+https://x#serde@1.0.0",
           "dep_kinds": [{"kind": null, "target": null}, {"kind": "dev", "target": null}]}
        ]},
        {"id": "registry+https://x#serde@1.0.0", "deps": []}
      ]},
      "target_directory": "/r/target"
    }"#;

    #[test]
    fn parses_packages_members_edges_and_kinds() {
        let graph = Graph::parse(SAMPLE).unwrap();
        assert_eq!(graph.members, vec!["cli"]);
        let cli = graph.package("cli").unwrap();
        assert_eq!(cli.dir, "C:/r/crates/cli");
        assert_eq!(cli.features, vec!["testkit"]);
        assert_eq!(cli.source, None);
        assert_eq!(cli.deps[0].name, "serde");
        assert_eq!(cli.deps[0].kinds, vec![Kind::Normal, Kind::Dev]);
        assert_eq!(graph.target_dir, "/r/target");
    }

    #[test]
    fn empty_output_is_an_error_not_an_empty_graph() {
        assert!(Graph::parse("  \n")
            .unwrap_err()
            .contains("printed nothing"));
    }

    #[test]
    fn the_closure_follows_normal_and_build_edges_only() {
        let g = graph(
            &["a"],
            &[
                ("a", None, &[], &[("b", Kind::Normal), ("t", Kind::Dev)]),
                ("b", None, &[], &[("c", Kind::Build)]),
                ("c", None, &[], &[]),
                ("t", None, &[], &[("u", Kind::Normal)]),
                ("u", None, &[], &[]),
            ],
        );
        let closure: Vec<String> = g.closure("a").into_iter().collect();
        assert_eq!(closure, vec!["b", "c"]);
    }
}
```

- [ ] **Step 2: Run them and watch them fail**

Run: `cargo test -p xtask --lib metadata::`

Expected: it does not compile; the errors name the missing types `Graph`, `Package`, `Dep`
and `Kind`.

- [ ] **Step 3: Write the implementation**

Put this above the test module in `xtask/src/metadata.rs`:

```rust
//! The workspace's dependency graph, read from `cargo metadata`.

use serde_json::Value;
use std::collections::{BTreeMap, BTreeSet};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Kind {
    Normal,
    Dev,
    Build,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Dep {
    /// The package name of the dependency.
    pub name: String,
    pub kinds: Vec<Kind>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Package {
    pub name: String,
    /// `None` for a path package. For a git package pinned to a tag, `git+<url>?tag=<tag>`;
    /// some cargo versions append `#<commit>`.
    pub source: Option<String>,
    pub features: Vec<String>,
    /// The directory holding the package's manifest, with forward slashes.
    pub dir: String,
    pub deps: Vec<Dep>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Graph {
    pub packages: Vec<Package>,
    /// Names of the workspace's own packages.
    pub members: Vec<String>,
    pub target_dir: String,
}

fn text(value: &Value, key: &str) -> Result<String, String> {
    value[key]
        .as_str()
        .map(str::to_string)
        .ok_or_else(|| format!("cargo metadata: `{key}` is missing or not a string"))
}

fn list<'a>(value: &'a Value, key: &str) -> Result<&'a Vec<Value>, String> {
    value[key]
        .as_array()
        .ok_or_else(|| format!("cargo metadata: `{key}` is missing or not a list"))
}

impl Graph {
    pub fn parse(json: &str) -> Result<Graph, String> {
        if json.trim().is_empty() {
            return Err("cargo metadata printed nothing".into());
        }
        let root: Value =
            serde_json::from_str(json).map_err(|e| format!("cargo metadata: not JSON: {e}"))?;

        let mut names = BTreeMap::new();
        let mut packages = BTreeMap::new();
        for package in list(&root, "packages")? {
            let id = text(package, "id")?;
            let name = text(package, "name")?;
            let manifest = text(package, "manifest_path")?.replace('\\', "/");
            let dir = manifest
                .rsplit_once('/')
                .map(|(dir, _)| dir.to_string())
                .unwrap_or_default();
            let features = package["features"]
                .as_object()
                .map(|map| map.keys().cloned().collect())
                .unwrap_or_default();
            names.insert(id.clone(), name.clone());
            packages.insert(
                id,
                Package {
                    name,
                    source: package["source"].as_str().map(str::to_string),
                    features,
                    dir,
                    deps: Vec::new(),
                },
            );
        }

        for node in list(&root["resolve"], "nodes")? {
            let id = text(node, "id")?;
            let mut deps = Vec::new();
            for dep in list(node, "deps")? {
                let target = text(dep, "pkg")?;
                let name = names
                    .get(&target)
                    .cloned()
                    .ok_or_else(|| format!("cargo metadata: unknown package id {target}"))?;
                let kinds = list(dep, "dep_kinds")?
                    .iter()
                    .map(|kind| match kind["kind"].as_str() {
                        Some("dev") => Kind::Dev,
                        Some("build") => Kind::Build,
                        _ => Kind::Normal,
                    })
                    .collect();
                deps.push(Dep { name, kinds });
            }
            if let Some(package) = packages.get_mut(&id) {
                package.deps = deps;
            }
        }

        let mut members = Vec::new();
        for id in list(&root, "workspace_members")? {
            let id = id.as_str().unwrap_or_default();
            let name = names
                .get(id)
                .cloned()
                .ok_or_else(|| format!("cargo metadata: unknown workspace member {id}"))?;
            members.push(name);
        }
        members.sort();

        Ok(Graph {
            packages: packages.into_values().collect(),
            members,
            target_dir: text(&root, "target_directory")?,
        })
    }

    /// Run `cargo metadata` for this workspace. `--locked`: a stale lockfile is an error here,
    /// never something this runner quietly rewrites.
    pub fn load() -> Result<Graph, String> {
        let output = crate::cargo()
            .args(["metadata", "--format-version", "1", "--locked"])
            .output()
            .map_err(|e| format!("could not start cargo metadata: {e}"))?;
        if !output.status.success() {
            return Err(format!(
                "cargo metadata failed: {}",
                String::from_utf8_lossy(&output.stderr).trim()
            ));
        }
        Graph::parse(&String::from_utf8_lossy(&output.stdout))
    }

    pub fn package(&self, name: &str) -> Option<&Package> {
        self.packages.iter().find(|p| p.name == name)
    }

    pub fn is_member(&self, name: &str) -> bool {
        self.members.iter().any(|m| m == name)
    }

    /// Every package `name` reaches through normal and build dependencies, itself excluded.
    pub fn closure(&self, name: &str) -> BTreeSet<String> {
        let mut seen = BTreeSet::new();
        let mut pending = vec![name.to_string()];
        while let Some(next) = pending.pop() {
            let Some(package) = self.package(&next) else {
                continue;
            };
            for dep in &package.deps {
                if dep.kinds.iter().any(|k| *k != Kind::Dev) && seen.insert(dep.name.clone()) {
                    pending.push(dep.name.clone());
                }
            }
        }
        seen
    }
}
```

- [ ] **Step 4: Run the tests**

Run: `cargo test -p xtask --lib metadata::`

Expected: `test result: ok. 3 passed`.

- [ ] **Step 5: Commit**

```bash
git add xtask/src/metadata.rs xtask/src/lib.rs
git commit -m "feat(xtask): read the workspace's dependency graph from cargo metadata"
```

### Task 4: `cargo xtask deps`, the dependency-direction gate

**Files:**
- Create: `xtask/src/deps.rs`
- Modify: `xtask/src/lib.rs` (one line)

**Interfaces:**
- Consumes: `metadata::{Graph, Kind}`, `xtask::{files_under, relative, repo_root, verdict}`.
- Produces, in `xtask::deps`:
  - `pub const ALLOWED_INTERNAL: &[(&str, &[&str])]`, `ENGINE_EXTERNAL`, `DOCKER_CRATES`,
    `ENGINE_FORBIDDEN`, `CONTRACT_CRATES`, `MAY_SPAWN: &[&str]`, `pub const CONTRACT_SOURCE_PREFIX: &str`
  - `pub fn check_graph(graph: &Graph) -> Vec<String>`
  - `pub fn check_sources(files: &[(String, String)]) -> Vec<String>`
  - `pub fn run() -> Result<(), String>`

- [ ] **Step 1: Write the failing tests**

In `xtask/src/lib.rs`, add `pub mod deps;` to the module list, above `pub mod metadata;`
(the list stays alphabetical). Create `xtask/src/deps.rs` with only its tests:

```rust
#[cfg(test)]
mod tests {
    use super::*;
    use crate::metadata::tests::graph;

    const TAGGED: &str =
        "git+https://github.com/adbarc92/command-center?tag=contracts-v0.2.0#0123abc";

    #[test]
    fn the_planned_edges_pass() {
        let g = graph(
            &["engine", "speaker", "cli"],
            &[
                ("engine", None, &[], &[]),
                ("speaker", None, &[], &[("harness-protocol", Kind::Normal)]),
                (
                    "cli",
                    None,
                    &[],
                    &[("engine", Kind::Normal), ("speaker", Kind::Normal)],
                ),
                ("harness-protocol", Some(TAGGED), &[], &[]),
            ],
        );
        assert_eq!(check_graph(&g), Vec::<String>::new());
    }

    #[test]
    fn an_unlisted_internal_edge_fails_but_a_dev_edge_does_not() {
        let g = graph(
            &["engine", "speaker"],
            &[
                ("engine", None, &[], &[("speaker", Kind::Normal)]),
                ("speaker", None, &[], &[("engine", Kind::Dev)]),
            ],
        );
        assert_eq!(check_graph(&g), vec!["engine may not depend on speaker"]);
    }

    #[test]
    fn a_crate_without_a_row_fails() {
        let g = graph(&["novel"], &[("novel", None, &[], &[])]);
        assert!(check_graph(&g)[0].starts_with("novel: no row in ALLOWED_INTERNAL"));
    }

    #[test]
    fn engine_may_not_name_or_reach_an_io_crate() {
        let g = graph(
            &["engine"],
            &[
                (
                    "engine",
                    None,
                    &[],
                    &[("serde", Kind::Normal), ("anyhow", Kind::Normal)],
                ),
                ("serde", None, &[], &[]),
                ("anyhow", None, &[], &[("tokio", Kind::Normal)]),
                ("tokio", None, &[], &[]),
            ],
        );
        let problems = check_graph(&g);
        assert!(problems
            .iter()
            .any(|p| p.starts_with("engine names anyhow")));
        assert!(problems.contains(&"engine reaches tokio: engine does no I/O".to_string()));
        assert_eq!(problems.len(), 2);
    }

    #[test]
    fn only_workspace_names_a_docker_crate() {
        let g = graph(
            &["workspace", "controls"],
            &[
                ("workspace", None, &[], &[("bollard", Kind::Normal)]),
                ("controls", None, &[], &[("bollard", Kind::Dev)]),
                ("bollard", None, &[], &[]),
            ],
        );
        assert_eq!(
            check_graph(&g),
            vec!["controls names bollard: only `workspace` may talk to Docker"]
        );
    }

    #[test]
    fn contract_crates_come_from_one_contracts_tag() {
        let other = "git+https://github.com/adbarc92/command-center?tag=contracts-v0.3.0#9";
        let g = graph(
            &[],
            &[
                ("harness-protocol", Some(TAGGED), &[], &[]),
                ("factory-spec", Some(other), &[], &[]),
                ("factory-presets", None, &[], &[]),
            ],
        );
        let problems = check_graph(&g);
        assert!(problems
            .iter()
            .any(|p| p.starts_with("factory-presets comes from a local path")));
        assert!(problems.contains(&"the contract crates are pinned to different tags".to_string()));
        assert_eq!(problems.len(), 2);
    }

    #[test]
    fn a_crate_is_named_after_its_directory() {
        let mut g = graph(&["engine"], &[("engine", None, &[], &[])]);
        g.packages[0].dir = "/repo/crates/stage-engine".into();
        assert!(check_graph(&g)[0].contains("named after its directory"));
    }

    #[test]
    fn a_process_may_start_only_at_the_seams() {
        let files = vec![
            (
                "crates/workspace/src/docker.rs".to_string(),
                "std::process::Command::new(\"docker\")".to_string(),
            ),
            (
                "crates/runtime/src/adapters/claude_code.rs".to_string(),
                "Command::new(\"claude\")".to_string(),
            ),
            (
                "crates/cli/tests/contract_harness_process.rs".to_string(),
                "Command::new(env!(\"CARGO_BIN_EXE_reqdrive\"))".to_string(),
            ),
            (
                "crates/controls/src/lib.rs".to_string(),
                "use std::process::Command;".to_string(),
            ),
        ];
        let problems = check_sources(&files);
        assert_eq!(problems.len(), 1);
        assert!(problems[0].starts_with("crates/controls/src/lib.rs uses `process::Command`"));
    }
}
```

- [ ] **Step 2: Run them and watch them fail**

Run: `cargo test -p xtask --lib deps::`

Expected: it does not compile; the errors name `check_graph` and `check_sources`.

- [ ] **Step 3: Write the implementation**

Put this above the test module in `xtask/src/deps.rs`:

```rust
//! Dependency direction, checked from `cargo metadata` and a scan of the sources.
//!
//! The rules, in the order they are checked:
//!
//! 1. Every workspace crate has a row in [`ALLOWED_INTERNAL`], and depends on another workspace
//!    crate only where that row says it may. Dev-dependencies are exempt.
//! 2. A crate under `crates/` is named after its directory.
//! 3. `engine` names no external crate outside [`ENGINE_EXTERNAL`], and reaches none of
//!    [`ENGINE_FORBIDDEN`] even transitively.
//! 4. Only `workspace` names a crate that talks to Docker ([`DOCKER_CRATES`]).
//! 5. The contract crates come from one tag of the control plane's repository.
//! 6. Source may start a process only under the paths in [`MAY_SPAWN`].

use crate::metadata::{Graph, Kind};
use std::path::Path;

/// Which workspace crate may depend on which, as normal or build dependencies.
/// A new edge is added here by the coordinating lane, in a reviewed change.
pub const ALLOWED_INTERNAL: &[(&str, &[&str])] = &[
    ("engine", &[]),
    ("workspace", &[]),
    ("runtime", &[]),
    ("oracle", &[]),
    ("map", &[]),
    ("controls", &[]),
    ("payload", &[]),
    ("ledger", &[]),
    ("speaker", &[]),
    ("cli", &["engine", "workspace", "runtime", "speaker"]),
    ("xtask", &[]),
];

/// The only external crates `engine` may name: the contract crates, which do no I/O, and two
/// crates that only generate code.
pub const ENGINE_EXTERNAL: &[&str] = &[
    "harness-protocol",
    "factory-spec",
    "factory-presets",
    "serde",
    "thiserror",
];

/// Crates that talk to Docker.
pub const DOCKER_CRATES: &[&str] = &[
    "bollard",
    "shiplift",
    "docker-api",
    "dockworker",
    "testcontainers",
];

/// Crates `engine` must not reach at all: runtimes, network, processes, files, databases.
pub const ENGINE_FORBIDDEN: &[&str] = &[
    "tokio",
    "async-std",
    "smol",
    "mio",
    "reqwest",
    "hyper",
    "ureq",
    "curl",
    "git2",
    "gix",
    "rusqlite",
    "sqlx",
    "tempfile",
    "walkdir",
];

pub const CONTRACT_CRATES: &[&str] = &["harness-protocol", "factory-spec", "factory-presets"];

/// What `cargo metadata` reports as the source of a crate pinned to a contracts tag.
pub const CONTRACT_SOURCE_PREFIX: &str =
    "git+https://github.com/adbarc92/command-center?tag=contracts-v";

/// Where source may start a process: the container seam, the agent-CLI adapters, this runner.
pub const MAY_SPAWN: &[&str] = &[
    "crates/workspace/src/",
    "crates/runtime/src/adapters/",
    "xtask/src/",
];

const SPAWN_MARKERS: &[&str] = &["process::Command", "Command::new(", "tokio::process"];

fn allowed(member: &str) -> Option<&'static [&'static str]> {
    ALLOWED_INTERNAL
        .iter()
        .find(|(name, _)| *name == member)
        .map(|(_, deps)| *deps)
}

/// Rules 1 to 5. Pure: the graph is the only input.
pub fn check_graph(graph: &Graph) -> Vec<String> {
    let mut problems = Vec::new();

    for member in &graph.members {
        let Some(package) = graph.package(member) else {
            continue;
        };
        let Some(may) = allowed(member) else {
            problems.push(format!(
                "{member}: no row in ALLOWED_INTERNAL (xtask/src/deps.rs); add one"
            ));
            continue;
        };
        for dep in &package.deps {
            let ships = dep.kinds.iter().any(|k| *k != Kind::Dev);
            if ships && graph.is_member(&dep.name) && !may.contains(&dep.name.as_str()) {
                problems.push(format!("{member} may not depend on {}", dep.name));
            }
            if member != "workspace" && DOCKER_CRATES.contains(&dep.name.as_str()) {
                problems.push(format!(
                    "{member} names {}: only `workspace` may talk to Docker",
                    dep.name
                ));
            }
        }
        if let Some((_, dir)) = package.dir.rsplit_once("/crates/") {
            if dir != member {
                problems.push(format!(
                    "{member}: lives in crates/{dir}; a crate is named after its directory"
                ));
            }
        }
    }

    if let Some(engine) = graph.package("engine") {
        for dep in &engine.deps {
            let ships = dep.kinds.iter().any(|k| *k != Kind::Dev);
            if ships && !graph.is_member(&dep.name) && !ENGINE_EXTERNAL.contains(&dep.name.as_str())
            {
                problems.push(format!(
                    "engine names {}: it may name only {ENGINE_EXTERNAL:?}",
                    dep.name
                ));
            }
        }
        for reached in graph.closure("engine") {
            let name = reached.as_str();
            if ENGINE_FORBIDDEN.contains(&name) || DOCKER_CRATES.contains(&name) {
                problems.push(format!("engine reaches {name}: engine does no I/O"));
            }
        }
    }

    let contracts: Vec<_> = graph
        .packages
        .iter()
        .filter(|p| CONTRACT_CRATES.contains(&p.name.as_str()))
        .collect();
    for package in &contracts {
        let source = package.source.as_deref().unwrap_or("a local path");
        if !source.starts_with(CONTRACT_SOURCE_PREFIX) {
            problems.push(format!(
                "{} comes from {source}: contract crates are pinned to a contracts tag",
                package.name
            ));
        }
    }
    if let Some(first) = contracts.first() {
        if contracts.iter().any(|p| p.source != first.source) {
            problems.push("the contract crates are pinned to different tags".into());
        }
    }

    problems
}

/// Rule 6. Pure: `files` are `(repository-relative path, content)` pairs.
pub fn check_sources(files: &[(String, String)]) -> Vec<String> {
    let mut problems = Vec::new();
    for (path, content) in files {
        let in_tests = path.contains("/tests/");
        if in_tests || MAY_SPAWN.iter().any(|prefix| path.starts_with(prefix)) {
            continue;
        }
        if let Some(marker) = SPAWN_MARKERS.iter().find(|m| content.contains(**m)) {
            problems.push(format!(
                "{path} uses `{marker}`: a process may be started only under {MAY_SPAWN:?}"
            ));
        }
    }
    problems
}

fn rust_sources(root: &Path) -> Vec<(String, String)> {
    let mut files = Vec::new();
    for dir in ["crates", "xtask"] {
        for path in crate::files_under(&root.join(dir)) {
            if path.extension().is_some_and(|ext| ext == "rs") {
                if let Ok(content) = std::fs::read_to_string(&path) {
                    files.push((crate::relative(root, &path), content));
                }
            }
        }
    }
    files
}

pub fn run() -> Result<(), String> {
    let graph = Graph::load()?;
    let sources = rust_sources(&crate::repo_root());
    let mut problems = check_graph(&graph);
    problems.extend(check_sources(&sources));
    crate::verdict(
        "deps",
        format!(
            "{} crates, {} source files",
            graph.members.len(),
            sources.len()
        ),
        problems,
    )
}
```

- [ ] **Step 4: Run the tests**

Run: `cargo test -p xtask --lib deps::`

Expected: `test result: ok. 8 passed`.

- [ ] **Step 5: Commit**

```bash
git add xtask/src/deps.rs xtask/src/lib.rs
git commit -m "feat(xtask): dependency-direction gate over cargo metadata and the sources"
```

### Task 5: `cargo xtask parity`, and the Form and registry formats

**Files:**
- Create: `xtask/src/parity.rs`, `docs/forms.md`
- Modify: `xtask/src/lib.rs` (one line)

**Interfaces:**
- Consumes: `metadata::Graph`, `xtask::{files_under, repo_root, verdict, TIERS}`.
- Produces, in `xtask::parity`:
  - `pub const SECTIONS: [&str; 7]`, `STATUSES: [&str; 3]`, `LEVELS: [&str; 4]`, `STATES: [&str; 2]`, `REPO: &str`
  - `pub struct Row { pub gate, pub form, pub mechanism, pub location, pub command, pub tier, pub state: String }`
    with `Row::owner(&self) -> &str` and `Row::local_id(&self) -> &str`
  - `pub struct FormGate { pub id: String, pub guards: Vec<String> }`
  - `pub struct Form { pub name: String, pub status: String, pub interface_files: Vec<String>, pub invariants: Vec<String>, pub gates: Vec<FormGate>, pub unenforced: Vec<String> }`
  - `pub struct Facts<'a> { pub exists: &'a dyn Fn(&str) -> bool, pub ci_tiers: Vec<String>, pub ci_unit_crates: Vec<String>, pub members: Vec<String>, pub with_testkit: Vec<String> }`
  - `pub fn parse_registry(text: &str) -> Result<Vec<Row>, String>`
  - `pub fn parse_form(name: &str, text: &str) -> Result<Form, String>`
  - `pub fn ci_tiers(workflow: &str) -> Vec<String>`, `pub fn ci_unit_crates(workflow: &str) -> Vec<String>`
  - `pub fn check(rows: &[Row], forms: &[Form], facts: &Facts) -> Vec<String>`
  - `pub fn run() -> Result<(), String>`
  - the public document `docs/forms.md`, which is the format `parse_form` and `parse_registry` accept.

- [ ] **Step 1: Write the format down**

The parser and this page must agree, so the page comes first. Create `docs/forms.md`:

`````markdown
# Forms and the gate registry

A **Form** is the written contract of one crate: what it is for, its whole public interface, the
statements that must stay true of any implementation, what it deliberately hides, and the
mechanical checks that guard all of that. A crate with a Form can be rebuilt from the Form and
its tests alone.

The **gate registry** is one table listing every such check in the repository.

`cargo xtask parity` reads both and fails when they disagree with each other, with the files on
disk, or with what CI runs. This page is the format that command parses. `reqdrive` will read
the same two formats in the repositories it works on.

## Which crates have a Form

Only the load-bearing ones: a crate other crates build against. `cli` and `xtask` have none. A
Form is named after its crate: `forms/<crate>.md`.

## A Form file

`forms/speaker.md` is a complete, real example.

````markdown
# Form: <crate>

- status: draft
- owner: <a person>
- level: E0
- last-drill: never
- interface-files:
  - crates/<crate>/src/lib.rs

## Purpose

## Interface

## Invariants

I1. <one sentence a test can prove false>

## Hidden decisions

- <a decision callers must not depend on>

## Gates

| Gate | Guards | Mechanism | Location | Blocks |
|---|---|---|---|---|
| G1 | I1 | <what checks it> | <path> | merge |

## Unenforced

None.

## Regeneration notes
````

### The header

The first line is `# Form: <crate>`, and the crate must exist in the workspace. Then five
entries, each on its own line:

| Entry | Value |
|---|---|
| `- status:` | `draft` (written, not yet approved), `frozen` (approved by the owner; its interface may change only as below) or `deprecated` |
| `- owner:` | A person. A Form is never owned by an agent |
| `- level:` | `E0` to `E3`: how far this crate has been shown to be regenerable. `E0` until a drill says otherwise |
| `- last-drill:` | The date of the last regeneration drill, or `never` |
| `- interface-files:` | A list, one `  - path` per line, of the files that hold the public interface. These are the files a change may not touch without the owner's decision |

### The seven sections

Exactly these headings, in this order. No other line in the file may begin with `## `.

1. **Purpose.** One paragraph: what the crate is for and what would break without it.
2. **Interface.** The complete public surface: signatures, types, events, and how it reports
   errors. Anything not written here is implementation and may be rewritten freely.
3. **Invariants.** Numbered `I1.`, `I2.`, … one per line, each a sentence a test could prove
   false. "The crate is well designed" is not an invariant. "No public function does I/O" is.
4. **Hidden decisions.** What the interface conceals on purpose, so that nobody helpfully
   exposes it later. A crate with nothing to hide probably does not need a Form.
5. **Gates.** A table, one row per check:

   | Column | Holds |
   |---|---|
   | Gate | `G1`, `G2`, … |
   | Guards | The invariants it guards, comma-separated: `I1, I3` |
   | Mechanism | What kind of check it is, in the order of preference below |
   | Location | The file that is the check |
   | Blocks | What it stops: `build`, `commit` or `merge`. Never empty: a gate that blocks nothing is prose |

6. **Unenforced.** Either the single line `None.`, or one line per invariant no gate guards:
   `- I4: <why> (<date>)`. Each is a debt, and the list should be empty.
7. **Regeneration notes.** What someone needs to rebuild the implementation from nothing: where
   the tests start, what the fixtures are, what the environment must provide, which
   dependencies are forbidden.

Every invariant must appear in some gate's Guards, or under Unenforced.

### Mechanisms, most preferred first

1. The type system: the wrong program does not compile.
2. The build graph: `cargo xtask deps` refuses the dependency.
3. Locked tests: a contract test file whose hash is frozen (below).
4. A conformance suite run from outside the crate.
5. A script in CI.

## The registry

`forms/registry.md` holds one table. Every gate of every Form has a row, and so does every
check that guards the repository as a whole.

| Column | Holds |
|---|---|
| Gate | `<crate>.G<n>`, matching the Form; or `repo.G<n>` for a repository-wide check |
| Form | `forms/<crate>.md`; `-` for a `repo` row |
| Mechanism | As in the Form |
| Location | The file that is the check |
| Command | The one command that runs it. A gate with no command cannot be run, so it is not a gate |
| Tier | The test tier that runs the command: `static`, `unit`, `contract`, `integration`, `e2e` or `live` |
| State | `live`: it runs in CI now. `planned`: it is specified and not built yet |

A cell may be wrapped in code ticks. A cell may not contain `|`.

`planned` exists because Forms are approved before the crates they describe are built. A
planned row is an honest statement that a check does not run yet; it turns `live` in the same
change that makes the check real.

## What parity checks

1. Every registry row names a Form that declares that gate, and every gate a Form declares has a
   registry row.
2. Every invariant is guarded by a gate or listed under Unenforced, and every id used is declared.
3. A `live` row's location exists, and its tier is one CI runs.
4. A Form with any live gate lists only interface files that exist.
5. Every Form is named after a workspace crate.
6. Every crate except `xtask` declares a `testkit` feature.
7. CI's per-crate unit matrix lists exactly the workspace's crates.

A malformed row or section is an error, never a row quietly skipped.

## Locked contract tests

A contract test tests a Form's interface from outside the crate. It is a test target under
`crates/<crate>/tests/` that the tier naming rule places in the `contract` tier: every file
there that is not an `e2e_*.rs`, a `live_*.rs`, a `*_it.rs` or a `characterisation_*.rs`. Name
one `contract_<name>.rs`. `forms/contract.lock.json` records the SHA-256 of every such file
(with CRLF folded to LF, so every platform agrees) and of the gate's own source.

`cargo xtask lock check` fails when a locked file changed or is missing, when a contract test
exists that the lock does not list, or when the gate itself changed. `cargo xtask lock accept`
rewrites the lock. Accepting is a decision, not a fix: the lock's diff is part of the pull
request and the owner reviews it.

## Changing a Form

- While `draft`: edit it, and keep parity green.
- Once `frozen`: an **additive** change (a new function or field that breaks no caller) needs
  the reviewer's approval and is recorded in the Form. A **breaking** change stops for the
  owner.
`````

- [ ] **Step 2: Write the failing tests**

In `xtask/src/lib.rs`, add `pub mod parity;` to the module list, below `pub mod metadata;`.
Create `xtask/src/parity.rs` with only its tests:

```rust
#[cfg(test)]
mod tests {
    use super::*;

    const REGISTRY: &str = "# Gate registry

| Gate | Form | Mechanism | Location | Command | Tier | State |
|---|---|---|---|---|---|---|
| repo.G1 | - | dependency direction | `xtask/src/deps.rs` | `cargo xtask deps` | static | live |
| speaker.G1 | forms/speaker.md | locked contract tests | `crates/speaker/tests/contract_speaker.rs` | `cargo xtask test contract` | contract | planned |
";

    const FORM: &str = "# Form: speaker

- status: draft
- owner: adbarc92
- level: E0
- last-drill: never
- interface-files:
  - crates/speaker/src/lib.rs
  - `crates/speaker/src/unit.rs`

## Purpose

Speaks the protocol.

## Interface

`open`, `Unit`.

## Invariants

I1. Nothing is written after the result.
I2. An interrupt is always answered.

## Hidden decisions

- Framing.

## Gates

| Gate | Guards | Mechanism | Location | Blocks |
|---|---|---|---|---|
| G1 | I1 | locked contract tests | crates/speaker/tests/contract_speaker.rs | merge |

## Unenforced

- I2: no test yet (2026-10-04)

## Regeneration notes

Run the contract tier.
";

    fn facts<'a>(exists: &'a dyn Fn(&str) -> bool) -> Facts<'a> {
        Facts {
            exists,
            ci_tiers: vec!["static".into(), "unit".into(), "contract".into()],
            ci_unit_crates: vec!["speaker".into(), "xtask".into()],
            members: vec!["speaker".into(), "xtask".into()],
            with_testkit: vec!["speaker".into()],
        }
    }

    fn parsed() -> (Vec<Row>, Vec<Form>) {
        (
            parse_registry(REGISTRY).unwrap(),
            vec![parse_form("speaker", FORM).unwrap()],
        )
    }

    #[test]
    fn a_consistent_registry_and_form_pass() {
        let (rows, forms) = parsed();
        assert_eq!(rows.len(), 2);
        assert_eq!(rows[1].location, "crates/speaker/tests/contract_speaker.rs");
        assert_eq!(forms[0].interface_files.len(), 2);
        assert_eq!(forms[0].invariants, vec!["I1", "I2"]);
        assert_eq!(forms[0].unenforced, vec!["I2"]);
        let everything = |_: &str| true;
        assert_eq!(
            check(&rows, &forms, &facts(&everything)),
            Vec::<String>::new()
        );
    }

    #[test]
    fn crlf_line_endings_parse_the_same() {
        let crlf = FORM.replace('\n', "\r\n");
        assert_eq!(
            parse_form("speaker", &crlf).unwrap(),
            parse_form("speaker", FORM).unwrap()
        );
        let registry = REGISTRY.replace('\n', "\r\n");
        assert_eq!(
            parse_registry(&registry).unwrap(),
            parse_registry(REGISTRY).unwrap()
        );
    }

    #[test]
    fn a_live_gate_must_exist_and_run_in_ci() {
        let (mut rows, forms) = parsed();
        rows[1].state = "live".into();
        rows[1].tier = "e2e".into();
        let nothing = |_: &str| false;
        let problems = check(&rows[1..], &forms, &facts(&nothing));
        assert!(problems.contains(
            &"speaker.G1: live, but crates/speaker/tests/contract_speaker.rs does not exist"
                .to_string()
        ));
        assert!(
            problems.contains(&"speaker.G1: live, but CI does not run the e2e tier".to_string())
        );
        assert!(problems
            .iter()
            .any(|p| p.contains("interface file crates/speaker/src/lib.rs does not exist")));
    }

    #[test]
    fn a_planned_gate_need_not_exist_yet() {
        let (rows, forms) = parsed();
        let only_deps = |path: &str| path == "xtask/src/deps.rs";
        assert_eq!(
            check(&rows, &forms, &facts(&only_deps)),
            Vec::<String>::new()
        );
    }

    #[test]
    fn the_registry_and_the_form_must_name_the_same_gates() {
        let (rows, mut forms) = parsed();
        let everything = |_: &str| true;
        let unregistered = check(&rows[..1], &forms, &facts(&everything));
        assert_eq!(
            unregistered,
            vec!["speaker.G1: declared in the Form, not registered"]
        );

        forms[0].gates.clear();
        forms[0].unenforced.push("I1".into());
        let undeclared = check(&rows, &forms, &facts(&everything));
        assert_eq!(undeclared, vec!["speaker.G1: the Form declares no G1"]);
    }

    #[test]
    fn an_invariant_needs_a_gate_or_an_unenforced_entry() {
        let (rows, mut forms) = parsed();
        forms[0].unenforced.clear();
        let everything = |_: &str| true;
        assert_eq!(
            check(&rows, &forms, &facts(&everything)),
            vec!["speaker I2: no gate guards it and it is not listed as unenforced"]
        );
    }

    #[test]
    fn every_crate_has_a_testkit_feature_and_a_unit_job() {
        let (rows, forms) = parsed();
        let everything = |_: &str| true;
        let mut f = facts(&everything);
        f.members.push("engine".into());
        f.ci_unit_crates.push("ghost".into());
        let problems = check(&rows, &forms, &f);
        assert_eq!(
            problems,
            vec![
                "engine: declares no `testkit` feature",
                "engine: missing from CI's unit matrix",
                "CI's unit matrix lists ghost, which is not a crate",
            ]
        );
    }

    #[test]
    fn a_form_must_be_named_after_a_crate() {
        let (rows, forms) = parsed();
        let everything = |_: &str| true;
        let mut f = facts(&everything);
        f.members = vec!["xtask".into()];
        f.ci_unit_crates = vec!["xtask".into()];
        assert_eq!(
            check(&rows, &forms, &f),
            vec!["forms/speaker.md: there is no crate named speaker"]
        );
    }

    #[test]
    fn malformed_documents_are_errors_not_skipped_rows() {
        let short = "| speaker.G1 | forms/speaker.md | tests |\n";
        assert!(parse_registry(short).unwrap_err().contains("7 cells"));
        let unnamed = REGISTRY.replace("speaker.G1", "G1");
        assert!(parse_registry(&unnamed)
            .unwrap_err()
            .contains("not <form>.G<n>"));
        let twice = format!("{REGISTRY}{}", REGISTRY.lines().last().unwrap());
        assert!(parse_registry(&twice)
            .unwrap_err()
            .contains("registered twice"));

        let missing = FORM.replace("## Hidden decisions", "## Secrets");
        assert!(parse_form("speaker", &missing)
            .unwrap_err()
            .contains("sections must be exactly"));
        let toothless = FORM.replace("| merge |", "| |");
        assert!(parse_form("speaker", &toothless)
            .unwrap_err()
            .contains("blocks nothing"));
        assert!(parse_form("engine", FORM)
            .unwrap_err()
            .contains("# Form: engine"));
        let vague = FORM.replace("- I2: no test yet (2026-10-04)", "- later");
        assert!(parse_form("speaker", &vague)
            .unwrap_err()
            .contains("under Unenforced"));
    }

    #[test]
    fn the_workflow_is_read_for_tiers_and_the_unit_matrix() {
        let workflow = "jobs:\n  static:\n    steps:\n      - run: cargo xtask test static\n  unit:\n    strategy:\n      matrix:\n        os: [ubuntu-latest, windows-latest]\n        crate: [engine, speaker, xtask]\n    steps:\n      - run: cargo xtask test unit ${{ matrix.crate }}\n";
        assert_eq!(ci_tiers(workflow), vec!["static", "unit"]);
        assert_eq!(ci_unit_crates(workflow), vec!["engine", "speaker", "xtask"]);
    }
}
```

- [ ] **Step 3: Run them and watch them fail**

Run: `cargo test -p xtask --lib parity::`

Expected: it does not compile; the errors name `parse_registry`, `parse_form`, `check`,
`Facts` and `Row`.

- [ ] **Step 4: Write the implementation**

Put this above the test module in `xtask/src/parity.rs`:

```rust
//! Registry parity: the gate registry, the Forms and what CI runs must agree.
//!
//! The formats this module reads are documented in `docs/forms.md`. The checks:
//!
//! 1. Every registry row names a Form that declares that gate, and every gate a Form declares
//!    has a registry row.
//! 2. Every invariant is guarded by a gate or listed under Unenforced.
//! 3. A `live` row's location exists and its tier is one CI runs.
//! 4. A Form with a live gate lists only interface files that exist.
//! 5. A Form is named after a workspace crate.
//! 6. Every crate except `xtask` declares a `testkit` feature.
//! 7. CI's per-crate unit matrix lists exactly the workspace's crates.

use crate::metadata::Graph;
use crate::TIERS;
use std::path::Path;

pub const SECTIONS: [&str; 7] = [
    "Purpose",
    "Interface",
    "Invariants",
    "Hidden decisions",
    "Gates",
    "Unenforced",
    "Regeneration notes",
];
pub const STATUSES: [&str; 3] = ["draft", "frozen", "deprecated"];
pub const LEVELS: [&str; 4] = ["E0", "E1", "E2", "E3"];
pub const STATES: [&str; 2] = ["live", "planned"];
/// The owner of a registry row that guards the repository as a whole, not one Form.
pub const REPO: &str = "repo";

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Row {
    /// `<form>.G<n>`, or `repo.G<n>`.
    pub gate: String,
    pub form: String,
    pub mechanism: String,
    pub location: String,
    pub command: String,
    pub tier: String,
    pub state: String,
}

impl Row {
    pub fn owner(&self) -> &str {
        self.gate.split_once('.').map(|(o, _)| o).unwrap_or("")
    }
    pub fn local_id(&self) -> &str {
        self.gate.split_once('.').map(|(_, g)| g).unwrap_or("")
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct FormGate {
    pub id: String,
    pub guards: Vec<String>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Form {
    pub name: String,
    pub status: String,
    pub interface_files: Vec<String>,
    pub invariants: Vec<String>,
    pub gates: Vec<FormGate>,
    pub unenforced: Vec<String>,
}

/// What parity needs to know about the repository besides the two documents.
pub struct Facts<'a> {
    pub exists: &'a dyn Fn(&str) -> bool,
    /// Tiers the CI workflow runs.
    pub ci_tiers: Vec<String>,
    /// The crates in CI's unit matrix.
    pub ci_unit_crates: Vec<String>,
    pub members: Vec<String>,
    pub with_testkit: Vec<String>,
}

fn numbered(id: &str, letter: char) -> bool {
    let mut chars = id.chars();
    chars.next() == Some(letter) && id.len() > 1 && chars.all(|c| c.is_ascii_digit())
}

/// The cells of a markdown table line, trimmed and without code ticks.
fn cells(line: &str) -> Option<Vec<String>> {
    let line = line.trim();
    if line.len() < 2 || !line.starts_with('|') || !line.ends_with('|') {
        return None;
    }
    Some(
        line[1..line.len() - 1]
            .split('|')
            .map(|cell| cell.trim().trim_matches('`').to_string())
            .collect(),
    )
}

fn is_rule(cells: &[String]) -> bool {
    cells
        .iter()
        .all(|c| !c.is_empty() && c.chars().all(|ch| ch == '-' || ch == ':'))
}

pub fn parse_registry(text: &str) -> Result<Vec<Row>, String> {
    let mut rows = Vec::new();
    for (index, line) in text.lines().enumerate() {
        let Some(c) = cells(line) else { continue };
        if c[0] == "Gate" || is_rule(&c) {
            continue;
        }
        let at = format!("forms/registry.md line {}", index + 1);
        if c.len() != 7 {
            return Err(format!("{at}: a row has 7 cells, this has {}", c.len()));
        }
        let row = Row {
            gate: c[0].clone(),
            form: c[1].clone(),
            mechanism: c[2].clone(),
            location: c[3].clone(),
            command: c[4].clone(),
            tier: c[5].clone(),
            state: c[6].clone(),
        };
        if row.owner().is_empty() || !numbered(row.local_id(), 'G') {
            return Err(format!("{at}: `{}` is not <form>.G<n>", row.gate));
        }
        if rows.iter().any(|r: &Row| r.gate == row.gate) {
            return Err(format!("{at}: `{}` is registered twice", row.gate));
        }
        rows.push(row);
    }
    Ok(rows)
}

fn header_value(head: &[&str], key: &str) -> Option<String> {
    let prefix = format!("- {key}:");
    head.iter()
        .find_map(|line| line.strip_prefix(&prefix))
        .map(|v| v.trim().to_string())
}

/// Parse `forms/<name>.md`. The first problem found is the error.
pub fn parse_form(name: &str, text: &str) -> Result<Form, String> {
    let at = format!("forms/{name}.md");
    let lines: Vec<&str> = text.lines().collect();
    if lines.first().map(|l| l.trim()) != Some(format!("# Form: {name}").as_str()) {
        return Err(format!("{at}: the first line must be `# Form: {name}`"));
    }

    let mut order = Vec::new();
    for (index, line) in lines.iter().enumerate() {
        if let Some(title) = line.strip_prefix("## ") {
            order.push((title.trim().to_string(), index));
        }
    }
    let titles: Vec<&str> = order.iter().map(|(t, _)| t.as_str()).collect();
    if titles != SECTIONS {
        return Err(format!(
            "{at}: sections must be exactly {SECTIONS:?}, in that order; found {titles:?}"
        ));
    }
    let section = |title: &str| -> &[&str] {
        let position = order.iter().position(|(t, _)| t == title).unwrap_or(0);
        let start = order[position].1 + 1;
        let end = order.get(position + 1).map_or(lines.len(), |(_, i)| *i);
        &lines[start..end]
    };

    let head = &lines[1..order[0].1];
    let status = header_value(head, "status").unwrap_or_default();
    if !STATUSES.contains(&status.as_str()) {
        return Err(format!("{at}: `- status:` must be one of {STATUSES:?}"));
    }
    if header_value(head, "owner").unwrap_or_default().is_empty() {
        return Err(format!("{at}: `- owner:` must name a person"));
    }
    let level = header_value(head, "level").unwrap_or_default();
    if !LEVELS.contains(&level.as_str()) {
        return Err(format!("{at}: `- level:` must be one of {LEVELS:?}"));
    }
    if header_value(head, "last-drill")
        .unwrap_or_default()
        .is_empty()
    {
        return Err(format!("{at}: `- last-drill:` must be a date or `never`"));
    }
    let Some(list_at) = head.iter().position(|l| l.trim() == "- interface-files:") else {
        return Err(format!("{at}: the header must have `- interface-files:`"));
    };
    let interface_files: Vec<String> = head[list_at + 1..]
        .iter()
        .map_while(|line| line.strip_prefix("  - "))
        .map(|path| path.trim().trim_matches('`').to_string())
        .collect();
    if interface_files.is_empty() {
        return Err(format!("{at}: `- interface-files:` lists no file"));
    }

    let invariants: Vec<String> = section("Invariants")
        .iter()
        .filter_map(|line| line.split_once(". "))
        .map(|(id, _)| id.trim().to_string())
        .filter(|id| numbered(id, 'I'))
        .collect();
    if invariants.is_empty() {
        return Err(format!(
            "{at}: no invariant; write each as `I<n>. <sentence>`"
        ));
    }

    let mut gates = Vec::new();
    for line in section("Gates") {
        let Some(c) = cells(line) else { continue };
        if c[0] == "Gate" || is_rule(&c) {
            continue;
        }
        if c.len() != 5 || !numbered(&c[0], 'G') {
            return Err(format!(
                "{at}: a gate row is `| G<n> | guards | mechanism | location | blocks |`"
            ));
        }
        let guards: Vec<String> = c[1].split(',').map(|g| g.trim().to_string()).collect();
        if guards.iter().any(|g| !numbered(g, 'I')) {
            return Err(format!(
                "{at}: {} guards `{}`: list invariant ids",
                c[0], c[1]
            ));
        }
        if c[4].is_empty() {
            return Err(format!("{at}: {} blocks nothing; a gate must block", c[0]));
        }
        gates.push(FormGate {
            id: c[0].clone(),
            guards,
        });
    }

    let mut unenforced = Vec::new();
    for line in section("Unenforced") {
        let line = line.trim();
        if line.is_empty() || line == "None." {
            continue;
        }
        let id = line
            .strip_prefix("- ")
            .and_then(|rest| rest.split_once(':'))
            .map(|(id, _)| id.trim().to_string());
        match id {
            Some(id) if numbered(&id, 'I') => unenforced.push(id),
            _ => {
                return Err(format!(
                    "{at}: under Unenforced write `None.` or `- I<n>: reason (date)`"
                ))
            }
        }
    }

    Ok(Form {
        name: name.to_string(),
        status,
        interface_files,
        invariants,
        gates,
        unenforced,
    })
}

/// The tiers a workflow runs: every `cargo xtask test <tier>` in it.
pub fn ci_tiers(workflow: &str) -> Vec<String> {
    let mut tiers = Vec::new();
    for piece in workflow.split("cargo xtask test ").skip(1) {
        let tier: String = piece
            .chars()
            .take_while(|c| c.is_ascii_alphanumeric())
            .collect();
        if !tier.is_empty() && !tiers.contains(&tier) {
            tiers.push(tier);
        }
    }
    tiers
}

/// The unit matrix: the workflow's `crate: [a, b, c]` line.
pub fn ci_unit_crates(workflow: &str) -> Vec<String> {
    workflow
        .lines()
        .filter_map(|line| line.trim().strip_prefix("crate: ["))
        .filter_map(|rest| rest.strip_suffix(']'))
        .flat_map(|inner| inner.split(','))
        .map(|name| name.trim().to_string())
        .filter(|name| !name.is_empty())
        .collect()
}

/// Every check, over parsed documents. Pure.
pub fn check(rows: &[Row], forms: &[Form], facts: &Facts) -> Vec<String> {
    let mut problems = Vec::new();

    for row in rows {
        let gate = &row.gate;
        if !STATES.contains(&row.state.as_str()) {
            problems.push(format!(
                "{gate}: state `{}` is not live or planned",
                row.state
            ));
        }
        if !TIERS.contains(&row.tier.as_str()) {
            problems.push(format!("{gate}: `{}` is not a tier", row.tier));
        }
        if row.command.is_empty() || row.mechanism.is_empty() || row.location.is_empty() {
            problems.push(format!(
                "{gate}: mechanism, location and command are all required"
            ));
        }
        if row.state == "live" {
            if !(facts.exists)(&row.location) {
                problems.push(format!("{gate}: live, but {} does not exist", row.location));
            }
            if !facts.ci_tiers.contains(&row.tier) {
                problems.push(format!(
                    "{gate}: live, but CI does not run the {} tier",
                    row.tier
                ));
            }
        }
        if row.owner() == REPO {
            continue;
        }
        if row.form != format!("forms/{}.md", row.owner()) {
            problems.push(format!(
                "{gate}: its Form cell must be forms/{}.md",
                row.owner()
            ));
        }
        match forms.iter().find(|f| f.name == row.owner()) {
            None => problems.push(format!("{gate}: forms/{}.md does not exist", row.owner())),
            Some(form) if !form.gates.iter().any(|g| g.id == row.local_id()) => {
                problems.push(format!("{gate}: the Form declares no {}", row.local_id()))
            }
            Some(_) => {}
        }
    }

    for form in forms {
        let name = &form.name;
        if !facts.members.contains(name) {
            problems.push(format!("forms/{name}.md: there is no crate named {name}"));
        }
        for gate in &form.gates {
            if !rows.iter().any(|r| r.gate == format!("{name}.{}", gate.id)) {
                problems.push(format!(
                    "{name}.{}: declared in the Form, not registered",
                    gate.id
                ));
            }
            for guard in &gate.guards {
                if !form.invariants.contains(guard) {
                    problems.push(format!(
                        "{name}.{}: guards {guard}, which is not declared",
                        gate.id
                    ));
                }
            }
        }
        for invariant in &form.invariants {
            let guarded = form.gates.iter().any(|g| g.guards.contains(invariant));
            if !guarded && !form.unenforced.contains(invariant) {
                problems.push(format!(
                    "{name} {invariant}: no gate guards it and it is not listed as unenforced"
                ));
            }
        }
        for listed in &form.unenforced {
            if !form.invariants.contains(listed) {
                problems.push(format!(
                    "{name}: {listed} is listed as unenforced but not declared"
                ));
            }
        }
        let built = rows.iter().any(|r| r.owner() == name && r.state == "live");
        if built {
            for file in &form.interface_files {
                if !(facts.exists)(file) {
                    problems.push(format!(
                        "forms/{name}.md: interface file {file} does not exist"
                    ));
                }
            }
        }
    }

    for member in &facts.members {
        if member != "xtask" && !facts.with_testkit.contains(member) {
            problems.push(format!("{member}: declares no `testkit` feature"));
        }
        if !facts.ci_unit_crates.contains(member) {
            problems.push(format!("{member}: missing from CI's unit matrix"));
        }
    }
    for listed in &facts.ci_unit_crates {
        if !facts.members.contains(listed) {
            problems.push(format!(
                "CI's unit matrix lists {listed}, which is not a crate"
            ));
        }
    }

    problems
}

pub fn run() -> Result<(), String> {
    let root = crate::repo_root();
    let read = |relative: &str| {
        std::fs::read_to_string(root.join(relative)).map_err(|e| format!("{relative}: {e}"))
    };
    let rows = parse_registry(&read("forms/registry.md")?)?;

    let mut forms = Vec::new();
    for path in crate::files_under(&root.join("forms")) {
        let name = path.file_stem().unwrap_or_default().to_string_lossy();
        let is_form = path.extension().is_some_and(|e| e == "md") && name != "registry";
        if is_form {
            let text = std::fs::read_to_string(&path).map_err(|e| format!("{path:?}: {e}"))?;
            forms.push(parse_form(&name, &text)?);
        }
    }

    let graph = Graph::load()?;
    let workflow = read(".github/workflows/ci.yml")?;
    let exists = |relative: &str| Path::new(&root).join(relative).exists();
    let facts = Facts {
        exists: &exists,
        ci_tiers: ci_tiers(&workflow),
        ci_unit_crates: ci_unit_crates(&workflow),
        with_testkit: graph
            .packages
            .iter()
            .filter(|p| graph.is_member(&p.name) && p.features.iter().any(|f| f == "testkit"))
            .map(|p| p.name.clone())
            .collect(),
        members: graph.members.clone(),
    };
    crate::verdict(
        "parity",
        format!("{} gates, {} Forms", rows.len(), forms.len()),
        check(&rows, &forms, &facts),
    )
}
```

- [ ] **Step 5: Run the tests**

Run: `cargo test -p xtask --lib parity::`

Expected: `test result: ok. 10 passed`.

- [ ] **Step 6: Commit**

```bash
git add xtask/src/parity.rs xtask/src/lib.rs docs/forms.md
git commit -m "feat(xtask): registry parity gate, and the Form and registry formats"
```

### Task 6: `cargo xtask lock`, the freeze gate over contract tests

**Files:**
- Create: `xtask/src/lock.rs`
- Modify: `xtask/src/lib.rs` (one line)

**Interfaces:**
- Consumes: `xtask::{files_under, relative, tier_of_test_target, verdict}`.
- Produces, in `xtask::lock`:
  - `pub const LOCK: &str = "forms/contract.lock.json"`, `pub const GATE: &str = "xtask/src/lock.rs"`
  - `pub fn sha256_normalised(bytes: &[u8]) -> String`
  - `pub fn test_targets(root: &Path, tier: &str) -> Vec<(String, String, String)>` — `(path, crate, test target)` for every `crates/<crate>/tests/<name>.rs` that `xtask::tier_of_test_target` places in `tier`
  - `pub struct Lock { pub conformance_kit: bool, pub gate_sha256: String, pub files: BTreeMap<String, String> }` with `Lock::parse(text: &str) -> Result<Lock, String>` and `Lock::render(&self) -> String`
  - `pub fn compare(lock: &Lock, actual: &BTreeMap<String, String>, gate_hash: &str) -> Vec<String>`
  - `pub fn read(root: &Path) -> Result<Lock, String>`, `pub fn check(root: &Path) -> Result<(), String>`, `pub fn accept(root: &Path) -> Result<(), String>`
  - the file `forms/contract.lock.json`: `{ "version": 1, "conformance_kit": bool, "gate_sha256": hex, "files": [{ "path", "sha256" }] }`

This ports the Bash suite's freeze gate (`archive/bash-v0.3/tests/oracle-gate.sh`) in spirit:
whole-file hashes, the gate hashes itself, an unregistered test fails, and re-locking is a
deliberate act. It does not port the per-test name list; a failing or missing test is caught by
`cargo test` itself.

What is locked is the whole contract tier: every test target the naming rule places there,
not only files that happen to be called `contract_*.rs`. So a new file under `tests/` that
is not named for another tier is caught as an unregistered contract test.

- [ ] **Step 1: Write the failing tests**

In `xtask/src/lib.rs`, add `pub mod lock;` to the module list, above `pub mod metadata;`.
Create `xtask/src/lock.rs` with only its tests:

```rust
#[cfg(test)]
mod tests {
    use super::*;

    fn lock(files: &[(&str, &str)]) -> Lock {
        Lock {
            conformance_kit: false,
            gate_sha256: "gate".into(),
            files: files
                .iter()
                .map(|(p, h)| (p.to_string(), h.to_string()))
                .collect(),
        }
    }

    fn tree(files: &[(&str, &str)]) -> BTreeMap<String, String> {
        files
            .iter()
            .map(|(p, h)| (p.to_string(), h.to_string()))
            .collect()
    }

    const A: &str = "crates/speaker/tests/contract_speaker.rs";
    const B: &str = "crates/cli/tests/contract_harness_process.rs";

    #[test]
    fn an_unchanged_tree_passes() {
        let problems = compare(
            &lock(&[(A, "1"), (B, "2")]),
            &tree(&[(A, "1"), (B, "2")]),
            "gate",
        );
        assert_eq!(problems, Vec::<String>::new());
    }

    #[test]
    fn a_changed_locked_file_needs_a_human() {
        let problems = compare(&lock(&[(A, "1")]), &tree(&[(A, "9")]), "gate");
        assert_eq!(problems.len(), 1);
        assert!(problems[0].starts_with(&format!("NEEDS_HUMAN: {A} changed (locked 1, now 9)")));
    }

    #[test]
    fn a_missing_locked_file_fails() {
        let problems = compare(&lock(&[(A, "1")]), &tree(&[]), "gate");
        assert_eq!(
            problems,
            vec![format!("{A}: locked, but missing (renamed or deleted)")]
        );
    }

    #[test]
    fn an_unregistered_contract_test_needs_a_human() {
        let problems = compare(&lock(&[]), &tree(&[(B, "2")]), "gate");
        assert!(problems[0].contains("is a contract test the lock does not know"));
    }

    #[test]
    fn a_changed_gate_needs_a_human() {
        let problems = compare(&lock(&[]), &tree(&[]), "different");
        assert!(problems[0].starts_with("NEEDS_HUMAN: xtask/src/lock.rs changed"));
    }

    #[test]
    fn the_hash_ignores_crlf_and_nothing_else() {
        assert_eq!(
            sha256_normalised(b"a\r\nb\r\n"),
            sha256_normalised(b"a\nb\n")
        );
        assert_ne!(sha256_normalised(b"a\nb\n"), sha256_normalised(b"a\nb"));
        assert_eq!(
            sha256_normalised(b"abc"),
            "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        );
    }

    #[test]
    fn a_lock_survives_a_round_trip_and_keeps_the_kit_switch() {
        let mut original = lock(&[(A, "1"), (B, "2")]);
        original.conformance_kit = true;
        let text = original.render();
        assert!(text.ends_with("}\n"));
        assert_eq!(Lock::parse(&text).unwrap(), original);
        assert_eq!(Lock::parse(&text.replace('\n', "\r\n")).unwrap(), original);
    }
    #[test]
    fn test_targets_are_found_per_tier_by_file_name() {
        let root = std::env::temp_dir().join(format!("xtask-targets-{}", std::process::id()));
        let tests = root.join("crates").join("demo").join("tests");
        std::fs::create_dir_all(&tests).unwrap();
        for name in [
            "contract_demo.rs",
            "vectors.rs",
            "docker_it.rs",
            "characterisation_old.rs",
            "e2e_whole.rs",
            "live_models.rs",
            "notes.md",
        ] {
            std::fs::write(tests.join(name), "").unwrap();
        }
        // A file that is not directly under `crates/<crate>/tests/` is not a test target.
        std::fs::create_dir_all(tests.join("support")).unwrap();
        std::fs::write(tests.join("support").join("helper.rs"), "").unwrap();

        let names = |tier: &str| -> Vec<String> {
            test_targets(&root, tier)
                .into_iter()
                .map(|(path, krate, target)| {
                    assert_eq!(krate, "demo");
                    assert_eq!(path, format!("crates/demo/tests/{target}.rs"));
                    target
                })
                .collect()
        };
        assert_eq!(names("contract"), vec!["contract_demo", "vectors"]);
        assert_eq!(names("integration"), vec!["docker_it"]);
        assert_eq!(names("unit"), vec!["characterisation_old"]);
        assert_eq!(names("e2e"), vec!["e2e_whole"]);
        assert_eq!(names("live"), vec!["live_models"]);
        assert!(names("static").is_empty());
        std::fs::remove_dir_all(&root).unwrap();
    }
}
```

- [ ] **Step 2: Run them and watch them fail**

Run: `cargo test -p xtask --lib lock::`

Expected: it does not compile; the errors name `Lock`, `compare` and `sha256_normalised`.

- [ ] **Step 3: Write the implementation**

Put this above the test module in `xtask/src/lock.rs`:

```rust
//! The freeze gate over the locked contract tests.
//!
//! A contract test is a test target `crates/<crate>/tests/<name>.rs` that the naming rule
//! ([`crate::tier_of_test_target`]) places in the `contract` tier: every one that is not an
//! `e2e_*`, a `live_*`, a `*_it` or a `characterisation_*`. By convention it is named
//! `contract_<name>.rs`. `forms/contract.lock.json` records the SHA-256 of each one and of
//! this file. `check` fails when a locked file changed or went missing, when a contract test
//! exists that the lock does not know, or when this gate itself changed. `accept` rewrites the
//! lock; that is a deliberate act whose diff is reviewed.
//!
//! Hashes are taken over the file with CRLF folded to LF, so a checkout on Windows and one on
//! Linux agree.

use serde_json::{json, Value};
use sha2::{Digest, Sha256};
use std::collections::BTreeMap;
use std::path::Path;

pub const LOCK: &str = "forms/contract.lock.json";
pub const GATE: &str = "xtask/src/lock.rs";

pub fn sha256_normalised(bytes: &[u8]) -> String {
    let text = String::from_utf8_lossy(bytes).replace("\r\n", "\n");
    Sha256::digest(text.as_bytes())
        .iter()
        .map(|byte| format!("{byte:02x}"))
        .collect()
}

/// Every test target the naming rule places in `tier`:
/// `(repository-relative path, crate, test target name)`, sorted.
pub fn test_targets(root: &Path, tier: &str) -> Vec<(String, String, String)> {
    let mut found = Vec::new();
    for path in crate::files_under(&root.join("crates")) {
        let relative = crate::relative(root, &path);
        let parts: Vec<&str> = relative.split('/').collect();
        if let ["crates", krate, "tests", file] = parts.as_slice() {
            if let Some(stem) = file.strip_suffix(".rs") {
                if crate::tier_of_test_target(stem) == tier {
                    found.push((relative.clone(), krate.to_string(), stem.to_string()));
                }
            }
        }
    }
    found.sort();
    found
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Lock {
    /// Whether the contract tier must run the control plane's conformance kit.
    pub conformance_kit: bool,
    pub gate_sha256: String,
    /// Path to hash.
    pub files: BTreeMap<String, String>,
}

impl Lock {
    pub fn parse(text: &str) -> Result<Lock, String> {
        let value: Value = serde_json::from_str(text).map_err(|e| format!("{LOCK}: {e}"))?;
        let mut files = BTreeMap::new();
        for entry in value["files"]
            .as_array()
            .ok_or_else(|| format!("{LOCK}: `files` must be a list"))?
        {
            match (entry["path"].as_str(), entry["sha256"].as_str()) {
                (Some(path), Some(hash)) => files.insert(path.to_string(), hash.to_string()),
                _ => return Err(format!("{LOCK}: every entry needs `path` and `sha256`")),
            };
        }
        Ok(Lock {
            conformance_kit: value["conformance_kit"].as_bool().unwrap_or(false),
            gate_sha256: value["gate_sha256"]
                .as_str()
                .unwrap_or_default()
                .to_string(),
            files,
        })
    }

    pub fn render(&self) -> String {
        let files: Vec<Value> = self
            .files
            .iter()
            .map(|(path, hash)| json!({ "path": path, "sha256": hash }))
            .collect();
        let value = json!({
            "version": 1,
            "conformance_kit": self.conformance_kit,
            "gate_sha256": self.gate_sha256,
            "files": files,
        });
        let mut text = serde_json::to_string_pretty(&value).expect("a lock always serialises");
        text.push('\n');
        text
    }
}

/// Compare a lock with the tree. Pure: `actual` is path to hash for every contract test found.
pub fn compare(lock: &Lock, actual: &BTreeMap<String, String>, gate_hash: &str) -> Vec<String> {
    let mut problems = Vec::new();
    if lock.gate_sha256 != gate_hash {
        problems.push(format!(
            "NEEDS_HUMAN: {GATE} changed. Review the diff, then re-lock with `cargo xtask lock accept`."
        ));
    }
    for (path, locked) in &lock.files {
        match actual.get(path) {
            None => problems.push(format!(
                "{path}: locked, but missing (renamed or deleted)"
            )),
            Some(now) if now != locked => problems.push(format!(
                "NEEDS_HUMAN: {path} changed (locked {locked}, now {now}). Review the diff, then re-lock with `cargo xtask lock accept`."
            )),
            Some(_) => {}
        }
    }
    for path in actual.keys() {
        if !lock.files.contains_key(path) {
            problems.push(format!(
                "NEEDS_HUMAN: {path} is a contract test the lock does not know. Review it, then add it with `cargo xtask lock accept`."
            ));
        }
    }
    problems
}

fn hash_file(root: &Path, relative: &str) -> Result<String, String> {
    std::fs::read(root.join(relative))
        .map(|bytes| sha256_normalised(&bytes))
        .map_err(|e| format!("{relative}: {e}"))
}

fn actual(root: &Path) -> Result<BTreeMap<String, String>, String> {
    let mut hashes = BTreeMap::new();
    for (path, _, _) in test_targets(root, "contract") {
        let hash = hash_file(root, &path)?;
        hashes.insert(path, hash);
    }
    Ok(hashes)
}

pub fn read(root: &Path) -> Result<Lock, String> {
    let text = std::fs::read_to_string(root.join(LOCK))
        .map_err(|e| format!("{LOCK}: {e}. Create it with `cargo xtask lock accept`."))?;
    Lock::parse(&text)
}

pub fn check(root: &Path) -> Result<(), String> {
    let lock = read(root)?;
    let problems = compare(&lock, &actual(root)?, &hash_file(root, GATE)?);
    crate::verdict(
        "lock",
        format!("{} locked contract tests unchanged", lock.files.len()),
        problems,
    )
}

pub fn accept(root: &Path) -> Result<(), String> {
    let conformance_kit = read(root).map(|lock| lock.conformance_kit).unwrap_or(false);
    let lock = Lock {
        conformance_kit,
        gate_sha256: hash_file(root, GATE)?,
        files: actual(root)?,
    };
    std::fs::write(root.join(LOCK), lock.render()).map_err(|e| format!("{LOCK}: {e}"))?;
    println!("lock: regenerated with {} contract tests", lock.files.len());
    for (path, hash) in &lock.files {
        println!("  {hash}  {path}");
    }
    Ok(())
}
```

- [ ] **Step 4: Run the tests**

Run: `cargo test -p xtask --lib lock::`

Expected: `test result: ok. 8 passed`.

- [ ] **Step 5: Commit the gate**

The lock file itself is created in Task 8, when `cargo xtask lock accept` exists as a command.

```bash
git add xtask/src/lock.rs xtask/src/lib.rs
git commit -m "feat(xtask): freeze gate over the locked contract tests"
```

### Task 7: The conformance kit runner

**Files:**
- Create: `xtask/src/kit.rs`
- Modify: `xtask/src/lib.rs` (one line)

**Interfaces:**
- Consumes: `metadata::Graph`, `xtask::{cargo, run}`.
- Produces, in `xtask::kit`:
  - `pub const KIT_REPO: &str = "https://github.com/adbarc92/command-center"`, `KIT_PACKAGE`, `KIT_BINARY`, `pub const HARNESS_ARGS: [&str; 2] = ["harness", "--fake"]`
  - `pub fn tag_from_source(source: &str) -> Option<String>`, `pub fn pinned_tag(graph: &Graph) -> Option<String>`
  - `pub fn kit_dir(root: &Path, tag: &str) -> PathBuf`, `pub fn exe(name: &str) -> String`
  - `pub fn summary(stdout: &str) -> Result<(u32, u32, u32), String>`, `pub fn judge(stdout: &str, exited_ok: bool) -> Result<String, String>`
  - `pub fn run(root: &Path, graph: &Graph) -> Result<(), String>`

Nothing calls `kit::run` until RD-SKEL turns it on: the kit needs the contract tag and a
`harness` command, and neither exists yet. What is tested here is everything around the
process: reading the tag, the cache path, and judging the kit's output.

- [ ] **Step 1: Write the failing tests**

In `xtask/src/lib.rs`, add `pub mod kit;` to the module list, above `pub mod lock;`. Create
`xtask/src/kit.rs` with only its tests:

```rust
#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_kit_tag_is_read_from_the_pinned_source() {
        let source = "git+https://github.com/adbarc92/command-center?tag=contracts-v0.2.0#0123abc";
        assert_eq!(tag_from_source(source), Some("contracts-v0.2.0".into()));
        assert_eq!(
            tag_from_source("git+https://x/y?tag=contracts-v0.2.0"),
            Some("contracts-v0.2.0".into())
        );
        assert_eq!(tag_from_source("git+https://x/y?rev=abc#abc"), None);
        assert_eq!(
            tag_from_source("registry+https://github.com/rust-lang/crates.io-index"),
            None
        );
    }

    #[test]
    fn the_kit_is_cached_per_tag() {
        let dir = kit_dir(Path::new("repo"), "contracts-v0.2.0");
        assert_eq!(
            crate::relative(Path::new("repo"), &dir),
            ".kit/contracts-v0.2.0"
        );
    }

    #[test]
    fn a_clean_run_passes() {
        let out = "PASS  happy_path_t1\nPASS  halt\n2 passed, 0 skipped, 0 failed\n";
        assert_eq!(judge(out, true).unwrap(), "2 passed, 0 skipped, 0 failed");
    }

    #[test]
    fn a_failure_a_skip_or_silence_fails() {
        let failed = "FAIL  halt  InterruptNotHonored\n5 passed, 0 skipped, 1 failed\n";
        assert!(judge(failed, false)
            .unwrap_err()
            .contains("1 case(s) failed"));
        let skipped = "SKIP  halt  (harness declares halt: false)\n5 passed, 1 skipped, 0 failed\n";
        assert!(judge(skipped, true).unwrap_err().contains("skipped"));
        assert!(judge("", true).unwrap_err().contains("printed nothing"));
        assert!(judge("0 passed, 0 skipped, 0 failed\n", true)
            .unwrap_err()
            .contains("no case ran"));
        assert!(judge("thread panicked\n", true)
            .unwrap_err()
            .contains("not a summary"));
        assert!(judge("6 passed, 0 skipped, 0 failed\n", false).is_err());
    }
}
```

- [ ] **Step 2: Run them and watch them fail**

Run: `cargo test -p xtask --lib kit::`

Expected: it does not compile; the errors name `tag_from_source`, `kit_dir` and `judge`.

- [ ] **Step 3: Write the implementation**

Put this above the test module in `xtask/src/kit.rs`:

```rust
//! The control plane's conformance kit, run against `reqdrive harness --fake`.
//!
//! The kit is a binary built from the control plane's repository at the same tag the contract
//! crates are pinned to, so the kit and the wire types can never disagree. It is installed once
//! into `.kit/<tag>/` and reused; CI caches that directory.

use crate::metadata::Graph;
use std::path::{Path, PathBuf};
use std::process::Command;

pub const KIT_REPO: &str = "https://github.com/adbarc92/command-center";
pub const KIT_PACKAGE: &str = "harness-conformance";
pub const KIT_BINARY: &str = "harness-conformance";
/// The arguments that make `reqdrive` a harness on fakes.
pub const HARNESS_ARGS: [&str; 2] = ["harness", "--fake"];

/// The tag in a git source such as `git+https://host/repo?tag=contracts-v0.2.0`, with or
/// without a trailing `#<commit>`.
pub fn tag_from_source(source: &str) -> Option<String> {
    let (_, rest) = source.split_once("?tag=")?;
    let tag = rest.split('#').next()?;
    (!tag.is_empty()).then(|| tag.to_string())
}

/// The tag `harness-protocol` is pinned to, which is the kit's tag too.
pub fn pinned_tag(graph: &Graph) -> Option<String> {
    graph
        .package("harness-protocol")
        .and_then(|package| package.source.as_deref())
        .and_then(tag_from_source)
}

pub fn kit_dir(root: &Path, tag: &str) -> PathBuf {
    root.join(".kit").join(tag)
}

pub fn exe(name: &str) -> String {
    format!("{name}{}", std::env::consts::EXE_SUFFIX)
}

/// Read the kit's last line, `<n> passed, <n> skipped, <n> failed`. A skipped case means the
/// harness declared it lacks a capability; this harness declares them all, so a skip fails.
pub fn summary(stdout: &str) -> Result<(u32, u32, u32), String> {
    let last = stdout
        .lines()
        .rev()
        .find(|line| !line.trim().is_empty())
        .ok_or("the conformance kit printed nothing")?;
    let numbers: Vec<u32> = last
        .split(|c: char| !c.is_ascii_digit())
        .filter(|piece| !piece.is_empty())
        .filter_map(|piece| piece.parse().ok())
        .collect();
    let shaped = last.contains("passed") && last.contains("skipped") && last.contains("failed");
    match numbers.as_slice() {
        [passed, skipped, failed] if shaped => Ok((*passed, *skipped, *failed)),
        _ => Err(format!(
            "the conformance kit's last line is not a summary: {last}"
        )),
    }
}

pub fn judge(stdout: &str, exited_ok: bool) -> Result<String, String> {
    let (passed, skipped, failed) = summary(stdout)?;
    if !exited_ok || failed > 0 {
        return Err(format!("conformance: {failed} case(s) failed"));
    }
    if skipped > 0 {
        return Err(format!(
            "conformance: {skipped} case(s) skipped; this harness may skip none"
        ));
    }
    if passed == 0 {
        return Err("conformance: no case ran".into());
    }
    Ok(format!("{passed} passed, 0 skipped, 0 failed"))
}

fn install(root: &Path, tag: &str) -> Result<PathBuf, String> {
    let dir = kit_dir(root, tag);
    let binary = dir.join("bin").join(exe(KIT_BINARY));
    if binary.exists() {
        println!(
            "xtask: using the cached conformance kit at {}",
            binary.display()
        );
        return Ok(binary);
    }
    let mut cmd = crate::cargo();
    cmd.args(["install", "--git", KIT_REPO, "--tag", tag, KIT_PACKAGE])
        .args(["--bin", KIT_BINARY, "--locked", "--root"])
        .arg(&dir);
    crate::run(cmd)?;
    if binary.exists() {
        Ok(binary)
    } else {
        Err(format!(
            "cargo install succeeded but {} is missing",
            binary.display()
        ))
    }
}

pub fn run(root: &Path, graph: &Graph) -> Result<(), String> {
    let tag = pinned_tag(graph).ok_or(
        "the conformance kit is required, but harness-protocol is not pinned to a contracts tag",
    )?;
    let kit = install(root, &tag)?;

    let mut build = crate::cargo();
    build.args(["build", "--locked", "--package", "cli", "--bin", "reqdrive"]);
    crate::run(build)?;
    let harness = Path::new(&graph.target_dir)
        .join("debug")
        .join(exe("reqdrive"));

    let mut cmd = Command::new(&kit);
    cmd.args(["--wall-clock-secs", "30", "--grace-secs", "5", "--"])
        .arg(&harness)
        .args(HARNESS_ARGS);
    println!("xtask: running {cmd:?}");
    let output = cmd
        .output()
        .map_err(|e| format!("could not start {}: {e}", kit.display()))?;
    let stdout = String::from_utf8_lossy(&output.stdout);
    print!("{stdout}");
    eprint!("{}", String::from_utf8_lossy(&output.stderr));
    let verdict = judge(&stdout, output.status.success())?;
    println!("conformance: OK ({verdict}; kit {tag})");
    Ok(())
}
```

- [ ] **Step 4: Run the tests**

Run: `cargo test -p xtask --lib kit::`

Expected: `test result: ok. 4 passed`.

- [ ] **Step 5: Commit**

```bash
git add xtask/src/kit.rs xtask/src/lib.rs
git commit -m "feat(xtask): install, run and judge the conformance kit"
```

### Task 8: The six tiers and the command dispatcher

**Files:**
- Create: `xtask/src/tiers.rs`, `forms/contract.lock.json`
- Modify: `xtask/src/lib.rs`

**Interfaces:**
- Consumes: everything `xtask` has so far.
- Produces:
  - `xtask::tiers::EMPTY: &str = "no tests in this tier yet"`, `pub fn tiers::run(tier: &str, krate: Option<&str>) -> Result<(), String>`
  - `pub fn tiers::unit_args(krate: &str, characterisation: &[String]) -> Vec<String>`: one crate's unit run, its library tests and any `characterisation_*` targets
  - the commands `cargo xtask test <tier> [crate]`, `cargo xtask deps`, `cargo xtask parity`, `cargo xtask lock check`, `cargo xtask lock accept`
  - `forms/contract.lock.json`, with no file locked and `conformance_kit` false.

- [ ] **Step 1: Write the failing tests**

In `xtask/src/lib.rs`, add `pub mod tiers;` at the end of the module list. Create
`xtask/src/tiers.rs` with only its tests:

```rust
#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn an_unknown_tier_is_refused_by_name() {
        let refused = run("smoke", None).unwrap_err();
        assert!(refused.contains("`smoke` is not a tier"));
        for tier in TIERS {
            assert!(refused.contains(tier));
        }
    }

    #[test]
    fn only_the_unit_tier_takes_a_crate() {
        let refused = run("static", Some("engine")).unwrap_err();
        assert!(refused.contains("only the unit tier takes a crate"));
    }

    #[test]
    fn a_unit_run_is_the_library_tests_and_any_characterisation_targets() {
        assert_eq!(
            unit_args("engine", &[]),
            ["test", "--locked", "--package", "engine", "--lib"]
        );
        assert_eq!(
            unit_args("ledger", &["characterisation_old".to_string()]),
            [
                "test",
                "--locked",
                "--package",
                "ledger",
                "--lib",
                "--test",
                "characterisation_old"
            ]
        );
    }
}
```

- [ ] **Step 2: Run them and watch them fail**

Run: `cargo test -p xtask --lib tiers::`

Expected: it does not compile; the errors name the missing functions `run` and `unit_args`.

- [ ] **Step 3: Write the implementation**

Put this above the test module in `xtask/src/tiers.rs`:

```rust
//! The six test tiers, one command each.
//!
//! | Tier | Runs | Needs |
//! |---|---|---|
//! | `static` | format check, lints as errors, dependency direction, registry parity | nothing |
//! | `unit` | each crate's library tests and its `characterisation_*` targets, one crate at a time | nothing |
//! | `contract` | the freeze gate, every contract test target, the conformance kit | nothing |
//! | `integration` | every `*_it` test target | Docker for some |
//! | `e2e` | every `e2e_*` test target | Docker |
//! | `live` | every `live_*` test target | keys and a spend cap |
//!
//! A test inside `src/` is a unit test. A test target under `crates/<crate>/tests/` is placed
//! by its file name and by nothing else: see [`crate::tier_of_test_target`]. A test that needs
//! Docker, a network or a token must therefore be named for `integration`, `e2e` or `live`.

use crate::metadata::Graph;
use crate::{cargo, lock, repo_root, run as run_command, TIERS};

pub const EMPTY: &str = "no tests in this tier yet";

pub fn run(tier: &str, krate: Option<&str>) -> Result<(), String> {
    match (tier, krate) {
        ("static", None) => static_tier(),
        ("unit", krate) => unit(krate),
        ("contract", None) => contract(),
        ("integration" | "e2e" | "live", None) => targets_of(tier).map(|ran| {
            if ran == 0 {
                println!("{tier}: {EMPTY}");
            }
        }),
        (tier, Some(_)) if TIERS.contains(&tier) => Err(format!(
            "only the unit tier takes a crate; `{tier}` runs whole"
        )),
        (other, _) => Err(format!("`{other}` is not a tier; the tiers are {TIERS:?}")),
    }
}

fn static_tier() -> Result<(), String> {
    let mut fmt = cargo();
    fmt.args(["fmt", "--all", "--", "--check"]);
    run_command(fmt)?;

    let mut clippy = cargo();
    clippy.args([
        "clippy",
        "--workspace",
        "--all-targets",
        "--all-features",
        "--locked",
    ]);
    clippy.args(["--", "-D", "warnings"]);
    run_command(clippy)?;

    crate::deps::run()?;
    crate::parity::run()
}

/// The arguments of one crate's unit run: its library tests, and with them any
/// `characterisation_*` test target it has.
pub fn unit_args(krate: &str, characterisation: &[String]) -> Vec<String> {
    let mut args: Vec<String> = ["test", "--locked", "--package", krate, "--lib"]
        .iter()
        .map(|arg| arg.to_string())
        .collect();
    for target in characterisation {
        args.push("--test".into());
        args.push(target.clone());
    }
    args
}

fn unit(krate: Option<&str>) -> Result<(), String> {
    let graph = Graph::load()?;
    let crates: Vec<String> = match krate {
        Some(name) if graph.is_member(name) => vec![name.to_string()],
        Some(name) => {
            return Err(format!(
                "`{name}` is not a crate of this workspace; the crates are {:?}",
                graph.members
            ))
        }
        None => graph.members.clone(),
    };
    let characterisation = lock::test_targets(&repo_root(), "unit");
    for name in &crates {
        let own: Vec<String> = characterisation
            .iter()
            .filter(|(_, krate, _)| krate == name)
            .map(|(_, _, target)| target.clone())
            .collect();
        let mut test = cargo();
        test.args(unit_args(name, &own));
        run_command(test)?;
    }
    println!("unit: OK ({} crate(s), one at a time)", crates.len());
    Ok(())
}

/// Run every test target the naming rule places in `tier`. Returns how many ran.
fn targets_of(tier: &str) -> Result<usize, String> {
    let targets = lock::test_targets(&repo_root(), tier);
    for (_, krate, target) in &targets {
        let mut test = cargo();
        test.args(["test", "--locked", "--package", krate]);
        test.args(["--features", "testkit", "--test", target]);
        run_command(test)?;
    }
    Ok(targets.len())
}

fn contract() -> Result<(), String> {
    let root = repo_root();
    lock::check(&root)?;
    let ran = targets_of("contract")?;
    let kit_required = lock::read(&root)?.conformance_kit;
    if kit_required {
        crate::kit::run(&root, &Graph::load()?)?;
    }
    if ran == 0 && !kit_required {
        println!("contract: {EMPTY}");
    } else {
        println!("contract: OK ({ran} locked test file(s), conformance kit: {kit_required})");
    }
    Ok(())
}
```

Then make `xtask/src/lib.rs` dispatch. Its `main_from` so far only prints the usage; the whole
file now reads as follows (the helpers and tests are unchanged, the module list is complete,
and `main_from` matches on the arguments):

````rust
//! `cargo xtask`: this repository's test runner and its structural gates.
//!
//! ```text
//! cargo xtask test <static|unit|contract|integration|e2e|live> [crate]
//! cargo xtask deps           dependency direction
//! cargo xtask parity         the gate registry agrees with the Forms and with CI
//! cargo xtask lock check     locked contract tests are unchanged
//! cargo xtask lock accept    re-lock them (a deliberate act; its diff is reviewed)
//! ```

pub mod deps;
pub mod kit;
pub mod lock;
pub mod metadata;
pub mod parity;
pub mod tiers;

/// The six test tiers, cheapest first.
pub const TIERS: [&str; 6] = ["static", "unit", "contract", "integration", "e2e", "live"];

use std::path::{Path, PathBuf};
use std::process::{Command, ExitCode};

pub const USAGE: &str = "usage:
  cargo xtask test <static|unit|contract|integration|e2e|live> [crate]
  cargo xtask deps
  cargo xtask parity
  cargo xtask lock <check|accept>";

/// The tier of a test target under `crates/<crate>/tests/`, decided by its file name and by
/// nothing else. `name` is the file name without `.rs`. This is the program's naming rule,
/// the same in the control plane's repository. It is total: every name has a tier, so no
/// test target can be left out of every tier.
///
/// | File name | Tier |
/// |---|---|
/// | `e2e_*.rs` | `e2e` |
/// | `live_*.rs` | `live` |
/// | `*_it.rs` | `integration` |
/// | `characterisation_*.rs` | `unit`: it runs with the crate's own tests |
/// | any other name | `contract` |
///
/// The first row that matches wins.
pub fn tier_of_test_target(name: &str) -> &'static str {
    if name.starts_with("e2e_") {
        "e2e"
    } else if name.starts_with("live_") {
        "live"
    } else if name.ends_with("_it") {
        "integration"
    } else if name.starts_with("characterisation_") {
        "unit"
    } else {
        "contract"
    }
}

/// The repository root: the directory above this crate.
pub fn repo_root() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR"))
        .parent()
        .expect("xtask sits one level below the repository root")
        .to_path_buf()
}

/// A `cargo` command that runs from the repository root.
pub fn cargo() -> Command {
    let mut cmd = Command::new(std::env::var_os("CARGO").unwrap_or_else(|| "cargo".into()));
    cmd.current_dir(repo_root());
    cmd
}

/// Echo a command, run it, and turn a failure into a one-line reason.
pub fn run(mut cmd: Command) -> Result<(), String> {
    let shown = format!("{cmd:?}");
    println!("xtask: running {shown}");
    let status = cmd
        .status()
        .map_err(|e| format!("could not start {shown}: {e}"))?;
    if status.success() {
        Ok(())
    } else {
        Err(format!("{shown} ended with {status}"))
    }
}

/// A repository-relative path with forward slashes, whatever the platform.
pub fn relative(root: &Path, path: &Path) -> String {
    path.strip_prefix(root)
        .unwrap_or(path)
        .to_string_lossy()
        .replace('\\', "/")
}

/// Every file under `dir`, recursively. A missing directory is an empty list.
pub fn files_under(dir: &Path) -> Vec<PathBuf> {
    let mut found = Vec::new();
    let mut pending = vec![dir.to_path_buf()];
    while let Some(next) = pending.pop() {
        let Ok(entries) = std::fs::read_dir(&next) else {
            continue;
        };
        for entry in entries.flatten() {
            let path = entry.path();
            if path.is_dir() {
                pending.push(path);
            } else {
                found.push(path);
            }
        }
    }
    found.sort();
    found
}

/// Join a gate's problems into one failure, or pass with a one-line summary.
pub fn verdict(gate: &str, ok: String, problems: Vec<String>) -> Result<(), String> {
    if problems.is_empty() {
        println!("{gate}: OK ({ok})");
        return Ok(());
    }
    let mut message = format!("{gate}: {} problem(s)", problems.len());
    for problem in &problems {
        message.push_str("\n  - ");
        message.push_str(problem);
    }
    Err(message)
}

pub fn main_from(args: Vec<String>) -> ExitCode {
    let args: Vec<&str> = args.iter().map(String::as_str).collect();
    let outcome = match args.as_slice() {
        ["test", tier] => tiers::run(tier, None),
        ["test", tier, krate] => tiers::run(tier, Some(krate)),
        ["deps"] => deps::run(),
        ["parity"] => parity::run(),
        ["lock", "check"] => lock::check(&repo_root()),
        ["lock", "accept"] => lock::accept(&repo_root()),
        _ => {
            eprintln!("{USAGE}");
            return ExitCode::from(2);
        }
    };
    match outcome {
        Ok(()) => ExitCode::SUCCESS,
        Err(message) => {
            eprintln!("xtask: {message}");
            ExitCode::FAILURE
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn an_unknown_command_is_a_usage_error() {
        assert_eq!(main_from(vec!["frobnicate".into()]), ExitCode::from(2));
        assert_eq!(main_from(vec![]), ExitCode::from(2));
    }

    #[test]
    fn relative_paths_use_forward_slashes() {
        let root = Path::new("repo");
        let path = root
            .join("crates")
            .join("engine")
            .join("src")
            .join("lib.rs");
        assert_eq!(relative(root, &path), "crates/engine/src/lib.rs");
    }

    #[test]
    fn a_gate_with_problems_fails_and_lists_each_one() {
        assert!(verdict("deps", "3 crates".into(), vec![]).is_ok());
        let failed = verdict("deps", String::new(), vec!["a".into(), "b".into()]).unwrap_err();
        assert!(
            failed.contains("2 problem(s)") && failed.contains("- a") && failed.contains("- b")
        );
    }

    #[test]
    fn a_test_target_is_sorted_into_a_tier_by_its_file_name_alone() {
        assert_eq!(tier_of_test_target("e2e_one_unit"), "e2e");
        assert_eq!(tier_of_test_target("live_models"), "live");
        assert_eq!(tier_of_test_target("docker_it"), "integration");
        assert_eq!(tier_of_test_target("integration_docker_it"), "integration");
        assert_eq!(tier_of_test_target("characterisation_store"), "unit");
        assert_eq!(tier_of_test_target("contract_speaker"), "contract");
        assert_eq!(tier_of_test_target("vectors"), "contract");
        // A prefix alone does not make an integration test: the suffix does.
        assert_eq!(tier_of_test_target("integration_docker"), "contract");
        // The first row that matches wins.
        assert_eq!(tier_of_test_target("e2e_full_it"), "e2e");
        assert_eq!(
            tier_of_test_target("characterisation_store_it"),
            "integration"
        );
        for name in ["", "it", "_it", "x"] {
            assert!(
                TIERS.contains(&tier_of_test_target(name)),
                "{name:?} has a tier"
            );
        }
    }
}
````

- [ ] **Step 4: Run the tests**

Run: `cargo test -p xtask --lib`

Expected: `test result: ok. 40 passed`.

- [ ] **Step 5: Create the lock, and run the tiers that can already run**

```bash
cargo xtask lock accept
cat forms/contract.lock.json
cargo xtask lock check
cargo xtask deps
cargo xtask test unit
cargo xtask test contract
cargo xtask test integration; cargo xtask test e2e; cargo xtask test live
cargo xtask test unit nosuch; echo "exit $?"
```

Expected, in order: `lock: regenerated with 0 contract tests`; a JSON object with
`"conformance_kit": false` and `"files": []`; `lock: OK (0 locked contract tests unchanged)`;
`deps: OK (11 crates, 31 source files)`; `unit: OK (11 crate(s), one at a time)`;
`contract: no tests in this tier yet`; three `no tests in this tier yet` lines; a message that
`nosuch` is not a crate of this workspace, and `exit 1`.

`cargo xtask parity` and `cargo xtask test static` cannot pass yet: they read the registry and
the CI workflow, which Task 9 creates.

- [ ] **Step 6: Commit**

```bash
cargo fmt --all
git add xtask forms/contract.lock.json
git commit -m "feat(xtask): six test tiers and the command dispatcher"
```

### Task 9: CI, the gate registry, and the first run of every gate

**Files:**
- Create: `.github/workflows/ci.yml`, `forms/registry.md`

**Interfaces:**
- Consumes: `cargo xtask test static | unit | contract`.
- Produces:
  - CI jobs `static`, `unit (<crate>, <os>)` for eleven crates on two systems, `contract (<os>)`
    on two systems, and `all checks`, which is green only when every other job is;
  - `forms/registry.md` with the four repository-wide gates.

- [ ] **Step 1: Write the registry**

Create `forms/registry.md`:

```markdown
# Gate registry

One row per gate, for the whole repository. `cargo xtask parity` reads this table and fails when
it disagrees with a Form or with what CI runs. The format is in [`docs/forms.md`](../docs/forms.md).

| Gate | Form | Mechanism | Location | Command | Tier | State |
|---|---|---|---|---|---|---|
| repo.G1 | - | dependency direction, from `cargo metadata` and a source scan | `xtask/src/deps.rs` | `cargo xtask deps` | static | live |
| repo.G2 | - | registry parity | `xtask/src/parity.rs` | `cargo xtask parity` | static | live |
| repo.G3 | - | format check, and lints as errors | `Cargo.toml` | `cargo xtask test static` | static | live |
| repo.G4 | - | freeze gate over the locked contract tests | `forms/contract.lock.json` | `cargo xtask lock check` | contract | live |
```

- [ ] **Step 2: Run parity and watch it fail**

Run: `cargo xtask parity`

Expected: `xtask: .github/workflows/ci.yml: ` followed by the system's "not found" message, and
exit 1. Parity reads the workflow to learn what CI runs; there is none yet.

- [ ] **Step 3: Write the workflow**

Create `.github/workflows/ci.yml`:

```yaml
name: CI

# Three tiers run here, one command each: static, unit (one job per crate, on Linux and on
# Windows) and contract. The integration, e2e and live tiers exist in `cargo xtask test` and
# are not run here until they hold tests. `cargo xtask parity` reads this file: the unit
# matrix must list exactly the workspace's crates, and a gate registered as live must name a
# tier that appears below.

on:
  push:
    branches: [main, "factory/**"]
  pull_request:

concurrency:
  group: ci-${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: true

env:
  CARGO_TERM_COLOR: always

defaults:
  run:
    shell: bash

jobs:
  static:
    name: static
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Install the pinned toolchain
        run: rustup toolchain install "$(sed -n 's/^channel = "\(.*\)"/\1/p' rust-toolchain.toml)" --profile minimal --component rustfmt --component clippy
      - uses: Swatinem/rust-cache@v2
      - name: Format, lints, dependency direction, registry parity
        run: cargo xtask test static

  unit:
    name: unit (${{ matrix.crate }}, ${{ matrix.os }})
    runs-on: ${{ matrix.os }}
    strategy:
      fail-fast: false
      matrix:
        os: [ubuntu-latest, windows-latest]
        crate: [engine, workspace, runtime, oracle, map, controls, payload, ledger, speaker, cli, xtask]
    steps:
      - uses: actions/checkout@v4
      - name: Install the pinned toolchain
        run: rustup toolchain install "$(sed -n 's/^channel = "\(.*\)"/\1/p' rust-toolchain.toml)" --profile minimal
      - uses: Swatinem/rust-cache@v2
      - name: Library tests of one crate, alone
        run: cargo xtask test unit ${{ matrix.crate }}

  contract:
    name: contract (${{ matrix.os }})
    runs-on: ${{ matrix.os }}
    strategy:
      fail-fast: false
      matrix:
        os: [ubuntu-latest, windows-latest]
    steps:
      - uses: actions/checkout@v4
      - name: Install the pinned toolchain
        run: rustup toolchain install "$(sed -n 's/^channel = "\(.*\)"/\1/p' rust-toolchain.toml)" --profile minimal
      - uses: Swatinem/rust-cache@v2
      - name: Cache the conformance kit
        uses: actions/cache@v4
        with:
          path: .kit
          key: kit-${{ runner.os }}-${{ hashFiles('Cargo.lock') }}
      - name: Freeze gate, locked contract tests, conformance kit
        run: cargo xtask test contract

  # One check to require in branch protection: green only when every job above is green.
  all:
    name: all checks
    if: always()
    needs: [static, unit, contract]
    runs-on: ubuntu-latest
    steps:
      - name: Every tier passed
        run: |
          results='${{ join(needs.*.result, ' ') }}'
          echo "results: $results"
          for result in $results; do
            [ "$result" = "success" ] || exit 1
          done
```

- [ ] **Step 4: Run the static tier**

Run: `cargo xtask test static`

Expected: the format check and clippy run without output of their own, then
`deps: OK (11 crates, 31 source files)` and `parity: OK (4 gates, 0 Forms)`; exit 0.

- [ ] **Step 5: Prove parity reads the workflow**

Temporarily remove `xtask` from the `crate:` list in `.github/workflows/ci.yml`, then:

Run: `cargo xtask parity`

Expected: `xtask: parity: 1 problem(s)` and `- xtask: missing from CI's unit matrix`; exit 1.
Put `xtask` back and run it again: `parity: OK (4 gates, 0 Forms)`.

- [ ] **Step 6: Commit**

```bash
git add .github/workflows/ci.yml forms/registry.md
git commit -m "ci: static, per-crate unit and contract tiers; register the repository gates"
```

### Task 10: The documents for the new state

**Files:**
- Create: `README.md`, `CLAUDE.md`, `docs/STATUS.md`, `docs/ROADMAP.md`

**Interfaces:**
- Consumes: nothing.
- Produces: the repository's entry points. The old ones are in `archive/bash-v0.3/`.

The README describes milestone 0 as it will reach `main`: the walking skeleton lands in the same
integration branch, from lane RD-SKEL.

- [ ] **Step 1: Write `README.md`**

````markdown
# reqdrive

A software factory harness. A signed spec goes in; a verified change, ready to merge, comes out.

`reqdrive` runs one unit of work as one process. A control plane starts it, hands it a work
order, and talks to it over stdin and stdout in JSON-RPC: the harness protocol, version 0.2. A
unit passes through seven stages:

| Stage | What happens |
|---|---|
| provision | A workspace is made for the unit |
| red | Tests are written from the spec's criteria, then frozen |
| plan | The work is cut into steps |
| green | The steps are built, one fresh agent context each |
| check | The host runs every check itself |
| review | A separate reviewer judges the change against the spec |
| deliver | The change and its evidence are handed back |

The tests are frozen before a plan exists. The host picks every next step and the agent only
carries it out. What an agent runs for itself is feedback for the agent and is never evidence.
The control plane re-checks everything `reqdrive` reports before it calls a unit done.

## Where this is

The harness is being rebuilt in Rust. What exists today is **milestone 0**: the workspace, the
test tiers, the gates, and a walking skeleton. `reqdrive harness --fake` drives a scripted unit
through all seven stages with no agent, no container and no network, and passes the control
plane's conformance kit. Nothing here runs a real model yet.

The earlier Bash implementation, v0.3, is kept whole under
[`archive/bash-v0.3/`](archive/bash-v0.3/) as the reference for behaviour. It is not maintained
and nothing in the Rust workspace depends on it.

## Layout

| Path | Holds |
|---|---|
| `crates/engine` | The stage machine. Pure: it decides the next action and does no I/O |
| `crates/workspace` | Containers, behind one seam. A fake today |
| `crates/runtime` | The worker-runtime contract and its adapters. A scripted fake today |
| `crates/oracle`, `map`, `controls`, `payload`, `ledger` | Empty until milestone 1 and 2 build them |
| `crates/speaker` | The harness protocol over stdin and stdout |
| `crates/cli` | The `reqdrive` binary. Wiring only |
| `xtask` | The test runner and the structural gates |
| `forms/` | One Form per load-bearing crate, the gate registry, and the contract-test lock |
| `docs/` | Formats, status, roadmap and plans |
| `archive/bash-v0.3/` | The Bash implementation, as it was |

## Build and test

You need Rust (the version in `rust-toolchain.toml`; `rustup` installs it on first use) and git.

```bash
cargo build
cargo xtask test static       # format, lints as errors, dependency direction, registry parity
cargo xtask test unit         # every crate's library tests, one crate at a time
cargo xtask test unit engine  # one crate
cargo xtask test contract     # locked contract tests and the conformance kit
```

`integration`, `e2e` and `live` are tiers too; each says "no tests in this tier yet" until it
has some. No tier below `live` needs a token or spends anything, and `static`, `unit` and
`contract` need no Docker.

## Try the skeleton

```bash
cargo build
{ printf '%s\n' \
  '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocol_version":"0.2"}}' \
  '{"jsonrpc":"2.0","id":2,"method":"unit/start","params":{"unit_id":"demo","work_item":{"kind":"issue","ref":"example/repo#1"},"tier":"t1","task":"demo","repo":{"url":"https://example.invalid/r.git","slug":"example/repo","base_branch":"main"},"branch":"agent/demo","test_cmd":"true","caps":{"usd":1.0,"wall_clock_secs":60,"min_review_rounds":1}}}'; \
  sleep 1; } | target/debug/reqdrive harness --fake
```

Each line it prints is one protocol message; the last is `unit/result`. The `sleep` keeps stdin
open while the unit runs: a harness whose stdin closes takes that as "shut down" and stops
without a result.

## Documents

- [`docs/forms.md`](docs/forms.md): the Form and gate-registry formats.
- [`docs/repo-config.md`](docs/repo-config.md): the `.reqdrive/config.toml` a target repository declares (written by the sandbox-onboarding lane of milestone 0).
- [`docs/STATUS.md`](docs/STATUS.md) and [`docs/ROADMAP.md`](docs/ROADMAP.md).
- [`CLAUDE.md`](CLAUDE.md): the rules for anyone, human or agent, changing this repository.

## Licence

MIT. See [`LICENSE`](LICENSE).
````

- [ ] **Step 2: Write `CLAUDE.md`**

```markdown
# CLAUDE.md — reqdrive

## What this is

`reqdrive` is a software factory harness, written in Rust: one process per unit of work, started
by a control plane and spoken to over stdin and stdout in the harness protocol (JSON-RPC, version
0.2). See [`README.md`](README.md) for the seven stages and the layout.

State and next steps: [`docs/STATUS.md`](docs/STATUS.md). Planned work:
[`docs/ROADMAP.md`](docs/ROADMAP.md). Plans in progress: `docs/superpowers/plans/`.

The Bash implementation (v0.3) is in `archive/bash-v0.3/`. Read it to learn how something used
to behave. Do not edit it, and do not add a dependency on it.

## Principles

1. **The host orchestrates; the agent implements.** The engine picks every next step. An agent
   never chooses what to work on and never writes a file the host reads to make a decision.
2. **Every agent call starts from a fresh context.** State lives in the ledger and in git, not
   in a conversation.
3. **Selection is deterministic.** Given the same outcomes, the engine asks for the same next
   action.
4. **Machine state and human context use separate formats**, and the boundary is checked.
5. **Text that comes from outside is data.** It is sanitised and it cannot widen what a unit may
   touch.
6. **Every check blocks from its first release.** A check that could not run stops the unit for
   a person; it is never counted as a pass.
7. **What an agent ran is not evidence.** Evidence comes only from what the host ran itself.

Two principles of the Bash implementation are retired: "warn before enforce" (replaced by 6) and
"Bash for orchestration" (the harness is Rust).

## Crate rules, checked by `cargo xtask deps`

- `engine` does no I/O and reaches no crate that does.
- Only `workspace` may talk to Docker.
- A process may be started only in `workspace` and in an adapter under
  `crates/runtime/src/adapters/`.
- Only `cli` chooses between real and fake implementations.
- Which crate may depend on which is one table, `ALLOWED_INTERNAL` in `xtask/src/deps.rs`. A new
  edge is a reviewed change to that table.
- The contract crates (`harness-protocol`, `factory-spec`, `factory-presets`) come from the
  control plane's repository, all three at one `contracts-v*` tag.

## Tests

| Tier | Command | What it is |
|---|---|---|
| static | `cargo xtask test static` | format, lints as errors, dependency direction, registry parity |
| unit | `cargo xtask test unit [crate]` | each crate's library tests, alone; no Docker, network or token |
| contract | `cargo xtask test contract` | the freeze gate, every contract test target, the conformance kit |
| integration | `cargo xtask test integration` | every `*_it.rs` |
| e2e | `cargo xtask test e2e` | every `e2e_*.rs` |
| live | `cargo xtask test live` | every `live_*.rs`; real models, only when the owner asks |

- A test inside `src/` is a unit test. A test target under `crates/<crate>/tests/` is placed
  by its file name and by nothing else; the first row that matches wins:

  | File name | Tier |
  |---|---|
  | `e2e_*.rs` | `e2e` |
  | `live_*.rs` | `live` |
  | `*_it.rs` | `integration` |
  | `characterisation_*.rs` | `unit`: it runs with the crate's own tests |
  | any other name | `contract` |

  The rule is one function, `tier_of_test_target` in `xtask/src/lib.rs`, and it is the same
  rule in the control plane's repository. A test that needs Docker, a network or a token must
  be named for `integration`, `e2e` or `live`.
- Write the failing test first, watch it fail, then write the code.
- Every crate has a `testkit` feature with builders for its own types. Use another crate's
  testkit as a dev-dependency; never copy its fixtures.
- **Contract tests are locked.** `forms/contract.lock.json` holds the hash of every test
  target in the contract tier; name one `contract_<name>.rs`. Changing one, or adding one,
  fails `cargo xtask lock check` until someone runs `cargo xtask lock accept` and the owner
  reviews the lock's diff. Do not run `accept` to make a red build green; say what changed
  and why.

## Forms

A load-bearing crate has a Form, `forms/<crate>.md`: its purpose, its whole public interface,
its invariants, what it hides, and the gates that guard it. The format is
[`docs/forms.md`](docs/forms.md). The owner approves Forms. An agent may propose a change to
one and may not make it: an additive change needs the reviewer's approval, a breaking one stops
for the owner. `cargo xtask parity` fails when the registry, a Form and CI disagree.

## Working here

- Branch from the integration branch your plan names. Open a pull request; never push to `main`.
- Commit messages and pull-request bodies carry no `Co-Authored-By` line and no "Generated
  with" footer.
- A lane changes only the files its plan says it owns. The root `Cargo.toml`, `Cargo.lock`,
  `.github/`, `xtask/`, `forms/registry.md` and this file belong to the coordinating lane.
- New external dependency: ask the coordinating lane. Do not commit a lockfile change you were
  not asked to make.
- Create and edit files with your editor or file tool, not by typing a here-document into a
  command line: quoting differs between PowerShell and Git Bash and mangles content.
- This repository is public. Its design lives in a private repository; never paste from it.
```

- [ ] **Step 3: Write `docs/STATUS.md`**

```markdown
# reqdrive — Status

## State summary

**What this is now.** A Rust workspace, at milestone 0 of the rebuild into a software factory
harness. The Bash implementation (v0.3) is archived, whole, under `archive/bash-v0.3/`; its last
status file is `archive/bash-v0.3/docs/STATUS.md`.

**Readiness.** Scaffold only. The workspace builds; ten crates exist as empty skeletons with a
`testkit` feature each; `cargo xtask` runs six test tiers and three structural gates (dependency
direction, registry parity, the contract-test lock); CI runs `static`, a per-crate `unit` matrix
on Linux and Windows, and `contract`. The `reqdrive` binary has no command yet.

**Open pull requests.** None recorded here yet.

**Known gaps.**
- No Form exists yet, so the registry holds only repository-wide gates.
- The contract tier holds no test and does not run the conformance kit until the walking
  skeleton lands (`forms/contract.lock.json`, `conformance_kit`).
- The archived Bash suite is not run in CI. It passed from its new location when it was moved.

**Next steps.** See [`ROADMAP.md`](ROADMAP.md). Now: the Forms for milestone 1's crates, then the
walking skeleton (`reqdrive harness --fake`).

## Session log

### 2026-10-04 — milestone 0 scaffold

Archived the Bash tree to `archive/bash-v0.3/`. Created the cargo workspace, the skeleton crates,
`xtask` (tiers, `deps`, `parity`, `lock`), the gate registry, and CI. Rewrote `README.md` and
`CLAUDE.md` for the new state.
```

- [ ] **Step 4: Write `docs/ROADMAP.md`**

```markdown
# reqdrive — Roadmap

The one list of intended work for this repository. An entry gets a GitHub issue when it is
scoped and about to be worked; the issue number goes on the entry.

## Milestones

| Milestone | Delivers here | Done when |
|---|---|---|
| **M0 Foundations** | The Bash tree archived; the Rust workspace, test tiers, gates and CI; Forms for milestone 1's crates; a walking skeleton, `reqdrive harness --fake` | The control plane's conformance kit drives the skeleton through all seven stages on fakes |
| **M1 One real unit** | `engine`, `workspace` (Docker), `runtime` with one real adapter, `oracle` (visible tests, per-test evidence), `payload`, `controls` (scope, protected paths), a single-round review, `ledger`, `speaker`, `cli`, the container images | One signed spec in a sandbox repository becomes a change the control plane verifies |
| **M2 Full envelope** | Hidden holdout tests; the repository map and its gauge; the remaining controls; the review loop and escalation; every stop reason, with resume; spec drafting | A gated unit passes its oracle gate on each supported stack; every control is seen to block once in a real run |
| **M3 Parallel and pluggable** | A second runtime adapter against a local model; capability probes; profiles; the adoption run | A build step runs on a local model and its escalation is observed |
| **M4 Hardening** | Documentation a cold reader can work from; coverage and mutation floors on the deciding crates | A cold-reader test passes; the end-to-end suite is green on Linux and Windows |

Plans: `docs/superpowers/plans/`. Milestone 0 is
[`2026-10-04-factory-m0-foundations.md`](superpowers/plans/2026-10-04-factory-m0-foundations.md).

## Deferred

- Running the archived Bash suite in CI. It is frozen and unmaintained; revisit only if the
  archive is ever edited.
- A third stack preset, network egress filtering for agent containers, and push delivery: none
  is in version 1.
- The Bash implementation's own open items stay where they were recorded:
  `archive/bash-v0.3/CLAUDE.md` and `archive/bash-v0.3/tests/FINDINGS.md`.
```

- [ ] **Step 5: Check the links and the gates**

```bash
for f in docs/forms.md docs/STATUS.md docs/ROADMAP.md CLAUDE.md LICENSE archive/bash-v0.3/CLAUDE.md archive/bash-v0.3/docs/STATUS.md archive/bash-v0.3/tests/FINDINGS.md; do test -e "$f" && echo "ok $f" || echo "MISSING $f"; done
cargo xtask test static
```

Expected: eight `ok` lines and no `MISSING`; the static tier passes as in Task 9.
`docs/repo-config.md`, which the README also links, is written by lane SANDBOX.

- [ ] **Step 6: Commit**

```bash
git add README.md CLAUDE.md docs/STATUS.md docs/ROADMAP.md
git commit -m "docs: README, CLAUDE.md, status and roadmap for the Rust rebuild"
```

### Task 11: Verify, push and open the pull request

**Files:** none.

**Interfaces:**
- Consumes: the lane's "Verify" table.
- Produces: a pull request from `feat/m0-scaffold` into `factory/m0`.

- [ ] **Step 1: Run the lane's Verify table**

Run every command in the "Verify" table at the top of this lane except the last, and keep the
output for the pull-request body.

- [ ] **Step 2: Push and open the pull request**

Write the body to a file outside the repository (for example
`/d/MajorProjects/.swarm-wt/m0-rd-coord-pr.md`) with this content, filling in the outputs:

```markdown
## What changed

- The Bash implementation (v0.3) moved, unchanged, to `archive/bash-v0.3/` (103 files, renames only).
- A cargo workspace: nine empty library crates with a `testkit` feature, the `cli` crate, `xtask`.
- `cargo xtask`: six test tiers; `deps` (dependency direction), `parity` (registry parity) and
  `lock` (freeze gate over contract tests); the conformance-kit runner, not yet switched on.
- CI: `static`, a per-crate `unit` matrix on Linux and Windows, `contract`, and `all checks`.
- `forms/registry.md`, `forms/contract.lock.json` (empty), `docs/forms.md`.
- New `README.md`, `CLAUDE.md`, `docs/STATUS.md`, `docs/ROADMAP.md`.

## How it was verified

<paste the output of each Verify command>

The archived Bash suite, run from its new location: <paste the two result lines>.

## Lock

`forms/contract.lock.json` is new and locks no file.

## Requests and notes

<anything you needed outside your ownership, or "none">
```

```bash
git push -u origin feat/m0-scaffold
gh pr create --base factory/m0 --head feat/m0-scaffold \
  --title "M0 scaffold: archive the Bash tree, cargo workspace, xtask, CI" \
  --body-file /d/MajorProjects/.swarm-wt/m0-rd-coord-pr.md
```

- [ ] **Step 3: Watch CI**

Run: `gh pr checks --watch`

Expected: `static`, twenty-two `unit` jobs, two `contract` jobs and `all checks` pass. This is
the first time the workflow runs anywhere: if a job fails for a reason in the workflow file
itself, fix the workflow, commit, push, and say so in the report. Do not merge.

---

## Lane RD-FORMS

**Owns:** `forms/engine.md`, `forms/workspace.md`, `forms/runtime.md`, `forms/oracle.md`,
`forms/payload.md`, `forms/controls.md`, `forms/ledger.md`, `forms/speaker.md`, and the rows of
`forms/registry.md` whose gate id begins with one of those crate names. It does not touch the
`repo.*` rows, and it writes no code.

**Reads:** this plan; `docs/forms.md`; the milestone 1 harness plan,
`docs/superpowers/plans/2026-10-04-factory-m1-harness.md`; the design (private; read it, never
paste from it).

**Worktree and branch:** worktree `D:\MajorProjects\.swarm-wt\m0-rd-forms`, branch
`feat/m0-forms` cut from `origin/factory/m0`, pull request against `factory/m0`.

**Needs:** RD-COORD merged into `factory/m0` (owner action A2); the milestone 1 harness plan on
`main` (A3).

**Blocks:** owner action A4 (approving the Forms), and through it RD-SKEL and milestone 1.

**Verify:**

| Command | Expected |
|---|---|
| `ls forms/*.md \| wc -l` | `9` (eight Forms and the registry) |
| `grep -L '^- status: draft$' forms/*.md` | `forms/registry.md` only: every Form is a draft until the owner freezes it |
| `cargo xtask parity` | `parity: OK (<n> gates, 8 Forms)`, where `<n>` is 4 plus the gates you registered |
| `grep -c '\| planned \|$' forms/registry.md` | the number of gates you registered: every one is `planned` |
| `cargo xtask test static` | exit 0 |
| `git diff --stat origin/factory/m0 -- . ':!forms'` | empty: nothing outside `forms/` changed |

**What this lane is.** Milestone 1 builds eight crates in parallel, one lane each. Each lane
needs a frozen interface to build against. The milestone 1 plan states those interfaces as
`Produces` and `Consumes` blocks, task by task. This lane turns each crate's blocks into one
Form, in the format of `docs/forms.md`, for the owner to approve. It is transcription and
bookkeeping. It decides nothing: where the milestone 1 plan is silent or unclear, the Form says
so and the pull request asks.

### Task 1: The worked example, `forms/speaker.md`

`speaker` is the one crate whose interface this plan itself defines (RD-SKEL builds it), so its
Form can be written in full here. It is also the example to imitate for the other seven.

**Files:**
- Create: `forms/speaker.md`
- Modify: `forms/registry.md` (five rows added)

**Interfaces:**
- Consumes: the format in `docs/forms.md`; the `speaker` interface in lane RD-SKEL, Tasks 5 and 6.
- Produces: the Form `forms/speaker.md` and the registry rows `speaker.G1` to `speaker.G5`, all `planned`.

- [ ] **Step 1: Create the worktree**

```bash
git -C /d/MajorProjects/INFRASTRUCTURE/reqdrive fetch origin
git -C /d/MajorProjects/INFRASTRUCTURE/reqdrive worktree add --no-track -b feat/m0-forms \
  /d/MajorProjects/.swarm-wt/m0-rd-forms origin/factory/m0
cd /d/MajorProjects/.swarm-wt/m0-rd-forms
test -f docs/forms.md && test -f forms/registry.md && cargo xtask parity
```

Expected: `parity: OK (4 gates, 0 Forms)`.

- [ ] **Step 2: Write the Form**

Create `forms/speaker.md`:

````markdown
# Form: speaker

- status: draft
- owner: adbarc92
- level: E0
- last-drill: never
- interface-files:
  - crates/speaker/src/lib.rs
  - crates/speaker/src/transport.rs
  - crates/speaker/src/unit.rs
  - crates/speaker/src/testkit.rs

## Purpose

`speaker` is the harness's side of the harness protocol: JSON-RPC 2.0, one message per line, on
the process's stdin and stdout. It performs the handshake, sends a unit's events and its one
result, asks for gates, and notices when the control plane halts the unit, abandons it, or goes
away. Without it every other crate would have to know the wire. With it, none does: the rest of
the harness calls typed functions and gets back either success or the reason the unit must stop.

## Interface

Wire types (`RpcMessage`, `WorkOrder`, `UnitEvent`, and so on) are `harness-protocol`'s, at the
tag this workspace pins.

```rust
// The seam under the protocol: one message out, one message in.
pub trait Transport {
    fn send(&mut self, message: &RpcMessage) -> Result<(), Closed>;
    /// None waits for a message or for the input to close; Some(wait) gives up after `wait`.
    fn recv(&mut self, wait: Option<Duration>) -> Recv;
}
pub struct Closed;
pub enum Recv { Message(RpcMessage), Malformed(String), Idle, Closed }

pub struct StdioTransport<W: Write> { /* private */ }
impl StdioTransport<Stdout> { pub fn stdio() -> Self; }
impl<W: Write> StdioTransport<W> {
    pub fn over<R: Read + Send + 'static>(input: R, out: W) -> Self;
}

// The handshake: answer `initialize`, then acknowledge `unit/start`.
pub struct Identity { pub info: HarnessInfo, pub capabilities: Capabilities }
pub enum OpenError { Closed, Interrupted, VersionRefused { offered: Vec<String> }, Protocol(String) }
pub fn open<T: Transport>(transport: T, identity: &Identity)
    -> Result<(Unit<T>, WorkOrder), OpenError>;

// One unit, from the `unit/start` acknowledgement to the result.
pub enum Stopped { Halt, Abandon, Closed }
pub struct Unit<T: Transport> { /* private */ }
impl<T: Transport> Unit<T> {
    pub fn event(&mut self, event: &UnitEvent) -> Result<(), Stopped>;
    pub fn observe(&mut self, observation: Observation) -> Result<(), Stopped>;
    pub fn stage(&mut self, stage: Stage, status: StageStatus, detail: Option<String>)
        -> Result<(), Stopped>;
    /// Give the control plane its turn: wait up to `pause`, then answer what has arrived.
    pub fn checkpoint(&mut self, pause: Duration) -> Result<(), Stopped>;
    /// Send `gate/request` and wait for its answer. Ok(true) means approved.
    pub fn gate(&mut self, request: &GateRequest) -> Result<bool, Stopped>;
    /// Send the one `unit/result`.
    pub fn finish(self, result: &UnitResult) -> Result<(), Stopped>;
}
```

Behind the `testkit` feature: `testkit::ScriptedPeer` (a scripted control plane that implements
`Transport`), and the helpers `initialize`, `start`, `order_v01`, `stage_started` and
`gate_requested`.

Errors. `open` fails with `OpenError`; only `VersionRefused` and `Protocol` are faults. Every
`Unit` method fails only with `Stopped`, which is never a fault: it is the control plane's
decision, or its absence. Nothing in this crate panics on input from the wire.

## Invariants

I1. The handshake answers `initialize` with the protocol version this crate is built against and the identity it was given. An offer that holds no version with that major and minor is answered with error -32001, and nothing else is written.
I2. A work order in the 0.1 shape is accepted: no field that protocol 0.2 added is required. A work order that does not parse is refused with error -32602.
I3. Before a unit starts, a closed input or an interrupt ends the handshake without a unit, and a first request other than `initialize` is refused with error -32601.
I4. While a unit is live, `unit/halt` and `unit/abandon` are answered with an empty result, including while a gate is pending. After that answer nothing more is written for the unit, and every later call returns the same `Stopped`.
I5. A gate is approved only by a response to its own request id that says `approved: true` and carries no edited files. Any other answer to it is a rejection.
I6. Once the input closes, every later call returns `Stopped::Closed` and writes nothing.
I7. A request this harness does not know is answered with error -32601, and `unit/resume` is acknowledged; neither stops the unit. Notifications and stray responses are ignored.
I8. Nothing can be sent after `unit/result`: `finish` consumes the unit.
I9. The input is drained continuously, on its own thread and without bound, so the control plane can always complete a write to this process whatever the state of this process's output.
I10. `speaker` starts no process and depends on no other crate of this workspace.
I11. A line from the control plane that cannot be read, because it is not UTF-8 or is longer than the protocol's line limit, ends the input for good: nothing after it is read, the reason is written to stderr, and the unit stops as it does for a closed input, with no result.

## Hidden decisions

- How a message becomes a line, and how lines are read back.
- That the input is read on a thread into a queue, and what kind of queue it is.
- The ids this side gives its own requests.
- What happens to an inbound line that is readable text but not a message. It is dropped; no
  caller sees it.
- How an unreadable line is told apart from a closed input. Callers see the same `Stopped`;
  only stderr says which it was.
- What `checkpoint` does with the rest of its pause once a message has arrived.

## Gates

| Gate | Guards | Mechanism | Location | Blocks |
|---|---|---|---|---|
| G1 | I1, I2, I3, I4, I5, I6, I7 | locked contract tests | `crates/speaker/tests/contract_speaker.rs` | merge |
| G2 | I8 | type system: `finish` takes the unit by value | `crates/speaker/src/unit.rs` | build |
| G3 | I4, I6, I9, I11 | locked tests of the real process over real pipes | `crates/cli/tests/contract_harness_process.rs` | merge |
| G4 | I1, I4, I8 | the control plane's conformance kit | `xtask/src/kit.rs` | merge |
| G5 | I10 | dependency direction | `xtask/src/deps.rs` | merge |

## Unenforced

None.

## Regeneration notes

- Rebuild against `harness-protocol` at the tag in the root `Cargo.toml`; use its `read_message`,
  `write_message` and `negotiate`, and do not re-implement them.
- The implementation is correct when `cargo xtask test contract` passes without changing a
  locked file: `crates/speaker/tests/contract_speaker.rs` drives the interface through
  `testkit::ScriptedPeer`, `crates/cli/tests/contract_harness_process.rs` drives the real binary,
  and the conformance kit drives it from the control plane's side.
- `testkit::ScriptedPeer` is part of the interface. It never waits: with nothing queued, a
  bounded `recv` is `Idle` and an unbounded one is `Closed`.
- Forbidden: a dependency on another crate of this workspace; starting a process; async
  runtimes; reading the clock (a pause is the transport's to wait out).
````

- [ ] **Step 3: Run parity and watch it fail**

Run: `cargo xtask parity`

Expected: `xtask: parity: 5 problem(s)`, one line for each of `speaker.G1` to `speaker.G5`:
`declared in the Form, not registered`.

- [ ] **Step 4: Register its gates**

Append these five rows to the table in `forms/registry.md`:

```markdown
| speaker.G1 | forms/speaker.md | locked contract tests | `crates/speaker/tests/contract_speaker.rs` | `cargo xtask test contract` | contract | planned |
| speaker.G2 | forms/speaker.md | type system: `finish` takes the unit by value | `crates/speaker/src/unit.rs` | `cargo xtask test unit speaker` | unit | planned |
| speaker.G3 | forms/speaker.md | locked tests of the real process over real pipes | `crates/cli/tests/contract_harness_process.rs` | `cargo xtask test contract` | contract | planned |
| speaker.G4 | forms/speaker.md | the control plane's conformance kit | `xtask/src/kit.rs` | `cargo xtask test contract` | contract | planned |
| speaker.G5 | forms/speaker.md | dependency direction | `xtask/src/deps.rs` | `cargo xtask deps` | static | planned |
```

- [ ] **Step 5: Run parity**

Run: `cargo xtask parity`

Expected: `parity: OK (9 gates, 1 Forms)`.

- [ ] **Step 6: Commit**

```bash
git add forms/speaker.md forms/registry.md
git commit -m "docs(forms): draft the speaker Form and register its gates"
```

### Task 2: The seven Forms transcribed from the milestone 1 plan

**Files:**
- Create: `forms/engine.md`, `forms/workspace.md`, `forms/runtime.md`, `forms/oracle.md`,
  `forms/payload.md`, `forms/controls.md`, `forms/ledger.md`
- Modify: `forms/registry.md`; `forms/speaker.md` only as step 3 allows

**Interfaces:**
- Consumes: every `Produces` and `Consumes` block of the milestone 1 harness plan.
- Produces: seven draft Forms and their `planned` registry rows.

What each Form is about, so you can tell when the milestone 1 plan has put something in the
wrong crate (report it; do not move it):

| Crate | Its Form covers |
|---|---|
| `engine` | The stage machine: which action follows which outcome. It does no I/O |
| `workspace` | Agent and check containers, volumes, mounts, labels, the dependency cache, and running a command with streaming, a time limit and cancellation |
| `runtime` | The worker-runtime contract (what a host hands an agent CLI and what it gets back) and its adapters |
| `oracle` | Freezing and hashing the visible tests, and reading a test report through a preset into per-test evidence |
| `payload` | What each role may see. The Form covers the visibility rules only, not prompt wording |
| `controls` | The scope and protected-path controls, and running build, lint and format check through `workspace` |
| `ledger` | The append-only event log for a unit, assembling evidence, and resuming |

- [ ] **Step 1: Confirm the source exists**

```bash
P=docs/superpowers/plans/2026-10-04-factory-m1-harness.md
test -f "$P" && grep -c 'Produces' "$P"
```

Expected: a number greater than zero. If the file is missing or has no `Produces` block, stop
and report: this task cannot be done from anything else.

- [ ] **Step 2: Write one Form per crate, by this procedure**

Do the seven in the order of the table above. For each crate `<c>`:

1. **Find its blocks.** `grep -n "crates/<c>/" "$P"` gives the tasks that touch it. Read each
   of those tasks whole.
2. **Start from the blank Form** in `docs/forms.md` ("A Form file"). The first line is
   `# Form: <c>`. Header: `- status: draft`, `- owner: adbarc92`, `- level: E0`,
   `- last-drill: never`.
3. **`interface-files`:** every source file under `crates/<c>/src/` in which those tasks
   define a `Produces` item. Not test files. If you cannot tell, list `crates/<c>/src/lib.rs`
   and say so in the pull request.
4. **Purpose:** one paragraph in your own words: what the crate is for, from the table above
   and from what the milestone 1 plan has it do, and what would break without it.
5. **Interface:** one `rust` code block holding every `Produces` signature of that crate's
   tasks, exactly as the milestone 1 plan writes them, in the plan's order. Add nothing and
   leave nothing out. Then one sentence on how the crate reports errors, if the plan says.
6. **Invariants:** one numbered sentence for each of
   - every behaviour a test in those tasks asserts at the crate's public interface (the test
     names are a good guide);
   - every "must", "never" and "only" the milestone 1 plan states about the crate;
   - the crate's dependency rule from this plan's "Global Constraints", decision 2.

   Each must be a sentence a test could prove false. Merge duplicates. Do not write an
   invariant the milestone 1 plan gives you no basis for.
7. **Hidden decisions:** what the plan leaves to the implementer or calls internal. At least
   one. If you can find none, write the Form anyway and raise it: a crate with nothing to hide
   may not need a Form.
8. **Gates:** one row for each `crates/<c>/tests/contract_*.rs` file the plan names, guarding
   the invariants its tests assert, mechanism `locked contract tests`, blocks `merge`. One row
   with location `xtask/src/deps.rs`, mechanism `dependency direction`, for an invariant that
   is a dependency rule. A row with mechanism `type system: <how>` and blocks `build` only
   where the plan makes a wrong program fail to compile.
9. **Unenforced:** every invariant no gate guards, as `- I<n>: <why> (<today's date>)`.
   Otherwise `None.`.
10. **Regeneration notes:** what the crate `Consumes` (and from which crate), where its tests
    start, which dependencies it may not have.
11. **Register the gates:** one row in `forms/registry.md` for each gate, state `planned`.
    Command: `cargo xtask test contract` for locked contract tests (tier `contract`),
    `cargo xtask deps` for dependency direction (tier `static`),
    `cargo xtask test unit <c>` for a type-system gate (tier `unit`).
12. **Check and commit that one Form:**

    ```bash
    cargo xtask parity
    git add forms/<c>.md forms/registry.md
    git commit -m "docs(forms): draft the <c> Form from the milestone 1 plan"
    ```

    Expected: `parity: OK`, with the Form count one higher than before.

Three rules hold throughout:

- **Transcribe; never invent.** A signature that is not in the milestone 1 plan does not go in
  a Form. A question you would have to answer to finish a Form goes in the pull request.
- **Own words.** Purpose, invariants and notes are yours. Nothing is pasted from the design.
- **No line in a Form may begin with `## `** except the seven section headings, and the
  Interface code block must not contain one either: the parser reads headings by that prefix.

- [ ] **Step 3: Reconcile `speaker` with the milestone 1 plan**

Read the milestone 1 plan's `speaker` tasks and compare their `Produces` with the Interface in
`forms/speaker.md`.

- Identical, or the plan has nothing more: leave the Form alone.
- The plan **adds** items and changes none: add them to the Interface, add an invariant and a
  `planned` gate for each behaviour they bring, and commit as
  `docs(forms): extend the speaker Form with milestone 1's additions`.
- The plan **changes or removes** an item this plan defines: change nothing. Report both
  versions side by side in the pull request. It is the owner's decision.

- [ ] **Step 4: Run the lane's Verify table**

Run every command in the "Verify" table at the top of this lane and keep the output.

### Task 3: Open the pull request for the owner's approval

**Files:** none.

**Interfaces:**
- Consumes: the eight draft Forms.
- Produces: a pull request the owner can approve Form by Form.

- [ ] **Step 1: Write the body and open the pull request**

Write the body to `/d/MajorProjects/.swarm-wt/m0-rd-forms-pr.md`:

```markdown
## What this is

Eight draft Forms for the crates milestone 1 builds, transcribed from the milestone 1 harness
plan, and their gates registered as `planned`. No code changed.

## For approval

| Form | Invariants | Gates | Unenforced | Interface files |
|---|---|---|---|---|
| engine | <n> | <n> | <n> | <list> |
| workspace | | | | |
| runtime | | | | |
| oracle | | | | |
| payload | | | | |
| controls | | | | |
| ledger | | | | |
| speaker | 11 | 5 | 0 | lib.rs, transport.rs, unit.rs, testkit.rs |

To approve a Form, change its `- status: draft` to `- status: frozen`.

## Questions for the owner

<one bullet per question, each naming the Form, the place in the milestone 1 plan, and the
choice to be made; or "none">

## Where the milestone 1 plan and this plan's speaker interface differ

<the side-by-side from Task 2 step 3, or "they agree">

## How it was verified

<paste the output of each Verify command>
```

```bash
git push -u origin feat/m0-forms
gh pr create --base factory/m0 --head feat/m0-forms \
  --title "M0 forms: draft Forms for milestone 1's harness crates" \
  --body-file /d/MajorProjects/.swarm-wt/m0-rd-forms-pr.md
gh pr checks --watch
```

Expected: every check passes. Do not merge, and do not change a `status` yourself.

---

## Lane RD-SKEL

**Owns:** `crates/speaker/**`; `crates/engine/**`; `crates/runtime/src/fake.rs`;
`crates/workspace/src/fake.rs`; `crates/cli/**`. And, because nobody else is editing them at
this point, these named lines only:

- in the root `Cargo.toml`: the three contract-crate lines added in Task 1;
- `Cargo.lock`: whatever Task 1's build writes;
- `forms/contract.lock.json`: rewritten by `cargo xtask lock accept` where a step says so, and
  the one flag changed in Task 9;
- in `forms/registry.md`: the state of the five `speaker.*` rows, in Task 9;
- in `docs/STATUS.md`: the paragraphs replaced in Task 9.

It does not edit `xtask/**`, `.github/**`, any Form, or `crates/runtime/src/lib.rs` and
`crates/workspace/src/lib.rs`.

**Reads:** this plan; `forms/speaker.md`; the control plane's `harness-protocol` README and
its reference harness `harness-fake` at the tag; the supervisor's specification, for the order
of observations.

**Worktree and branch:** worktree `D:\MajorProjects\.swarm-wt\m0-rd-skel`, branch
`feat/m0-skeleton` cut from `origin/factory/m0`, pull request against `factory/m0`.

**Needs:** RD-COORD and RD-FORMS merged into `factory/m0` (owner actions A2, A4); the tag
`contracts-v0.2.0` on `adbarc92/command-center` (A6). Check the tag first:
`git ls-remote --tags https://github.com/adbarc92/command-center contracts-v0.2.0` must print
one line. If it prints nothing, stop and report.

**Blocks:** owner action A11, the milestone's proof.

**Verify:**

| Command | Expected |
|---|---|
| `cargo xtask test static` | ends `deps: OK (11 crates, 38 source files)` and `parity: OK (… gates, 8 Forms)`; exit 0 |
| `cargo xtask test unit` | `cli` 35 passed, `engine` 8, `runtime` 6, `speaker` 8, `workspace` 4, `xtask` 40, the rest 0; ends `unit: OK (11 crate(s), one at a time)` |
| `cargo xtask test contract` | `lock: OK (3 locked contract tests unchanged)`; `contract_harness_process` 9 passed, `contract_pins` 5 passed, `contract_speaker` 14 passed; the kit's cases all `PASS`; `conformance: OK (<n> passed, 0 skipped, 0 failed; kit contracts-v0.2.0)`; `contract: OK (3 locked test file(s), conformance kit: true)` |
| `cargo xtask test contract` a second time | the same, with `using the cached conformance kit` |
| `gh pr checks <the PR>` | every job passes, on Linux and on Windows |

Against the control plane's kit as it stood at protocol 0.1, the cases are
`version_mismatch_refused`, `happy_path_t1`, `gate_approved_t2`, `gate_rejected_t2`, `halt` and
`abandon`: `6 passed, 0 skipped, 0 failed`. The kit at the tag may have more. If one fails or
is skipped, do not weaken anything and do not edit a locked test: report the case name and the
kit's line for it.

### Task 1: Pin the contract crates

**Files:**
- Create: `crates/cli/tests/contract_pins.rs`
- Modify: `Cargo.toml`, `Cargo.lock`, `crates/speaker/Cargo.toml`, `crates/cli/Cargo.toml`, `forms/contract.lock.json`

**Interfaces:**
- Consumes: `harness-protocol`, `factory-spec` and `factory-presets` at `contracts-v0.2.0`.
- Produces: the three crates in this workspace's dependency graph, all from one tag; a locked
  test that the names and behaviours this harness relies on exist there.

- [ ] **Step 1: Create the worktree**

```bash
git ls-remote --tags https://github.com/adbarc92/command-center contracts-v0.2.0
git -C /d/MajorProjects/INFRASTRUCTURE/reqdrive fetch origin
git -C /d/MajorProjects/INFRASTRUCTURE/reqdrive worktree add --no-track -b feat/m0-skeleton \
  /d/MajorProjects/.swarm-wt/m0-rd-skel origin/factory/m0
cd /d/MajorProjects/.swarm-wt/m0-rd-skel
cargo xtask test static
```

Expected: the tag is listed; the static tier passes.

- [ ] **Step 2: Write the failing test**

Create `crates/cli/tests/contract_pins.rs`:

```rust
//! Locked contract tests of the pinned contract crates: the names and behaviours this harness
//! relies on exist at the tag it pins. If one of these stops compiling or passing after the
//! pin moves, the contract changed under us: stop, and report it.
//!
//! This file is hash-frozen in `forms/contract.lock.json`.

use harness_protocol::{
    bundle_hash, file_sha256, negotiate, FrozenFile, Observation, Outcome, Stage, StageStatus,
    StopReason, UnitEvent, PROTOCOL_VERSION,
};
use serde_json::json;

#[test]
fn the_protocol_is_0_2_and_negotiates_on_the_minor() {
    assert_eq!(PROTOCOL_VERSION, "0.2");
    assert!(negotiate(&["0.2"], PROTOCOL_VERSION));
    assert!(negotiate(&["0.1", "0.2"], PROTOCOL_VERSION));
    assert!(!negotiate(&["0.1"], PROTOCOL_VERSION));
    assert!(!negotiate(&["99.0"], PROTOCOL_VERSION));
}

#[test]
fn the_hash_scheme_is_sha256_lowercase_hex_over_sorted_path_lines() {
    let abc = "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad";
    assert_eq!(file_sha256(b"abc"), abc);
    let file = |path: &str| FrozenFile {
        path: path.into(),
        sha256: abc.into(),
    };
    let forwards = bundle_hash(&[file("tests/a.rs"), file("tests/b.rs")]);
    let backwards = bundle_hash(&[file("tests/b.rs"), file("tests/a.rs")]);
    assert_eq!(
        forwards, backwards,
        "the bundle hash does not depend on order"
    );
    assert_eq!(forwards.len(), 64);
    let lines = format!("tests/a.rs\0{abc}\ntests/b.rs\0{abc}\n");
    assert_eq!(forwards, file_sha256(lines.as_bytes()));
}

#[test]
fn the_wire_spellings_this_harness_relies_on() {
    let stage = UnitEvent::Stage {
        stage: Stage::Deliver,
        status: StageStatus::Finished,
        detail: None,
    };
    assert_eq!(
        serde_json::to_value(&stage).unwrap(),
        json!({ "type": "stage", "stage": "deliver", "status": "finished" })
    );
    let bare: Observation = serde_json::from_value(json!({ "kind": "oracle_frozen" })).unwrap();
    assert_eq!(bare, Observation::OracleFrozen { freeze: None });
    assert_eq!(
        serde_json::to_value(Outcome::NeedsHuman).unwrap(),
        json!("needs_human")
    );
    assert_eq!(
        serde_json::to_value(StopReason::ScopeRequest).unwrap(),
        json!("scope_request")
    );
    // Fieldless wire enums are `Copy`: this harness passes them by value.
    let stage = Stage::Red;
    let (first, second) = (stage, stage);
    assert_eq!(first, second);
}

#[test]
fn the_presets_this_harness_declares_exist_at_the_pinned_version() {
    assert!(!factory_presets::PRESETS_VERSION.is_empty());
    for name in ["cargo", "node"] {
        let preset = factory_presets::preset(name).unwrap_or_else(|| panic!("no {name} preset"));
        assert_eq!(preset.name(), name);
    }
    assert!(factory_presets::preset("cobol").is_none());
}

#[test]
fn the_spec_hash_is_sha256_lowercase_hex_over_exact_bytes() {
    assert_eq!(
        factory_spec::sha256_hex(b"abc"),
        "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
    );
    assert_ne!(
        factory_spec::sha256_hex(b"abc\n"),
        factory_spec::sha256_hex(b"abc")
    );
}
```

- [ ] **Step 3: Run it and watch it fail**

Run: `cargo test -p cli --test contract_pins`

Expected: it does not compile: `unresolved import `harness_protocol``, and
`factory_presets` and `factory_spec` are undeclared crates.

- [ ] **Step 4: Add the dependencies**

In the root `Cargo.toml`, under `[workspace.dependencies]`, after the `sha2` line, add:

```toml

# The contract crates, from the control plane's repository. One tag for all three:
# `cargo xtask deps` fails if they differ, and the conformance kit is built from the same tag.
harness-protocol = { git = "https://github.com/adbarc92/command-center", tag = "contracts-v0.2.0" }
factory-spec = { git = "https://github.com/adbarc92/command-center", tag = "contracts-v0.2.0" }
factory-presets = { git = "https://github.com/adbarc92/command-center", tag = "contracts-v0.2.0" }
```

In `crates/speaker/Cargo.toml`, make the `[dependencies]` table read:

```toml
[dependencies]
harness-protocol.workspace = true
serde.workspace = true
serde_json.workspace = true
```

In `crates/cli/Cargo.toml`, make the two dependency tables read:

```toml
[dependencies]
clap.workspace = true
engine.workspace = true
factory-presets.workspace = true
harness-protocol.workspace = true
runtime.workspace = true
serde_json.workspace = true
speaker.workspace = true
workspace.workspace = true

[dev-dependencies]
factory-spec.workspace = true
speaker = { workspace = true, features = ["testkit"] }
```

- [ ] **Step 5: Run the test**

Run: `cargo test -p cli --test contract_pins`

Expected: cargo fetches the tagged repository and updates `Cargo.lock`, then
`test result: ok. 5 passed`.

If it does not compile, or a test fails, the tagged crates differ from what this plan was
written against. **Stop here and report the exact output.** Do not change the test to match,
and do not go on to Task 2.

- [ ] **Step 6: Lock the new contract test, and check the gates**

```bash
cargo xtask lock accept
cargo xtask lock check
cargo xtask deps
```

Expected: `lock: regenerated with 1 contract tests`; `lock: OK (1 locked contract tests
unchanged)`; `deps: OK`. `deps` now also proves that all three contract crates come from one
`contracts-v` tag.

- [ ] **Step 7: Commit**

```bash
git add Cargo.toml Cargo.lock crates/speaker/Cargo.toml crates/cli/Cargo.toml \
  crates/cli/tests/contract_pins.rs forms/contract.lock.json
git commit -m "feat(contracts): pin harness-protocol, factory-spec and factory-presets to contracts-v0.2.0"
```

### Task 2: The stage machine

**Files:**
- Modify: `crates/engine/src/lib.rs`

**Interfaces:**
- Consumes: nothing. `engine` has no dependency, and `cargo xtask deps` keeps it so.
- Produces, in `engine`:
  - `pub enum Stage { Provision, Red, Plan, Green, Check, Review, Deliver }` with `Stage::ALL: [Stage; 7]`
  - `pub struct Params { pub gate_required: bool, pub min_review_rounds: u32, pub resume_frozen: bool }`
  - `pub enum CheckOutcome { Passed, Failed, EmptyDiff }`
  - `pub enum Event { Provisioned, Frozen, GateApproved, GateRejected, Planned, Built, Checked(CheckOutcome), Reviewed { unresolved_blockers: u32 }, Delivered, Stopped, Failed }`
  - `pub enum Failure { OracleRejected, Stage(Stage) }`
  - `pub enum Finish { PrOpen, NoChange, Failed(Failure), NeedsHuman(Stage) }`
  - `pub enum Action { Run(Stage), AwaitGate, Finish(Finish) }`
  - `pub struct State` with `State::start(params: Params) -> State`, `State::action(&self) -> Action`, `State::rounds(&self) -> u32`
  - `pub struct Rejected { pub action: Action, pub event: Event }`, which implements `Display`
  - `pub fn transition(state: &State, event: Event) -> Result<State, Rejected>`

This is the skeleton's machine. It has every stage and both loops (a failed check returns to
Green; an unmet review gate returns to Green). It has none of the counting that later
milestones add: no escalation, no limit on rounds. Milestone 1's engine lane replaces this
file against its Form.

- [ ] **Step 1: Write the failing tests**

Append this test module to `crates/engine/src/lib.rs`:

```rust
#[cfg(test)]
mod tests {
    use super::*;
    use Action::{AwaitGate, Finish as End, Run};
    use Stage::{Check, Deliver, Green, Plan, Provision, Red, Review};

    const T1: Params = Params {
        gate_required: false,
        min_review_rounds: 1,
        resume_frozen: false,
    };
    const T2: Params = Params {
        gate_required: true,
        ..T1
    };

    fn clean() -> Event {
        Event::Reviewed {
            unresolved_blockers: 0,
        }
    }

    /// Feed `events` in order and return every action the machine asked for, the first included.
    fn actions(params: Params, events: &[Event]) -> Vec<Action> {
        let mut state = State::start(params);
        let mut asked = vec![state.action()];
        for event in events {
            state = transition(&state, *event).expect("the table lists only legal events");
            asked.push(state.action());
        }
        asked
    }

    #[test]
    fn the_table_of_whole_units() {
        let passed = Event::Checked(CheckOutcome::Passed);
        let failed = Event::Checked(CheckOutcome::Failed);
        let empty = Event::Checked(CheckOutcome::EmptyDiff);
        let table: Vec<(&str, Params, Vec<Event>, Vec<Action>)> = vec![
            (
                "a T1 unit passes through all seven stages in order",
                T1,
                vec![
                    Event::Provisioned,
                    Event::Frozen,
                    Event::Planned,
                    Event::Built,
                    passed,
                    clean(),
                    Event::Delivered,
                ],
                vec![
                    Run(Provision),
                    Run(Red),
                    Run(Plan),
                    Run(Green),
                    Run(Check),
                    Run(Review),
                    Run(Deliver),
                    End(Finish::PrOpen),
                ],
            ),
            (
                "a gated unit waits for the gate between Red and Plan",
                T2,
                vec![Event::Provisioned, Event::Frozen, Event::GateApproved],
                vec![Run(Provision), Run(Red), AwaitGate, Run(Plan)],
            ),
            (
                "a rejected gate ends the unit as failed",
                T2,
                vec![Event::Provisioned, Event::Frozen, Event::GateRejected],
                vec![
                    Run(Provision),
                    Run(Red),
                    AwaitGate,
                    End(Finish::Failed(Failure::OracleRejected)),
                ],
            ),
            (
                "a failed check returns to Green, and a passing one goes on to Review",
                T1,
                vec![
                    Event::Provisioned,
                    Event::Frozen,
                    Event::Planned,
                    Event::Built,
                    failed,
                    Event::Built,
                    passed,
                ],
                vec![
                    Run(Provision),
                    Run(Red),
                    Run(Plan),
                    Run(Green),
                    Run(Check),
                    Run(Green),
                    Run(Check),
                    Run(Review),
                ],
            ),
            (
                "an empty diff ends the unit as no_change, with no review",
                T1,
                vec![
                    Event::Provisioned,
                    Event::Frozen,
                    Event::Planned,
                    Event::Built,
                    empty,
                ],
                vec![
                    Run(Provision),
                    Run(Red),
                    Run(Plan),
                    Run(Green),
                    Run(Check),
                    End(Finish::NoChange),
                ],
            ),
            (
                "review blockers return to Green; a clean later round delivers",
                T1,
                vec![
                    Event::Provisioned,
                    Event::Frozen,
                    Event::Planned,
                    Event::Built,
                    passed,
                    Event::Reviewed {
                        unresolved_blockers: 2,
                    },
                    Event::Built,
                    passed,
                    clean(),
                ],
                vec![
                    Run(Provision),
                    Run(Red),
                    Run(Plan),
                    Run(Green),
                    Run(Check),
                    Run(Review),
                    Run(Green),
                    Run(Check),
                    Run(Review),
                    Run(Deliver),
                ],
            ),
            (
                "a clean first review below the minimum still loops through Green and Check",
                Params {
                    min_review_rounds: 2,
                    ..T1
                },
                vec![
                    Event::Provisioned,
                    Event::Frozen,
                    Event::Planned,
                    Event::Built,
                    passed,
                    clean(),
                    Event::Built,
                    passed,
                    clean(),
                ],
                vec![
                    Run(Provision),
                    Run(Red),
                    Run(Plan),
                    Run(Green),
                    Run(Check),
                    Run(Review),
                    Run(Green),
                    Run(Check),
                    Run(Review),
                    Run(Deliver),
                ],
            ),
            (
                "a resumed unit skips Red, the gate and Plan, even at a gated tier",
                Params {
                    resume_frozen: true,
                    ..T2
                },
                vec![
                    Event::Provisioned,
                    Event::Built,
                    passed,
                    clean(),
                    Event::Delivered,
                ],
                vec![
                    Run(Provision),
                    Run(Green),
                    Run(Check),
                    Run(Review),
                    Run(Deliver),
                    End(Finish::PrOpen),
                ],
            ),
            (
                "a stop in Green ends the unit as needs_human",
                T1,
                vec![
                    Event::Provisioned,
                    Event::Frozen,
                    Event::Planned,
                    Event::Stopped,
                ],
                vec![
                    Run(Provision),
                    Run(Red),
                    Run(Plan),
                    Run(Green),
                    End(Finish::NeedsHuman(Green)),
                ],
            ),
            (
                "a failure in Plan ends the unit as failed, naming the stage",
                T1,
                vec![Event::Provisioned, Event::Frozen, Event::Failed],
                vec![
                    Run(Provision),
                    Run(Red),
                    Run(Plan),
                    End(Finish::Failed(Failure::Stage(Plan))),
                ],
            ),
        ];
        for (name, params, events, expected) in table {
            assert_eq!(actions(params, &events), expected, "{name}");
        }
    }

    #[test]
    fn rounds_count_from_one_and_only_reviews_count() {
        let mut state = State::start(T1);
        for event in [
            Event::Provisioned,
            Event::Frozen,
            Event::Planned,
            Event::Built,
            Event::Checked(CheckOutcome::Passed),
        ] {
            state = transition(&state, event).unwrap();
            assert_eq!(state.rounds(), 0);
        }
        state = transition(
            &state,
            Event::Reviewed {
                unresolved_blockers: 1,
            },
        )
        .unwrap();
        assert_eq!(state.rounds(), 1);
        state = transition(&state, Event::Built).unwrap();
        state = transition(&state, Event::Checked(CheckOutcome::Passed)).unwrap();
        state = transition(&state, clean()).unwrap();
        assert_eq!(state.rounds(), 2);
    }

    #[test]
    fn a_minimum_of_zero_rounds_still_reviews_once() {
        let zero = Params {
            min_review_rounds: 0,
            ..T1
        };
        let asked = actions(
            zero,
            &[
                Event::Provisioned,
                Event::Frozen,
                Event::Planned,
                Event::Built,
                Event::Checked(CheckOutcome::Passed),
                clean(),
            ],
        );
        assert_eq!(asked[5..], [Run(Review), Run(Deliver)]);
    }

    #[test]
    fn a_person_is_never_asked_for_in_provision_or_deliver() {
        let provision = State::start(T1);
        assert!(transition(&provision, Event::Stopped).is_err());
        assert_eq!(
            transition(&provision, Event::Failed).unwrap().action(),
            End(Finish::Failed(Failure::Stage(Provision)))
        );

        let mut deliver = State::start(Params {
            resume_frozen: true,
            ..T1
        });
        for event in [
            Event::Provisioned,
            Event::Built,
            Event::Checked(CheckOutcome::Passed),
            clean(),
        ] {
            deliver = transition(&deliver, event).unwrap();
        }
        assert_eq!(deliver.action(), Run(Deliver));
        assert!(transition(&deliver, Event::Stopped).is_err());
    }

    #[test]
    fn every_stage_from_red_to_review_may_stop_for_a_person() {
        for stage in [Red, Plan, Green, Check, Review] {
            let state = State {
                action: Run(stage),
                params: T1,
                rounds: 0,
            };
            assert_eq!(
                transition(&state, Event::Stopped).unwrap().action(),
                End(Finish::NeedsHuman(stage))
            );
        }
    }

    #[test]
    fn an_event_that_does_not_answer_the_action_is_rejected_and_changes_nothing() {
        let state = State::start(T1);
        let rejected = transition(&state, Event::Built).unwrap_err();
        assert_eq!(rejected.action, Run(Provision));
        assert_eq!(rejected.event, Event::Built);
        assert_eq!(
            rejected.to_string(),
            "Built is not an answer to Run(Provision)"
        );
        assert_eq!(state, State::start(T1));

        let gate = transition(
            &transition(&State::start(T2), Event::Provisioned).unwrap(),
            Event::Frozen,
        )
        .unwrap();
        assert!(transition(&gate, Event::Planned).is_err());
        assert!(transition(&State::start(T1), Event::GateApproved).is_err());
    }

    #[test]
    fn a_finished_unit_accepts_nothing() {
        let done = State {
            action: End(Finish::PrOpen),
            params: T1,
            rounds: 1,
        };
        for event in [
            Event::Provisioned,
            Event::Built,
            Event::Stopped,
            Event::Failed,
            Event::Delivered,
        ] {
            assert!(transition(&done, event).is_err());
        }
    }

    #[test]
    fn the_seven_stages_are_listed_in_order() {
        assert_eq!(
            Stage::ALL,
            [Provision, Red, Plan, Green, Check, Review, Deliver]
        );
    }
}
```

- [ ] **Step 2: Run them and watch them fail**

Run: `cargo test -p engine --lib`

Expected: it does not compile; the errors name `State`, `Params`, `Event`, `Action` and
`transition`.

- [ ] **Step 3: Write the implementation**

Replace everything above the test module in `crates/engine/src/lib.rs` with:

````rust
//! `engine`: the unit's stage machine. It decides the next action from stage outcomes.
//!
//! Pure: no I/O, no clock, no dependency. The host asks [`State::action`] what to do, does it,
//! and reports what happened to [`transition`]. This is the walking skeleton's machine: it has
//! every stage and both loops, and none of the counting (escalation, round limits) that later
//! milestones add.
//!
//! ```text
//! Provision -> Red -> [gate] -> Plan -> Green -> Check -> Review -> Deliver -> pr_open
//!                                         ^        |         |
//!                                         +- failed+         |
//!                                         +--- gate not met -+
//! ```

#[cfg(any(test, feature = "testkit"))]
pub mod testkit;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum Stage {
    Provision,
    Red,
    Plan,
    Green,
    Check,
    Review,
    Deliver,
}

impl Stage {
    /// The seven stages, in the order a fresh unit passes through them.
    pub const ALL: [Stage; 7] = [
        Stage::Provision,
        Stage::Red,
        Stage::Plan,
        Stage::Green,
        Stage::Check,
        Stage::Review,
        Stage::Deliver,
    ];
}

/// What the work order fixes about a unit before it starts.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Params {
    /// The unit's tier needs a person to approve the frozen tests before any plan exists.
    pub gate_required: bool,
    /// Reviews that must happen before the review gate can be met.
    pub min_review_rounds: u32,
    /// A respawn whose tests are already frozen: Red, the gate and Plan are skipped.
    pub resume_frozen: bool,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum CheckOutcome {
    Passed,
    Failed,
    /// The unit changed nothing.
    EmptyDiff,
}

/// What happened when the host did what [`State::action`] asked.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Event {
    Provisioned,
    Frozen,
    GateApproved,
    GateRejected,
    Planned,
    Built,
    Checked(CheckOutcome),
    Reviewed {
        unresolved_blockers: u32,
    },
    Delivered,
    /// The stage in progress stopped for a person.
    Stopped,
    /// The stage in progress failed.
    Failed,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Failure {
    OracleRejected,
    Stage(Stage),
}

/// How a unit ends.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Finish {
    PrOpen,
    NoChange,
    Failed(Failure),
    /// Stopped for a person in this stage.
    NeedsHuman(Stage),
}

/// What the host must do next.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Action {
    Run(Stage),
    AwaitGate,
    Finish(Finish),
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct State {
    action: Action,
    params: Params,
    rounds: u32,
}

/// An event that is not a legal answer to the current action. A host bug, never a unit outcome.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Rejected {
    pub action: Action,
    pub event: Event,
}

impl std::fmt::Display for Rejected {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{:?} is not an answer to {:?}", self.event, self.action)
    }
}

impl State {
    pub fn start(params: Params) -> State {
        State {
            action: Action::Run(Stage::Provision),
            params,
            rounds: 0,
        }
    }

    pub fn action(&self) -> Action {
        self.action
    }

    /// Reviews finished so far in this process. Counts from 1 after the first review.
    pub fn rounds(&self) -> u32 {
        self.rounds
    }
}

/// A person may be asked for only while an agent could be working: not before the workspace
/// exists, and not once the work is being handed over.
fn may_stop(stage: Stage) -> bool {
    !matches!(stage, Stage::Provision | Stage::Deliver)
}

pub fn transition(state: &State, event: Event) -> Result<State, Rejected> {
    use Action::{AwaitGate, Finish as End, Run};
    let params = state.params;
    let mut rounds = state.rounds;
    let action = match (state.action, event) {
        (Run(Stage::Provision), Event::Provisioned) if params.resume_frozen => Run(Stage::Green),
        (Run(Stage::Provision), Event::Provisioned) => Run(Stage::Red),
        (Run(Stage::Red), Event::Frozen) if params.gate_required => AwaitGate,
        (Run(Stage::Red), Event::Frozen) => Run(Stage::Plan),
        (AwaitGate, Event::GateApproved) => Run(Stage::Plan),
        (AwaitGate, Event::GateRejected) => End(Finish::Failed(Failure::OracleRejected)),
        (Run(Stage::Plan), Event::Planned) => Run(Stage::Green),
        (Run(Stage::Green), Event::Built) => Run(Stage::Check),
        (Run(Stage::Check), Event::Checked(CheckOutcome::Passed)) => Run(Stage::Review),
        (Run(Stage::Check), Event::Checked(CheckOutcome::Failed)) => Run(Stage::Green),
        (Run(Stage::Check), Event::Checked(CheckOutcome::EmptyDiff)) => End(Finish::NoChange),
        (
            Run(Stage::Review),
            Event::Reviewed {
                unresolved_blockers,
            },
        ) => {
            rounds += 1;
            if unresolved_blockers == 0 && rounds >= params.min_review_rounds {
                Run(Stage::Deliver)
            } else {
                Run(Stage::Green)
            }
        }
        (Run(Stage::Deliver), Event::Delivered) => End(Finish::PrOpen),
        (Run(stage), Event::Stopped) if may_stop(stage) => End(Finish::NeedsHuman(stage)),
        (Run(stage), Event::Failed) => End(Finish::Failed(Failure::Stage(stage))),
        (action, event) => return Err(Rejected { action, event }),
    };
    Ok(State {
        action,
        params,
        rounds,
    })
}
````

- [ ] **Step 4: Run the tests**

Run: `cargo test -p engine --lib`

Expected: `test result: ok. 8 passed`.

- [ ] **Step 5: Commit**

```bash
git add crates/engine/src/lib.rs
git commit -m "feat(engine): the walking skeleton's stage machine, with table tests"
```

### Task 3: The scripted runtime and its scenario file

**Files:**
- Modify: `crates/runtime/src/fake.rs`

**Interfaces:**
- Consumes: `serde`, `serde_json`.
- Produces, in `runtime::fake`:
  - `pub enum Stage { Red, Plan, Green, Check, Review }`, `pub enum Check { Passed, Failed, EmptyDiff }`
  - `pub struct TestFile { pub path: String, pub body: String, pub ids: Vec<String> }`
  - `pub struct StopAt { pub stage: Stage, pub reason: String, pub detail: String, pub request: Vec<String> }`
  - `pub struct FailAt { pub stage: Stage, pub detail: String }`
  - `pub struct Scenario { pub step_ms: u64, pub checks: Vec<Check>, pub reviews: Vec<u32>, pub stop: Option<StopAt>, pub fail: Option<FailAt>, pub tests: Vec<TestFile>, pub holdouts: Vec<TestFile>, pub log_lines: u32 }`, with `Default` and `Scenario::parse(text: &str) -> Result<Scenario, ScenarioError>`
  - `pub struct ScenarioError(pub String)`, which implements `Display`
  - `pub enum Scripted { Authored { tests, holdouts }, Planned, Built { log: Vec<String> }, Checked(Check), Reviewed { unresolved_blockers: u32 }, Stop(StopAt), Fail(FailAt) }`
  - `pub struct FakeRuntime` with `FakeRuntime::new(scenario: Scenario) -> FakeRuntime`, `pause(&self) -> Duration`, `run(&mut self, stage: Stage) -> Scripted`

This carries over the idea of the Bash suite's fake `claude` binary
(`archive/bash-v0.3/tests/lib/pipeline-harness.sh`): a stand-in agent whose behaviour a test
picks by name. There it was a mode word; here it is a small JSON file, so one stand-in can stage
any path through a unit.

- [ ] **Step 1: Write the failing tests**

Append this test module to `crates/runtime/src/fake.rs`:

```rust
#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn an_empty_scenario_is_the_happy_path() {
        let scenario = Scenario::parse("{}").unwrap();
        assert_eq!(scenario, Scenario::default());
        let mut runtime = FakeRuntime::new(scenario);
        assert_eq!(runtime.pause(), Duration::ZERO);
        assert!(matches!(
            runtime.run(Stage::Red),
            Scripted::Authored { tests, holdouts } if tests.len() == 1 && holdouts.len() == 1
        ));
        assert_eq!(runtime.run(Stage::Plan), Scripted::Planned);
        assert_eq!(runtime.run(Stage::Green), Scripted::Built { log: vec![] });
        assert_eq!(runtime.run(Stage::Check), Scripted::Checked(Check::Passed));
        assert_eq!(
            runtime.run(Stage::Review),
            Scripted::Reviewed {
                unresolved_blockers: 0
            }
        );
    }

    #[test]
    fn checks_and_reviews_are_consumed_in_order_then_default() {
        let scenario =
            Scenario::parse(r#"{"checks": ["failed", "empty_diff"], "reviews": [2]}"#).unwrap();
        let mut runtime = FakeRuntime::new(scenario);
        assert_eq!(runtime.run(Stage::Check), Scripted::Checked(Check::Failed));
        assert_eq!(
            runtime.run(Stage::Check),
            Scripted::Checked(Check::EmptyDiff)
        );
        assert_eq!(runtime.run(Stage::Check), Scripted::Checked(Check::Passed));
        assert_eq!(
            runtime.run(Stage::Review),
            Scripted::Reviewed {
                unresolved_blockers: 2
            }
        );
        assert_eq!(
            runtime.run(Stage::Review),
            Scripted::Reviewed {
                unresolved_blockers: 0
            }
        );
    }

    #[test]
    fn a_scripted_stop_or_failure_replaces_that_stage_only() {
        let scenario = Scenario::parse(
            r#"{"stop": {"stage": "green", "reason": "scope_request", "detail": "needs src/b.rs",
                         "request": ["src/b.rs"]},
                "fail": {"stage": "plan", "detail": "no plan"}}"#,
        )
        .unwrap();
        let mut runtime = FakeRuntime::new(scenario);
        assert!(matches!(runtime.run(Stage::Red), Scripted::Authored { .. }));
        assert!(matches!(runtime.run(Stage::Plan), Scripted::Fail(f) if f.detail == "no plan"));
        match runtime.run(Stage::Green) {
            Scripted::Stop(stop) => {
                assert_eq!(stop.reason, "scope_request");
                assert_eq!(stop.request, vec!["src/b.rs"]);
            }
            other => panic!("expected a stop, got {other:?}"),
        }
    }

    #[test]
    fn the_builder_prints_as_many_lines_as_scripted() {
        let mut runtime = FakeRuntime::new(Scenario::parse(r#"{"log_lines": 3}"#).unwrap());
        match runtime.run(Stage::Green) {
            Scripted::Built { log } => {
                assert_eq!(log.len(), 3);
                assert_eq!(log[2], "scripted builder line 3 of 3");
            }
            other => panic!("expected a build, got {other:?}"),
        }
    }

    #[test]
    fn crlf_line_endings_and_a_byte_order_mark_change_nothing() {
        let unix = "{\n  \"step_ms\": 5,\n  \"checks\": [\"failed\",\n    \"passed\"]\n}\n";
        let windows = format!("\u{feff}{}", unix.replace('\n', "\r\n"));
        assert_eq!(
            Scenario::parse(&windows).unwrap(),
            Scenario::parse(unix).unwrap()
        );
        assert_eq!(Scenario::parse(&windows).unwrap().step_ms, 5);
    }

    #[test]
    fn a_misspelt_field_is_an_error_not_the_happy_path() {
        let error = Scenario::parse(r#"{"check": ["failed"]}"#).unwrap_err();
        assert!(error
            .to_string()
            .starts_with("scenario: unknown field `check`"));
        assert!(Scenario::parse(r#"{"checks": ["flaky"]}"#).is_err());
        assert!(Scenario::parse("").is_err());
    }
}
```

- [ ] **Step 2: Run them and watch them fail**

Run: `cargo test -p runtime --lib`

Expected: it does not compile; the errors name `Scenario`, `FakeRuntime`, `Scripted`, `Stage`
and `Check`.

- [ ] **Step 3: Write the implementation**

Replace everything above the test module in `crates/runtime/src/fake.rs` with:

````rust
//! A scripted worker runtime. It starts no agent and reaches nothing: every stage's outcome is
//! read from a scenario, so a test can stage any path through a unit.
//!
//! A scenario is a small JSON file. Every field is optional; an empty object is the happy path.
//!
//! ```json
//! {
//!   "step_ms": 0,
//!   "checks": ["failed", "passed"],
//!   "reviews": [1, 0],
//!   "stop": { "stage": "green", "reason": "scope_request", "detail": "needs src/b.rs", "request": ["src/b.rs"] },
//!   "fail": { "stage": "plan", "detail": "planner reply failed its schema twice" },
//!   "tests": [{ "path": "tests/a.rs", "body": "...", "ids": ["a::ac1_holds"] }],
//!   "holdouts": [{ "path": "tests/h.rs", "body": "...", "ids": ["h::ac1_holds"] }],
//!   "log_lines": 0
//! }
//! ```

use serde::Deserialize;
use std::collections::VecDeque;
use std::time::Duration;

/// The stages a scenario can script. Provision and Deliver belong to the workspace.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum Stage {
    Red,
    Plan,
    Green,
    Check,
    Review,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum Check {
    Passed,
    Failed,
    EmptyDiff,
}

#[derive(Debug, Clone, PartialEq, Eq, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct TestFile {
    /// Repository-relative.
    pub path: String,
    pub body: String,
    /// The test ids this file declares.
    pub ids: Vec<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct StopAt {
    pub stage: Stage,
    /// A stop reason, spelled as on the wire (for example `scope_request`).
    pub reason: String,
    pub detail: String,
    #[serde(default)]
    pub request: Vec<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct FailAt {
    pub stage: Stage,
    pub detail: String,
}

#[derive(Debug, Clone, PartialEq, Eq, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Scenario {
    /// A pause before each stage, so that a controller can interrupt a unit in flight.
    #[serde(default)]
    pub step_ms: u64,
    /// One entry per Check, in order. When the list runs out, checks pass.
    #[serde(default)]
    pub checks: Vec<Check>,
    /// Unresolved blockers per Review round, in order. When the list runs out, zero.
    #[serde(default)]
    pub reviews: Vec<u32>,
    /// Stop for a person when this stage is reached.
    #[serde(default)]
    pub stop: Option<StopAt>,
    /// Fail the unit when this stage is reached.
    #[serde(default)]
    pub fail: Option<FailAt>,
    /// The visible tests the scripted test author writes in Red.
    #[serde(default = "default_tests")]
    pub tests: Vec<TestFile>,
    /// The holdouts the scripted holdout author writes in Red.
    #[serde(default = "default_holdouts")]
    pub holdouts: Vec<TestFile>,
    /// Log lines the scripted builder prints in each Green.
    #[serde(default)]
    pub log_lines: u32,
}

fn default_tests() -> Vec<TestFile> {
    vec![TestFile {
        path: "tests/scripted_ac1.rs".into(),
        body: "// A scripted visible test for criterion ac1.\n".into(),
        ids: vec!["scripted_ac1::ac1_holds".into()],
    }]
}

fn default_holdouts() -> Vec<TestFile> {
    vec![TestFile {
        path: "tests/holdout_ac1.rs".into(),
        body: "// A scripted holdout for criterion ac1.\n".into(),
        ids: vec!["holdout_ac1::ac1_holds".into()],
    }]
}

impl Default for Scenario {
    fn default() -> Self {
        Scenario {
            step_ms: 0,
            checks: Vec::new(),
            reviews: Vec::new(),
            stop: None,
            fail: None,
            tests: default_tests(),
            holdouts: default_holdouts(),
            log_lines: 0,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ScenarioError(pub String);

impl std::fmt::Display for ScenarioError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "scenario: {}", self.0)
    }
}

impl Scenario {
    /// Parse a scenario file's text. A byte-order mark and CRLF line endings are accepted, so a
    /// file saved by a Windows editor reads the same as one saved anywhere else. An unknown
    /// field is an error: a misspelt key must not silently become the happy path.
    pub fn parse(text: &str) -> Result<Scenario, ScenarioError> {
        let text = text.strip_prefix('\u{feff}').unwrap_or(text);
        serde_json::from_str(text).map_err(|e| ScenarioError(e.to_string()))
    }
}

/// What the scripted runtime did in one stage.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Scripted {
    Authored {
        tests: Vec<TestFile>,
        holdouts: Vec<TestFile>,
    },
    Planned,
    Built {
        log: Vec<String>,
    },
    Checked(Check),
    Reviewed {
        unresolved_blockers: u32,
    },
    Stop(StopAt),
    Fail(FailAt),
}

#[derive(Debug, Clone)]
pub struct FakeRuntime {
    scenario: Scenario,
    checks: VecDeque<Check>,
    reviews: VecDeque<u32>,
}

impl FakeRuntime {
    pub fn new(scenario: Scenario) -> FakeRuntime {
        FakeRuntime {
            checks: scenario.checks.iter().copied().collect(),
            reviews: scenario.reviews.iter().copied().collect(),
            scenario,
        }
    }

    /// How long the host should pause before each stage.
    pub fn pause(&self) -> Duration {
        Duration::from_millis(self.scenario.step_ms)
    }

    /// Run one stage as scripted. A scripted stop or failure for this stage wins over its
    /// ordinary outcome.
    pub fn run(&mut self, stage: Stage) -> Scripted {
        if let Some(stop) = self.scenario.stop.as_ref().filter(|s| s.stage == stage) {
            return Scripted::Stop(stop.clone());
        }
        if let Some(fail) = self.scenario.fail.as_ref().filter(|f| f.stage == stage) {
            return Scripted::Fail(fail.clone());
        }
        match stage {
            Stage::Red => Scripted::Authored {
                tests: self.scenario.tests.clone(),
                holdouts: self.scenario.holdouts.clone(),
            },
            Stage::Plan => Scripted::Planned,
            Stage::Green => Scripted::Built {
                log: (1..=self.scenario.log_lines)
                    .map(|n| format!("scripted builder line {n} of {}", self.scenario.log_lines))
                    .collect(),
            },
            Stage::Check => Scripted::Checked(self.checks.pop_front().unwrap_or(Check::Passed)),
            Stage::Review => Scripted::Reviewed {
                unresolved_blockers: self.reviews.pop_front().unwrap_or(0),
            },
        }
    }
}
````

- [ ] **Step 4: Run the tests**

Run: `cargo test -p runtime --lib`

Expected: `test result: ok. 6 passed`.

- [ ] **Step 5: Commit**

```bash
git add crates/runtime/src/fake.rs
git commit -m "feat(runtime): a scripted fake runtime driven by a scenario file"
```

### Task 4: The in-memory workspace

**Files:**
- Modify: `crates/workspace/src/fake.rs`

**Interfaces:**
- Consumes: nothing.
- Produces, in `workspace::fake`:
  - `pub const FAKE_HEAD_SHA: &str`
  - `pub struct FakeWorkspace` with `FakeWorkspace::provision(root: impl Into<PathBuf>, unit_id: &str) -> FakeWorkspace`, `root(&self) -> &Path`, `head_sha(&self) -> &'static str`, `bundle_path(&self) -> String`, `holdout_bundle_path(&self) -> String`
  - `pub fn repo_path(raw: &str) -> String`

- [ ] **Step 1: Write the failing tests**

Append this test module to `crates/workspace/src/fake.rs`:

```rust
#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_provisioned_workspace_reports_a_head_and_touches_no_disk() {
        let root = std::env::temp_dir().join("reqdrive-fake-never-created");
        let workspace = FakeWorkspace::provision(&root, "unit-1");
        assert_eq!(workspace.head_sha().len(), 40);
        assert_eq!(workspace.root(), root.as_path());
        assert!(!root.exists());
    }

    #[test]
    fn host_paths_keep_the_hosts_own_separators() {
        let workspace = FakeWorkspace::provision(Path::new("ws").join("units"), "unit-1");
        let expected = Path::new("ws").join("units").join("unit-1.bundle");
        assert_eq!(workspace.bundle_path(), expected.to_string_lossy());
        assert!(workspace
            .holdout_bundle_path()
            .ends_with("unit-1.holdouts.tar"));
    }

    #[test]
    fn a_windows_style_root_survives_as_given() {
        let workspace = FakeWorkspace::provision(r"C:\Users\someone\ws", "u1");
        assert!(workspace.bundle_path().starts_with(r"C:\Users\someone\ws"));
        assert!(workspace.bundle_path().ends_with("u1.bundle"));
    }

    #[test]
    fn repository_paths_always_use_forward_slashes() {
        assert_eq!(repo_path(r"tests\scripted_ac1.rs"), "tests/scripted_ac1.rs");
        assert_eq!(repo_path(r".\crates\a\tests\x.rs"), "crates/a/tests/x.rs");
        assert_eq!(repo_path("./tests/a.rs"), "tests/a.rs");
        assert_eq!(repo_path("tests/a.rs"), "tests/a.rs");
    }
}
```

- [ ] **Step 2: Run them and watch them fail**

Run: `cargo test -p workspace --lib`

Expected: it does not compile; the errors name `FakeWorkspace` and `repo_path`.

- [ ] **Step 3: Write the implementation**

Replace everything above the test module in `crates/workspace/src/fake.rs` with:

```rust
//! A workspace that exists only in memory: no container, no volume, no file on disk. It gives
//! the walking skeleton something to provision and something to deliver.

use std::path::{Path, PathBuf};

/// The commit every fake workspace reports as its head.
pub const FAKE_HEAD_SHA: &str = "0123456789abcdef0123456789abcdef01234567";

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct FakeWorkspace {
    root: PathBuf,
    unit_id: String,
}

impl FakeWorkspace {
    /// "Create" the workspace for one unit under `root`. Nothing is written.
    pub fn provision(root: impl Into<PathBuf>, unit_id: &str) -> FakeWorkspace {
        FakeWorkspace {
            root: root.into(),
            unit_id: unit_id.to_string(),
        }
    }

    pub fn root(&self) -> &Path {
        &self.root
    }

    pub fn head_sha(&self) -> &'static str {
        FAKE_HEAD_SHA
    }

    /// Where the unit's git bundle would be written: a host path, in the host's own form.
    pub fn bundle_path(&self) -> String {
        self.host_path("bundle")
    }

    /// Where the unit's holdout bundle would be written: a host path, in the host's own form.
    pub fn holdout_bundle_path(&self) -> String {
        self.host_path("holdouts.tar")
    }

    fn host_path(&self, extension: &str) -> String {
        self.root
            .join(format!("{}.{extension}", self.unit_id))
            .to_string_lossy()
            .into_owned()
    }
}

/// A repository-relative path in the one form evidence may carry: forward slashes, and no
/// leading `./`. Hashes are taken over these paths, so a path spelt the Windows way must not
/// change a hash.
pub fn repo_path(raw: &str) -> String {
    let forward = raw.replace('\\', "/");
    forward.strip_prefix("./").unwrap_or(&forward).to_string()
}
```

- [ ] **Step 4: Run the tests**

Run: `cargo test -p workspace --lib`

Expected: `test result: ok. 4 passed`.

- [ ] **Step 5: Commit**

```bash
git add crates/workspace/src/fake.rs
git commit -m "feat(workspace): an in-memory fake workspace and repository-path normalising"
```

### Task 5: The transport under the protocol

**Files:**
- Create: `crates/speaker/src/transport.rs`
- Modify: `crates/speaker/src/lib.rs`

**Interfaces:**
- Consumes: `harness_protocol::{read_message, write_message, ReadError, RpcMessage, MAX_LINE_BYTES}`.
- Produces, in `speaker`:
  - `pub trait Transport { fn send(&mut self, message: &RpcMessage) -> Result<(), Closed>; fn recv(&mut self, wait: Option<Duration>) -> Recv; }`
  - `pub struct Closed;`
  - `pub enum Recv { Message(RpcMessage), Malformed(String), Idle, Closed }`
  - `pub struct StdioTransport<W: Write>`, with `StdioTransport::<Stdout>::stdio() -> Self` and `StdioTransport::over<R: Read + Send + 'static>(input: R, out: W) -> Self`

Two design decisions live in this file.

- The one Review Focus 1 is about: the input is read on its own thread into a queue with no
  bound, from the moment the transport exists.
- What a read error means. `harness_protocol::read_message` reports five: `Eof` and `Io` end
  the input, as they must. `Malformed` (readable text that is not a JSON-RPC message) is
  passed up as `Recv::Malformed`, and the unit drops it. `InvalidUtf8` and `LineTooLong` are
  **fatal for the unit**: the first line might have been an abandon or a gate answer, and
  after the second the reader is in the middle of a line. So the reader thread writes one
  line to stderr saying which it was, and stops. The caller then sees `Recv::Closed`, and the
  unit ends exactly as it does when stdin closes: no result, exit 0. No new variant is added
  to `Recv` or to `Stopped` for this: only stderr tells an unreadable line from a closed input.
  The `match` in `unreadable` names every variant, so a sixth read error in a later protocol
  version fails to compile here until someone decides what it means.

- [ ] **Step 1: Write the failing tests**

Replace `crates/speaker/src/lib.rs` with:

```rust
//! `speaker`: the harness side of the harness protocol, over stdin and stdout.
//!
//! A harness is one process per unit of work. The control plane writes one JSON-RPC message
//! per line to its stdin and reads one per line from its stdout. This crate turns that wire
//! into three things a harness calls:
//!
//! - [`open`] performs the handshake (`initialize`, then `unit/start`) and returns the work
//!   order with a [`Unit`];
//! - [`Unit`] sends events, asks for a gate, notices `unit/halt` and `unit/abandon`, and sends
//!   the one `unit/result`;
//! - [`Transport`] is the seam under both: [`StdioTransport`] for a real process, and
//!   `testkit::ScriptedPeer` for tests.
//!
//! The interface, its invariants and its gates are `forms/speaker.md`.

mod transport;

#[cfg(any(test, feature = "testkit"))]
pub mod testkit;

pub use transport::{Closed, Recv, StdioTransport, Transport};
```

Create `crates/speaker/src/transport.rs` with only its tests:

```rust
#[cfg(test)]
mod tests {
    use super::*;
    use harness_protocol::{method, Empty};
    use std::io::Cursor;

    fn line(message: &RpcMessage) -> String {
        format!("{}\n", serde_json::to_string(message).unwrap())
    }

    #[test]
    fn messages_arrive_in_order_then_the_input_closes() {
        let input = format!(
            "{}{}",
            line(&RpcMessage::request(1, method::UNIT_HALT, &Empty {})),
            line(&RpcMessage::request(2, method::UNIT_ABANDON, &Empty {})),
        );
        let mut transport = StdioTransport::over(Cursor::new(input.into_bytes()), Vec::new());
        assert!(matches!(transport.recv(None), Recv::Message(m) if m.id == Some(1)));
        assert!(matches!(transport.recv(None), Recv::Message(m) if m.id == Some(2)));
        assert_eq!(transport.recv(None), Recv::Closed);
        assert_eq!(transport.recv(Some(Duration::ZERO)), Recv::Closed);
    }

    #[test]
    fn crlf_blank_lines_and_garbage_are_each_handled() {
        let halt =
            serde_json::to_string(&RpcMessage::request(1, method::UNIT_HALT, &Empty {})).unwrap();
        let input = format!("\r\n{halt}\r\n\r\nthis is not json\r\n");
        let mut transport = StdioTransport::over(Cursor::new(input.into_bytes()), Vec::new());
        assert!(matches!(transport.recv(None), Recv::Message(m) if m.id == Some(1)));
        assert_eq!(
            transport.recv(None),
            Recv::Malformed("this is not json".into())
        );
        assert_eq!(transport.recv(None), Recv::Closed);
    }

    #[test]
    fn a_wait_ends_idle_when_nothing_arrives() {
        let (reader, _keep_open) = std::io::pipe().unwrap();
        let mut transport = StdioTransport::over(reader, Vec::new());
        assert_eq!(transport.recv(Some(Duration::ZERO)), Recv::Idle);
        assert_eq!(transport.recv(Some(Duration::from_millis(20))), Recv::Idle);
    }

    #[test]
    fn a_sent_message_is_one_json_line() {
        let mut transport = StdioTransport::over(Cursor::new(Vec::new()), Vec::new());
        transport.send(&RpcMessage::response(7, &Empty {})).unwrap();
        let written = String::from_utf8(transport.out.clone()).unwrap();
        assert_eq!(written, "{\"jsonrpc\":\"2.0\",\"id\":7,\"result\":{}}\n");
    }

    #[test]
    fn a_closed_output_is_reported_not_panicked_on() {
        struct Broken;
        impl Write for Broken {
            fn write(&mut self, _: &[u8]) -> std::io::Result<usize> {
                Err(std::io::ErrorKind::BrokenPipe.into())
            }
            fn flush(&mut self) -> std::io::Result<()> {
                Ok(())
            }
        }
        let mut transport = StdioTransport::over(Cursor::new(Vec::new()), Broken);
        assert_eq!(
            transport.send(&RpcMessage::response(1, &Empty {})),
            Err(Closed)
        );
    }
    #[test]
    fn a_line_that_is_not_utf8_ends_the_input_for_good() {
        let halt = line(&RpcMessage::request(1, method::UNIT_HALT, &Empty {}));
        let abandon = line(&RpcMessage::request(2, method::UNIT_ABANDON, &Empty {}));
        let mut input = halt.into_bytes();
        input.extend_from_slice(b"{\"jsonrpc\":\"2.0\",\"method\":\"\xff\xfe\"}\n");
        input.extend_from_slice(abandon.as_bytes());
        let mut transport = StdioTransport::over(Cursor::new(input), Vec::new());
        assert!(matches!(transport.recv(None), Recv::Message(m) if m.id == Some(1)));
        assert_eq!(
            transport.recv(None),
            Recv::Closed,
            "nothing after the unreadable line is delivered, not even a well-formed message"
        );
    }

    #[test]
    fn a_line_over_the_limit_ends_the_input_for_good() {
        let abandon = line(&RpcMessage::request(2, method::UNIT_ABANDON, &Empty {}));
        let mut input = vec![b'x'; harness_protocol::MAX_LINE_BYTES + 1];
        input.push(b'\n');
        input.extend_from_slice(abandon.as_bytes());
        let mut transport = StdioTransport::over(Cursor::new(input), Vec::new());
        assert_eq!(transport.recv(None), Recv::Closed);
    }

    #[test]
    fn only_a_line_that_cannot_be_read_is_fatal_and_each_says_why() {
        let not_utf8 = ReadError::InvalidUtf8 { line: "?".into() };
        assert_eq!(
            unreadable(&not_utf8).as_deref(),
            Some("a line from the control plane is not UTF-8")
        );
        let too_long = ReadError::LineTooLong { limit: 4 };
        assert_eq!(
            unreadable(&too_long).as_deref(),
            Some("a line from the control plane is longer than 4 bytes")
        );
        let not_a_message = ReadError::Malformed {
            line: "hello".into(),
            error: "expected value".into(),
        };
        assert_eq!(unreadable(&not_a_message), None);
        assert_eq!(unreadable(&ReadError::Eof), None);
    }
}
```

- [ ] **Step 2: Run them and watch them fail**

Run: `cargo test -p speaker --lib`

Expected: it does not compile; the errors name `Closed`, `Recv`, `StdioTransport` and
`Transport`.

- [ ] **Step 3: Write the implementation**

Put this above the test module in `crates/speaker/src/transport.rs`:

```rust
//! The seam between the protocol and the bytes: one message out, one message in.

use harness_protocol::{read_message, write_message, ReadError, RpcMessage};
use std::io::{BufReader, Read, Stdout, Write};
use std::sync::mpsc::{self, Receiver, RecvTimeoutError, TryRecvError};
use std::time::Duration;

/// The other side is gone: its end of the pipe is closed.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Closed;

/// What waiting for the next inbound line produced.
#[derive(Debug, Clone, PartialEq)]
pub enum Recv {
    Message(RpcMessage),
    /// A line of readable text that is not a protocol message, kept verbatim.
    Malformed(String),
    /// Nothing arrived within the wait.
    Idle,
    /// The input has ended: the peer closed it, or sent a line that cannot be read.
    Closed,
}

pub trait Transport {
    fn send(&mut self, message: &RpcMessage) -> Result<(), Closed>;
    /// The next inbound message. `None` waits until one arrives or the input closes;
    /// `Some(wait)` gives up after `wait`, and `Some(Duration::ZERO)` does not wait at all.
    fn recv(&mut self, wait: Option<Duration>) -> Recv;
}

enum Inbound {
    Message(RpcMessage),
    Malformed(String),
}

impl From<Inbound> for Recv {
    fn from(inbound: Inbound) -> Recv {
        match inbound {
            Inbound::Message(message) => Recv::Message(message),
            Inbound::Malformed(line) => Recv::Malformed(line),
        }
    }
}

/// Why a read error ends the input for good, if it does. A line that is not UTF-8 could have
/// been anything, an interrupt or a gate answer included, and a line over the limit leaves the
/// reader inside it. Neither can be skipped safely, so each is treated as the control plane
/// going away: reading stops, and the unit ends as it does when the input closes.
fn unreadable(error: &ReadError) -> Option<String> {
    match error {
        ReadError::InvalidUtf8 { .. } => Some("a line from the control plane is not UTF-8".into()),
        ReadError::LineTooLong { limit } => Some(format!(
            "a line from the control plane is longer than {limit} bytes"
        )),
        ReadError::Eof | ReadError::Io(_) | ReadError::Malformed { .. } => None,
    }
}

/// A transport over a byte stream in each direction.
///
/// The input is read on its own thread into an unbounded queue, from the moment the transport
/// exists. So the peer can always finish a write to this process, even while this process is
/// itself blocked writing to a full output pipe: the two sides can never each be waiting for
/// the other to read.
pub struct StdioTransport<W: Write> {
    inbound: Receiver<Inbound>,
    out: W,
}

impl StdioTransport<Stdout> {
    /// The process's own stdin and stdout.
    pub fn stdio() -> Self {
        Self::over(std::io::stdin(), std::io::stdout())
    }
}

impl<W: Write> StdioTransport<W> {
    pub fn over<R: Read + Send + 'static>(input: R, out: W) -> Self {
        let (queue, inbound) = mpsc::channel();
        std::thread::spawn(move || {
            let mut reader = BufReader::new(input);
            loop {
                let item = match read_message(&mut reader) {
                    Ok(message) => Inbound::Message(message),
                    Err(ReadError::Malformed { line, .. }) => Inbound::Malformed(line),
                    Err(error) => {
                        if let Some(why) = unreadable(&error) {
                            eprintln!("speaker: {why}; reading stops here and the unit ends");
                        }
                        break;
                    }
                };
                if queue.send(item).is_err() {
                    break;
                }
            }
        });
        StdioTransport { inbound, out }
    }
}

impl<W: Write> Transport for StdioTransport<W> {
    fn send(&mut self, message: &RpcMessage) -> Result<(), Closed> {
        write_message(&mut self.out, message).map_err(|_| Closed)
    }

    fn recv(&mut self, wait: Option<Duration>) -> Recv {
        match wait {
            None => self.inbound.recv().map_or(Recv::Closed, Recv::from),
            Some(wait) if wait.is_zero() => match self.inbound.try_recv() {
                Ok(inbound) => inbound.into(),
                Err(TryRecvError::Empty) => Recv::Idle,
                Err(TryRecvError::Disconnected) => Recv::Closed,
            },
            Some(wait) => match self.inbound.recv_timeout(wait) {
                Ok(inbound) => inbound.into(),
                Err(RecvTimeoutError::Timeout) => Recv::Idle,
                Err(RecvTimeoutError::Disconnected) => Recv::Closed,
            },
        }
    }
}
```

- [ ] **Step 4: Run the tests**

Run: `cargo test -p speaker --lib`

Expected: `test result: ok. 8 passed`.

- [ ] **Step 5: Commit**

```bash
git add crates/speaker/src/lib.rs crates/speaker/src/transport.rs
git commit -m "feat(speaker): a transport seam, and stdio read on its own thread"
```

### Task 6: The handshake, the unit, and a scripted control plane

**Files:**
- Create: `crates/speaker/src/unit.rs`, `crates/speaker/tests/contract_speaker.rs`
- Modify: `crates/speaker/src/testkit.rs`, `crates/speaker/src/lib.rs`, `forms/contract.lock.json`

**Interfaces:**
- Consumes: `speaker::{Transport, Recv, Closed}`; the wire types of `harness-protocol`.
- Produces, in `speaker`:
  - `pub struct Identity { pub info: HarnessInfo, pub capabilities: Capabilities }`
  - `pub enum OpenError { Closed, Interrupted, VersionRefused { offered: Vec<String> }, Protocol(String) }`, which implements `Display`
  - `pub fn open<T: Transport>(transport: T, identity: &Identity) -> Result<(Unit<T>, WorkOrder), OpenError>`
  - `pub enum Stopped { Halt, Abandon, Closed }`
  - `pub struct Unit<T: Transport>` with
    `event(&mut self, event: &UnitEvent) -> Result<(), Stopped>`,
    `observe(&mut self, observation: Observation) -> Result<(), Stopped>`,
    `stage(&mut self, stage: Stage, status: StageStatus, detail: Option<String>) -> Result<(), Stopped>`,
    `checkpoint(&mut self, pause: Duration) -> Result<(), Stopped>`,
    `gate(&mut self, request: &GateRequest) -> Result<bool, Stopped>`,
    `finish(self, result: &UnitResult) -> Result<(), Stopped>`
- Produces, in `speaker::testkit` (feature `testkit`):
  - `pub struct ScriptedPeer` (implements `Transport`, `Clone`, `Default`) with `new()`, `starting(order: serde_json::Value)`, `then(self, message: RpcMessage)`, `react(self, reaction)`, `answer_gates(self, approved: bool)`, `interrupt_when(self, request: &'static str, when)`, `close_when(self, when)`, `sent(&self) -> Vec<RpcMessage>`, `events(&self) -> Vec<UnitEvent>`, `result(&self) -> Option<UnitResult>`, `story(&self) -> Vec<String>`
  - `pub fn initialize(version: &str) -> RpcMessage`, `pub fn start(order: Value) -> RpcMessage`, `pub fn order_v01(tier: &str, min_review_rounds: u32) -> Value`, `pub fn stage_started(stage: Stage) -> impl Fn(&RpcMessage) -> bool`, `pub fn gate_requested(message: &RpcMessage) -> bool`

The tests of this task are the **locked contract tests** of `forms/speaker.md`: each test name
starts with the invariant it guards.

- [ ] **Step 1: Write the failing tests**

Create `crates/speaker/tests/contract_speaker.rs`:

```rust
//! Locked contract tests for `forms/speaker.md`. Each test names the invariant it guards.
//! This file is hash-frozen in `forms/contract.lock.json`: change it only with the owner's
//! review, then re-lock with `cargo xtask lock accept`.

use harness_protocol::{
    error_code, method, Capabilities, Delivery, Empty, GateKind, GateReply, GateRequest,
    HarnessInfo, InitializeParams, InitializeResult, Isolation, LogStream, MessageKind, Metering,
    Observation, Outcome, RpcMessage, Stage, Tier, UnitEvent, UnitResult, PROTOCOL_VERSION,
};
use serde_json::json;
use speaker::testkit::{gate_requested, initialize, order_v01, start, ScriptedPeer};
use speaker::{open, Identity, OpenError, Stopped};
use std::time::Duration;

fn identity() -> Identity {
    Identity {
        info: HarnessInfo {
            name: "contract-test".into(),
            version: "0.0.0".into(),
        },
        capabilities: Capabilities {
            isolation: Isolation::None,
            metering: Metering::None,
            gates: vec![GateKind::Oracle],
            delivery: Delivery::Bundle,
            resume: true,
            halt: true,
            holdouts: false,
            controls: vec![],
            network: None,
            profiles: vec![],
            kinds: vec![],
            presets: vec![],
        },
    }
}

fn log(line: &str) -> UnitEvent {
    UnitEvent::Log {
        stream: LogStream::System,
        line: line.into(),
    }
}

fn failed() -> UnitResult {
    UnitResult {
        outcome: Outcome::Failed,
        evidence: None,
        failure: Some(harness_protocol::Failure {
            scope: harness_protocol::ErrorScope::Harness,
            detail: "contract test".into(),
        }),
        stop: None,
    }
}

fn gate() -> GateRequest {
    GateRequest::Oracle {
        test_files: vec!["tests/a.rs".into()],
        hash: "h".into(),
        summary: "one test".into(),
        holdout_files: vec![],
        holdout_hash: None,
    }
}

fn error_code_of(message: &RpcMessage) -> Option<i64> {
    match message.kind() {
        MessageKind::ErrorResponse { error, .. } => Some(error.code),
        _ => None,
    }
}

// I1 ---------------------------------------------------------------------------------------

#[test]
fn i1_the_handshake_answers_initialize_with_this_version_and_the_given_identity() {
    let peer = ScriptedPeer::starting(order_v01("t1", 1));
    let (_unit, order) = open(peer.clone(), &identity()).unwrap();
    assert_eq!(order.unit_id, "unit-1");
    let sent = peer.sent();
    let hello: InitializeResult = sent[0].result_as().unwrap();
    assert_eq!(hello.protocol_version, PROTOCOL_VERSION);
    assert_eq!(hello.harness.name, "contract-test");
    assert_eq!(hello.capabilities, identity().capabilities);
    assert_eq!(sent[1].kind(), MessageKind::Response { id: 2 });
    assert_eq!(sent.len(), 2);
}

#[test]
fn i1_a_version_this_harness_does_not_speak_is_refused_with_minus_32001() {
    for offered in ["99.0", "0.1", "not-a-version"] {
        let peer = ScriptedPeer::new().then(initialize(offered));
        let refused = open(peer.clone(), &identity()).err().unwrap();
        assert_eq!(
            refused,
            OpenError::VersionRefused {
                offered: vec![offered.to_string()]
            }
        );
        let sent = peer.sent();
        assert_eq!(sent.len(), 1, "nothing but the refusal is sent");
        assert_eq!(
            error_code_of(&sent[0]),
            Some(error_code::PROTOCOL_VERSION_UNSUPPORTED)
        );
    }
}

#[test]
fn i1_any_accepted_version_that_matches_is_enough() {
    let offer = RpcMessage::request(
        1,
        method::INITIALIZE,
        &InitializeParams {
            protocol_version: "0.9".into(),
            accepted_versions: vec!["0.9".into(), PROTOCOL_VERSION.into()],
        },
    );
    let peer = ScriptedPeer::new()
        .then(offer)
        .then(start(order_v01("t1", 1)));
    assert!(open(peer, &identity()).is_ok());
}

// I2 ---------------------------------------------------------------------------------------

#[test]
fn i2_a_work_order_in_the_0_1_shape_is_accepted() {
    let order = order_v01("t2", 3);
    assert!(order.get("spec").is_none() && order.get("config").is_none());
    let (_unit, parsed) = open(ScriptedPeer::starting(order), &identity()).unwrap();
    assert_eq!(parsed.tier, Tier::T2);
    assert_eq!(parsed.caps.min_review_rounds, 3);
    assert!(parsed.spec.is_none() && parsed.source.is_none() && parsed.scope.is_none());
    assert!(parsed.config.is_none() && parsed.resume.is_none());
    assert!(parsed.scope_grants.is_empty() && parsed.expected_red.is_empty());
}

#[test]
fn i2_a_work_order_that_is_not_one_is_refused_with_invalid_params() {
    let peer = ScriptedPeer::starting(json!({ "unit_id": "u" }));
    let refused = open(peer.clone(), &identity()).err().unwrap();
    assert!(matches!(refused, OpenError::Protocol(why) if why.starts_with("unit/start params")));
    assert_eq!(
        error_code_of(peer.sent().last().unwrap()),
        Some(error_code::INVALID_PARAMS)
    );
}

// I3 ---------------------------------------------------------------------------------------

#[test]
fn i3_an_input_that_closes_before_a_unit_starts_is_an_orderly_end() {
    let nothing = ScriptedPeer::new();
    assert_eq!(open(nothing, &identity()).err(), Some(OpenError::Closed));
    let probe = ScriptedPeer::new().then(initialize(PROTOCOL_VERSION));
    assert_eq!(
        open(probe.clone(), &identity()).err(),
        Some(OpenError::Closed)
    );
    assert_eq!(
        probe.sent().len(),
        1,
        "the probe still got its initialize reply"
    );
}

#[test]
fn i3_an_interrupt_before_unit_start_is_answered_and_ends_the_handshake() {
    let peer = ScriptedPeer::new()
        .then(initialize(PROTOCOL_VERSION))
        .then(RpcMessage::request(5, method::UNIT_ABANDON, &Empty {}));
    assert_eq!(
        open(peer.clone(), &identity()).err(),
        Some(OpenError::Interrupted)
    );
    assert_eq!(peer.sent()[1].kind(), MessageKind::Response { id: 5 });
}

#[test]
fn i3_anything_but_initialize_first_is_refused() {
    let peer = ScriptedPeer::new().then(start(order_v01("t1", 1)));
    assert!(matches!(
        open(peer.clone(), &identity()).err(),
        Some(OpenError::Protocol(_))
    ));
    assert_eq!(
        error_code_of(&peer.sent()[0]),
        Some(error_code::METHOD_NOT_FOUND)
    );
}

// I4 ---------------------------------------------------------------------------------------

#[test]
fn i4_halt_and_abandon_are_answered_and_then_nothing_more_is_written() {
    for (request, expected) in [
        (method::UNIT_HALT, Stopped::Halt),
        (method::UNIT_ABANDON, Stopped::Abandon),
    ] {
        let peer = ScriptedPeer::starting(order_v01("t1", 1));
        let (mut unit, _) = open(peer.clone(), &identity()).unwrap();
        unit.event(&log("before")).unwrap();
        let peer = peer.then(RpcMessage::request(7, request, &Empty {}));
        assert_eq!(unit.checkpoint(Duration::ZERO), Err(expected));
        let written = peer.sent().len();
        assert_eq!(
            peer.sent().last().unwrap().kind(),
            MessageKind::Response { id: 7 }
        );

        assert_eq!(unit.event(&log("after")), Err(expected));
        assert_eq!(unit.observe(Observation::BuildFinished), Err(expected));
        assert_eq!(unit.checkpoint(Duration::ZERO), Err(expected));
        assert_eq!(unit.gate(&gate()), Err(expected));
        assert_eq!(unit.finish(&failed()), Err(expected));
        assert_eq!(
            peer.sent().len(),
            written,
            "nothing after the acknowledgement"
        );
        assert!(peer.result().is_none());
    }
}

#[test]
fn i4_an_interrupt_is_answered_while_a_gate_is_pending() {
    let peer = ScriptedPeer::starting(order_v01("t2", 1))
        .interrupt_when(method::UNIT_HALT, gate_requested);
    let (mut unit, _) = open(peer.clone(), &identity()).unwrap();
    assert_eq!(unit.gate(&gate()), Err(Stopped::Halt));
    assert_eq!(
        peer.sent().last().unwrap().kind(),
        MessageKind::Response { id: 900 }
    );
    assert_eq!(unit.finish(&failed()), Err(Stopped::Halt));
    assert!(peer.result().is_none());
}

// I5 ---------------------------------------------------------------------------------------

#[test]
fn i5_only_an_unedited_approval_of_this_request_approves_a_gate() {
    fn reply_with(reply: serde_json::Value) -> bool {
        let peer = ScriptedPeer::starting(order_v01("t2", 1)).react(move |sent| {
            let MessageKind::Request { id, method: m } = sent.kind() else {
                return None;
            };
            (m == method::GATE_REQUEST).then(|| RpcMessage::response(id, &reply))
        });
        let (mut unit, _) = open(peer, &identity()).unwrap();
        unit.gate(&gate()).unwrap()
    }
    assert!(reply_with(json!({ "approved": true })));
    assert!(!reply_with(json!({ "approved": false })));
    assert!(!reply_with(
        json!({ "approved": true, "edited_test_files": ["tests/a.rs"] })
    ));
    assert!(!reply_with(json!({ "verdict": "fine" })));
}

#[test]
fn i5_an_error_reply_rejects_and_a_reply_to_another_id_is_not_an_answer() {
    let peer = ScriptedPeer::starting(order_v01("t2", 1)).react(|sent| {
        let MessageKind::Request { id, method: m } = sent.kind() else {
            return None;
        };
        (m == method::GATE_REQUEST).then(|| RpcMessage::error(id, -32000, "no"))
    });
    let (mut unit, _) = open(peer, &identity()).unwrap();
    assert_eq!(unit.gate(&gate()), Ok(false));

    let stray = RpcMessage::response(
        4242,
        &GateReply {
            approved: true,
            edited_test_files: None,
        },
    );
    let peer = ScriptedPeer::starting(order_v01("t2", 1)).then(stray);
    let (mut unit, _) = open(peer, &identity()).unwrap();
    assert_eq!(
        unit.gate(&gate()),
        Err(Stopped::Closed),
        "the stray approval was not taken as the answer"
    );
}

// I6 ---------------------------------------------------------------------------------------

#[test]
fn i6_a_closed_input_stops_the_unit_and_stays_stopped() {
    let peer = ScriptedPeer::starting(order_v01("t1", 1))
        .close_when(|sent| matches!(sent.params_as::<UnitEvent>(), Ok(UnitEvent::Log { .. })));
    let (mut unit, _) = open(peer.clone(), &identity()).unwrap();
    unit.event(&log("the peer closes on seeing this")).unwrap();
    assert_eq!(unit.checkpoint(Duration::ZERO), Err(Stopped::Closed));
    assert_eq!(
        unit.stage(Stage::Red, harness_protocol::StageStatus::Started, None),
        Err(Stopped::Closed)
    );
    assert_eq!(unit.finish(&failed()), Err(Stopped::Closed));
    assert!(peer.result().is_none());
}

// I7 ---------------------------------------------------------------------------------------

#[test]
fn i7_other_requests_are_answered_and_do_not_stop_the_unit() {
    let peer = ScriptedPeer::starting(order_v01("t1", 1));
    let (mut unit, _) = open(peer.clone(), &identity()).unwrap();
    let peer = peer
        .then(RpcMessage::request(8, method::UNIT_RESUME, &Empty {}))
        .then(RpcMessage::request(9, "unit/whatever", &Empty {}))
        .then(RpcMessage::notification("unit/noise", &Empty {}))
        .then(RpcMessage::response(77, &Empty {}));
    assert_eq!(unit.checkpoint(Duration::ZERO), Ok(()));
    let sent = peer.sent();
    assert_eq!(sent[2].kind(), MessageKind::Response { id: 8 });
    assert_eq!(error_code_of(&sent[3]), Some(error_code::METHOD_NOT_FOUND));
    assert_eq!(
        sent.len(),
        4,
        "a notification and a stray response get no answer"
    );
    assert_eq!(unit.finish(&failed()), Ok(()));
    assert_eq!(peer.result().unwrap().outcome, Outcome::Failed);
}
```

- [ ] **Step 2: Run them and watch them fail**

Run: `cargo test -p speaker --features testkit --test contract_speaker`

Expected: it does not compile: `unresolved imports` of `speaker::testkit::ScriptedPeer`,
`speaker::open`, `speaker::Identity`, `speaker::OpenError` and `speaker::Stopped`.

- [ ] **Step 3: Write the scripted control plane**

Replace `crates/speaker/src/testkit.rs` with:

```rust
//! A scripted control plane, for tests of anything that speaks through a [`Transport`].
//!
//! `ScriptedPeer` holds a queue of inbound messages and a list of reactions. Each time the
//! harness sends a message, every reaction sees it and may queue a reply, so a test can say
//! "approve any gate" or "halt as soon as Green starts" without threads, sleeps or timing.

use crate::transport::{Closed, Recv, Transport};
use harness_protocol::{
    method, Empty, GateReply, InitializeParams, MessageKind, Observation, RpcMessage, Stage,
    StageStatus, UnitEvent, UnitResult, PROTOCOL_VERSION,
};
use serde_json::{json, Value};
use std::cell::RefCell;
use std::collections::VecDeque;
use std::rc::Rc;
use std::time::Duration;

type Reaction = Box<dyn FnMut(&RpcMessage) -> Option<RpcMessage>>;
type Trigger = Box<dyn Fn(&RpcMessage) -> bool>;

#[derive(Default)]
struct Inner {
    inbound: VecDeque<RpcMessage>,
    sent: Vec<RpcMessage>,
    reactions: Vec<Reaction>,
    close_when: Option<Trigger>,
    closed: bool,
}

/// A clonable handle: give one clone to the code under test, keep one to read what was sent.
#[derive(Clone, Default)]
pub struct ScriptedPeer {
    inner: Rc<RefCell<Inner>>,
}

impl ScriptedPeer {
    pub fn new() -> Self {
        Self::default()
    }

    /// A peer that has already sent `initialize` (at this crate's protocol version) and
    /// `unit/start` with `order`.
    pub fn starting(order: Value) -> Self {
        Self::new()
            .then(initialize(PROTOCOL_VERSION))
            .then(start(order))
    }

    /// Queue an inbound message.
    pub fn then(self, message: RpcMessage) -> Self {
        self.inner.borrow_mut().inbound.push_back(message);
        self
    }

    /// React to every message the harness sends.
    pub fn react(self, reaction: impl FnMut(&RpcMessage) -> Option<RpcMessage> + 'static) -> Self {
        self.inner.borrow_mut().reactions.push(Box::new(reaction));
        self
    }

    /// Answer every `gate/request` with this verdict.
    pub fn answer_gates(self, approved: bool) -> Self {
        self.react(move |sent| match sent.kind() {
            MessageKind::Request { id, method: m } if m == method::GATE_REQUEST => {
                Some(RpcMessage::response(
                    id,
                    &GateReply {
                        approved,
                        edited_test_files: None,
                    },
                ))
            }
            _ => None,
        })
    }

    /// Send `request` (`unit/halt` or `unit/abandon`) the first time the harness sends a
    /// message `when` accepts.
    pub fn interrupt_when(
        self,
        request: &'static str,
        when: impl Fn(&RpcMessage) -> bool + 'static,
    ) -> Self {
        let mut fired = false;
        self.react(move |sent| {
            if fired || !when(sent) {
                return None;
            }
            fired = true;
            Some(RpcMessage::request(900, request, &Empty {}))
        })
    }

    /// Close the input the first time the harness sends a message `when` accepts.
    pub fn close_when(self, when: impl Fn(&RpcMessage) -> bool + 'static) -> Self {
        self.inner.borrow_mut().close_when = Some(Box::new(when));
        self
    }

    /// Every message the harness has sent, in order.
    pub fn sent(&self) -> Vec<RpcMessage> {
        self.inner.borrow().sent.clone()
    }

    /// Every `unit/event` the harness has sent, in order.
    pub fn events(&self) -> Vec<UnitEvent> {
        self.sent()
            .iter()
            .filter(|m| m.method.as_deref() == Some(method::UNIT_EVENT))
            .map(|m| m.params_as().expect("a unit/event carries a UnitEvent"))
            .collect()
    }

    /// The `unit/result`, if one was sent.
    pub fn result(&self) -> Option<UnitResult> {
        self.sent()
            .iter()
            .find(|m| m.method.as_deref() == Some(method::UNIT_RESULT))
            .map(|m| m.params_as().expect("a unit/result carries a UnitResult"))
    }

    /// The events as short words, for whole-transcript assertions: `provisioned`,
    /// `red:started`, `oracle_frozen`, `review_finished(1,0)`, and so on. Logs are left out.
    pub fn story(&self) -> Vec<String> {
        self.sent().iter().filter_map(word).collect()
    }
}

fn stage_word(stage: Stage) -> String {
    serde_json::to_value(stage)
        .ok()
        .and_then(|v| v.as_str().map(str::to_string))
        .unwrap_or_default()
}

fn word(message: &RpcMessage) -> Option<String> {
    match message.kind() {
        MessageKind::Request { method: m, .. } if m == method::GATE_REQUEST => {
            Some("gate/request".into())
        }
        MessageKind::Notification { method: m } if m == method::UNIT_RESULT => {
            let result: UnitResult = message.params_as().ok()?;
            let outcome = serde_json::to_value(result.outcome).ok()?;
            Some(format!("result:{}", outcome.as_str()?))
        }
        MessageKind::Notification { method: m } if m == method::UNIT_EVENT => {
            match message.params_as().ok()? {
                UnitEvent::Stage { stage, status, .. } => {
                    let status = match status {
                        StageStatus::Started => "started",
                        StageStatus::Finished => "finished",
                    };
                    Some(format!("{}:{status}", stage_word(stage)))
                }
                UnitEvent::Observed { observation } => Some(match observation {
                    Observation::Provisioned => "provisioned".into(),
                    Observation::OracleFrozen { .. } => "oracle_frozen".into(),
                    Observation::BuildFinished => "build_finished".into(),
                    Observation::ChecksPassed => "checks_passed".into(),
                    Observation::ChecksFailed => "checks_failed".into(),
                    Observation::EmptyDiff => "empty_diff".into(),
                    Observation::ReviewFinished {
                        round,
                        unresolved_blockers,
                        ..
                    } => format!("review_finished({round},{unresolved_blockers})"),
                }),
                _ => None,
            }
        }
        _ => None,
    }
}

impl Transport for ScriptedPeer {
    fn send(&mut self, message: &RpcMessage) -> Result<(), Closed> {
        let mut inner = self.inner.borrow_mut();
        if inner.closed {
            return Err(Closed);
        }
        inner.sent.push(message.clone());
        let mut replies = Vec::new();
        for reaction in inner.reactions.iter_mut() {
            replies.extend(reaction(message));
        }
        inner.inbound.extend(replies);
        if inner.close_when.as_ref().is_some_and(|when| when(message)) {
            inner.closed = true;
            inner.inbound.clear();
        }
        Ok(())
    }

    /// Never waits: a script has no clock. With nothing queued, a bounded wait is `Idle` and an
    /// unbounded one is `Closed`, because a script that has run out can never send again.
    fn recv(&mut self, wait: Option<Duration>) -> Recv {
        let mut inner = self.inner.borrow_mut();
        match inner.inbound.pop_front() {
            Some(message) => Recv::Message(message),
            None if inner.closed || wait.is_none() => Recv::Closed,
            None => Recv::Idle,
        }
    }
}

/// An `initialize` request that offers one protocol version.
pub fn initialize(version: &str) -> RpcMessage {
    RpcMessage::request(
        1,
        method::INITIALIZE,
        &InitializeParams {
            protocol_version: version.into(),
            accepted_versions: Vec::new(),
        },
    )
}

/// A `unit/start` request carrying `order`.
pub fn start(order: Value) -> RpcMessage {
    RpcMessage::request(2, method::UNIT_START, &order)
}

/// A work order in the 0.1 shape: only the fields every protocol version has. `tier` is `t1`,
/// `t2` or `t3`.
pub fn order_v01(tier: &str, min_review_rounds: u32) -> Value {
    json!({
        "unit_id": "unit-1",
        "work_item": { "kind": "issue", "ref": "example/repo#1" },
        "tier": tier,
        "task": "A scripted unit. It touches no repository.",
        "repo": {
            "url": "https://example.invalid/repo.git",
            "slug": "example/repo",
            "base_branch": "main"
        },
        "branch": "agent/unit-1",
        "test_cmd": "true",
        "caps": { "usd": 1.0, "wall_clock_secs": 60, "min_review_rounds": min_review_rounds }
    })
}

/// True for the `stage` event that marks `stage` as started.
pub fn stage_started(stage: Stage) -> impl Fn(&RpcMessage) -> bool {
    move |message| {
        matches!(
            message.params_as::<UnitEvent>(),
            Ok(UnitEvent::Stage { stage: s, status: StageStatus::Started, .. }) if s == stage
        ) && message.method.as_deref() == Some(method::UNIT_EVENT)
    }
}

/// True for a `gate/request`.
pub fn gate_requested(message: &RpcMessage) -> bool {
    message.method.as_deref() == Some(method::GATE_REQUEST)
}
```

- [ ] **Step 4: Write the handshake and the unit**

Create `crates/speaker/src/unit.rs`:

```rust
//! The handshake, and the conversation about one unit.

use crate::transport::{Recv, Transport};
use harness_protocol::{
    error_code, method, negotiate, Capabilities, Empty, GateReply, GateRequest, HarnessInfo,
    InitializeParams, InitializeResult, MessageKind, Observation, RpcMessage, Stage, StageStatus,
    UnitEvent, UnitResult, WorkOrder, PROTOCOL_VERSION,
};
use std::time::Duration;

/// The first id this side uses for its own requests. The control plane numbers its requests
/// from 1; starting high keeps the two sequences visibly apart in a transcript.
const FIRST_REQUEST_ID: u64 = 1_000;

/// What this harness says about itself at `initialize`.
#[derive(Debug, Clone, PartialEq)]
pub struct Identity {
    pub info: HarnessInfo,
    pub capabilities: Capabilities,
}

/// Why the handshake did not produce a unit.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum OpenError {
    /// The input closed before a unit started. An orderly shutdown, not a fault.
    Closed,
    /// The control plane withdrew before a unit started (`unit/halt` or `unit/abandon`).
    Interrupted,
    /// The control plane accepts no protocol version this harness speaks.
    VersionRefused { offered: Vec<String> },
    /// The control plane broke the handshake.
    Protocol(String),
}

impl std::fmt::Display for OpenError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            OpenError::Closed => write!(f, "the input closed before a unit started"),
            OpenError::Interrupted => write!(f, "interrupted before a unit started"),
            OpenError::VersionRefused { offered } => write!(
                f,
                "the control plane offered protocol {offered:?}; this harness speaks {PROTOCOL_VERSION}"
            ),
            OpenError::Protocol(what) => write!(f, "handshake: {what}"),
        }
    }
}

/// Why a unit can send nothing more. Once a call returns one of these, every later call on the
/// same [`Unit`] returns the same one and writes nothing.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Stopped {
    /// `unit/halt` was received and answered.
    Halt,
    /// `unit/abandon` was received and answered.
    Abandon,
    /// The control plane closed its end, or sent a line that cannot be read.
    Closed,
}

fn next_request<T: Transport>(transport: &mut T) -> Result<RpcMessage, OpenError> {
    match transport.recv(None) {
        Recv::Message(message) => Ok(message),
        Recv::Malformed(line) => Err(OpenError::Protocol(format!("not a message: {line}"))),
        Recv::Idle | Recv::Closed => Err(OpenError::Closed),
    }
}

fn refuse<T: Transport>(transport: &mut T, id: u64, code: i64, why: &str) -> OpenError {
    let _ = transport.send(&RpcMessage::error(id, code, why));
    OpenError::Protocol(why.to_string())
}

/// Perform the handshake: answer `initialize`, then acknowledge `unit/start`.
///
/// A work order in the 0.1 shape, with none of the fields 0.2 added, is accepted: every added
/// field is optional on the wire.
pub fn open<T: Transport>(
    mut transport: T,
    identity: &Identity,
) -> Result<(Unit<T>, WorkOrder), OpenError> {
    let first = next_request(&mut transport)?;
    let id = match first.kind() {
        MessageKind::Request { id, method: m } if m == method::INITIALIZE => id,
        MessageKind::Request { id, .. } => {
            let code = error_code::METHOD_NOT_FOUND;
            return Err(refuse(&mut transport, id, code, "expected initialize"));
        }
        _ => return Err(OpenError::Protocol("expected an initialize request".into())),
    };
    let params: InitializeParams = match first.params_as() {
        Ok(params) => params,
        Err(e) => {
            let why = format!("initialize params: {e}");
            return Err(refuse(&mut transport, id, error_code::INVALID_PARAMS, &why));
        }
    };
    let offered = if params.accepted_versions.is_empty() {
        vec![params.protocol_version]
    } else {
        params.accepted_versions
    };
    let accepted: Vec<&str> = offered.iter().map(String::as_str).collect();
    if !negotiate(&accepted, PROTOCOL_VERSION) {
        let why = format!("this harness speaks protocol {PROTOCOL_VERSION}");
        let _ = transport.send(&RpcMessage::error(
            id,
            error_code::PROTOCOL_VERSION_UNSUPPORTED,
            why,
        ));
        return Err(OpenError::VersionRefused { offered });
    }
    let hello = InitializeResult {
        protocol_version: PROTOCOL_VERSION.into(),
        harness: identity.info.clone(),
        capabilities: identity.capabilities.clone(),
    };
    transport
        .send(&RpcMessage::response(id, &hello))
        .map_err(|_| OpenError::Closed)?;

    loop {
        let message = next_request(&mut transport)?;
        match message.kind() {
            MessageKind::Request { id, method: m } if m == method::UNIT_START => {
                let order: WorkOrder = match message.params_as() {
                    Ok(order) => order,
                    Err(e) => {
                        let why = format!("unit/start params: {e}");
                        return Err(refuse(&mut transport, id, error_code::INVALID_PARAMS, &why));
                    }
                };
                transport
                    .send(&RpcMessage::response(id, &Empty {}))
                    .map_err(|_| OpenError::Closed)?;
                let unit = Unit {
                    transport,
                    stopped: None,
                    next_id: FIRST_REQUEST_ID,
                };
                return Ok((unit, order));
            }
            MessageKind::Request { id, method: m }
                if m == method::UNIT_HALT || m == method::UNIT_ABANDON =>
            {
                let _ = transport.send(&RpcMessage::response(id, &Empty {}));
                return Err(OpenError::Interrupted);
            }
            MessageKind::Request { id, .. } => {
                let code = error_code::METHOD_NOT_FOUND;
                return Err(refuse(&mut transport, id, code, "expected unit/start"));
            }
            // A stray response or notification before the unit starts is not ours to answer.
            _ => {}
        }
    }
}

/// One unit's side of the conversation, from the `unit/start` acknowledgement to the result.
pub struct Unit<T: Transport> {
    transport: T,
    stopped: Option<Stopped>,
    next_id: u64,
}

impl<T: Transport> Unit<T> {
    fn live(&self) -> Result<(), Stopped> {
        self.stopped.map_or(Ok(()), Err)
    }

    fn stop(&mut self, why: Stopped) -> Stopped {
        *self.stopped.get_or_insert(why)
    }

    fn send(&mut self, message: &RpcMessage) -> Result<(), Stopped> {
        self.live()?;
        self.transport
            .send(message)
            .map_err(|_| self.stop(Stopped::Closed))
    }

    /// Answer one inbound message from the control plane.
    fn control(&mut self, message: &RpcMessage) -> Result<(), Stopped> {
        let MessageKind::Request { id, method: m } = message.kind() else {
            // A response to nothing we asked, or a notification: not ours to answer.
            return Ok(());
        };
        if m == method::UNIT_HALT || m == method::UNIT_ABANDON {
            let why = if m == method::UNIT_HALT {
                Stopped::Halt
            } else {
                Stopped::Abandon
            };
            let _ = self.transport.send(&RpcMessage::response(id, &Empty {}));
            return Err(self.stop(why));
        }
        if m == method::UNIT_RESUME {
            // Resume is a respawn in this protocol version; the request is only acknowledged.
            return self.send(&RpcMessage::response(id, &Empty {}));
        }
        let unknown = format!("{m} is not a request this harness accepts");
        self.send(&RpcMessage::error(
            id,
            error_code::METHOD_NOT_FOUND,
            unknown,
        ))
    }

    /// Send one `unit/event`.
    pub fn event(&mut self, event: &UnitEvent) -> Result<(), Stopped> {
        self.send(&RpcMessage::notification(method::UNIT_EVENT, event))
    }

    /// Send one observation: an event the control plane's state machine acts on.
    pub fn observe(&mut self, observation: Observation) -> Result<(), Stopped> {
        self.event(&UnitEvent::Observed { observation })
    }

    /// Send one `stage` event: informational, and it counts as activity.
    pub fn stage(
        &mut self,
        stage: Stage,
        status: StageStatus,
        detail: Option<String>,
    ) -> Result<(), Stopped> {
        self.event(&UnitEvent::Stage {
            stage,
            status,
            detail,
        })
    }

    /// Give the control plane its turn. Waits up to `pause` for an inbound message, then answers
    /// everything that has arrived. A unit calls this between stages; it is the only place,
    /// besides [`Unit::gate`], where `unit/halt` and `unit/abandon` are noticed.
    pub fn checkpoint(&mut self, pause: Duration) -> Result<(), Stopped> {
        self.live()?;
        let mut wait = pause;
        loop {
            match self.transport.recv(Some(wait)) {
                Recv::Idle => return Ok(()),
                Recv::Closed => return Err(self.stop(Stopped::Closed)),
                Recv::Malformed(_) => {}
                Recv::Message(message) => self.control(&message)?,
            }
            wait = Duration::ZERO;
        }
    }

    /// Send `gate/request` and wait for its answer, however long that takes. `Ok(true)` only
    /// for a reply to this request that approves it unchanged; an error reply, an unreadable
    /// reply, a refusal, or an approval that carries edited files are all `Ok(false)`.
    pub fn gate(&mut self, request: &GateRequest) -> Result<bool, Stopped> {
        let id = self.next_id;
        self.next_id += 1;
        self.send(&RpcMessage::request(id, method::GATE_REQUEST, request))?;
        loop {
            let message = match self.transport.recv(None) {
                Recv::Message(message) => message,
                Recv::Malformed(_) => continue,
                Recv::Idle | Recv::Closed => return Err(self.stop(Stopped::Closed)),
            };
            match message.kind() {
                MessageKind::Response { id: answered } if answered == id => {
                    return Ok(message
                        .result_as::<GateReply>()
                        .is_ok_and(|reply| reply.approved && reply.edited_test_files.is_none()));
                }
                MessageKind::ErrorResponse { id: answered, .. } if answered == id => {
                    return Ok(false)
                }
                _ => self.control(&message)?,
            }
        }
    }

    /// Send the unit's one `unit/result`. Consumes the unit, so nothing can follow it.
    pub fn finish(mut self, result: &UnitResult) -> Result<(), Stopped> {
        self.send(&RpcMessage::notification(method::UNIT_RESULT, result))
    }
}
```

Replace `crates/speaker/src/lib.rs` with:

```rust
//! `speaker`: the harness side of the harness protocol, over stdin and stdout.
//!
//! A harness is one process per unit of work. The control plane writes one JSON-RPC message
//! per line to its stdin and reads one per line from its stdout. This crate turns that wire
//! into three things a harness calls:
//!
//! - [`open`] performs the handshake (`initialize`, then `unit/start`) and returns the work
//!   order with a [`Unit`];
//! - [`Unit`] sends events, asks for a gate, notices `unit/halt` and `unit/abandon`, and sends
//!   the one `unit/result`;
//! - [`Transport`] is the seam under both: [`StdioTransport`] for a real process, and
//!   `testkit::ScriptedPeer` for tests.
//!
//! The interface, its invariants and its gates are `forms/speaker.md`.

mod transport;
mod unit;

#[cfg(any(test, feature = "testkit"))]
pub mod testkit;

pub use transport::{Closed, Recv, StdioTransport, Transport};
pub use unit::{open, Identity, OpenError, Stopped, Unit};
```

- [ ] **Step 5: Run the tests**

```bash
cargo test -p speaker --features testkit --test contract_speaker
cargo test -p speaker --lib
```

Expected: `test result: ok. 14 passed`, then `test result: ok. 8 passed`.

- [ ] **Step 6: Lock the contract test**

```bash
cargo xtask lock accept
cargo xtask lock check
```

Expected: `lock: regenerated with 2 contract tests`, listing
`crates/cli/tests/contract_pins.rs` and `crates/speaker/tests/contract_speaker.rs`; then
`lock: OK (2 locked contract tests unchanged)`.

- [ ] **Step 7: Commit**

```bash
git add crates/speaker forms/contract.lock.json
git commit -m "feat(speaker): the handshake, the unit conversation and a scripted peer, with locked contract tests"
```

### Task 7: The driver: one unit over the fakes

**Files:**
- Create: `crates/cli/src/harness.rs`
- Modify: `crates/cli/src/lib.rs` (one line)

**Interfaces:**
- Consumes: `engine::{transition, Action, CheckOutcome, Event, Failure, Finish, Params, State}`;
  `runtime::fake::{Check, FakeRuntime, Scenario, Scripted, TestFile}`;
  `workspace::fake::{repo_path, FakeWorkspace}`;
  `speaker::{open, Identity, OpenError, Stopped, Transport, Unit}`;
  `factory_presets::PRESETS_VERSION`; the wire types of `harness-protocol`.
- Produces, in `cli::harness`:
  - `pub const EXIT_OK: u8 = 0`, `EXIT_INTERNAL: u8 = 1`, `EXIT_USAGE: u8 = 2`, `EXIT_HANDSHAKE: u8 = 3`
  - `pub fn fake_identity() -> Identity`
  - `pub fn drive<T: Transport>(transport: T, scenario: Scenario, root: PathBuf) -> ExitCode`

This is where "Global Constraints", decision 8, becomes code and tests. Read the tests first:
each expected transcript is written as words, and `[red]` stands for the pair `red:started`,
`red:finished`.

- [ ] **Step 1: Write the failing tests**

In `crates/cli/src/lib.rs`, below the line `use std::process::ExitCode;`, add a blank line and
then `pub mod harness;`. Create `crates/cli/src/harness.rs` with only its tests:

```rust
#[cfg(test)]
mod tests {
    use super::*;
    use harness_protocol::monitor::{Inbound, ProtocolMonitor};
    use harness_protocol::{method, InitializeResult, MessageKind, Network, PROTOCOL_VERSION};
    use serde_json::{json, Value};
    use speaker::testkit::{gate_requested, initialize, order_v01, stage_started, ScriptedPeer};
    use workspace::fake::FAKE_HEAD_SHA;

    const OK: ExitCode = ExitCode::SUCCESS;

    fn scenario(text: &str) -> Scenario {
        Scenario::parse(text).unwrap()
    }

    /// Run one unit against a scripted control plane and return its exit code.
    fn run(peer: &ScriptedPeer, text: &str) -> ExitCode {
        drive(peer.clone(), scenario(text), PathBuf::from("fake-root"))
    }

    fn story(peer: &ScriptedPeer) -> Vec<String> {
        peer.story()
    }

    fn pair(stage: &str) -> [String; 2] {
        [format!("{stage}:started"), format!("{stage}:finished")]
    }

    /// Build an expected story from words; `[red]` expands to the stage's started/finished pair.
    fn words(spec: &str) -> Vec<String> {
        spec.split_whitespace()
            .flat_map(|word| match word.strip_prefix('[') {
                Some(stage) => pair(stage.trim_end_matches(']')).to_vec(),
                None => vec![word.to_string()],
            })
            .collect()
    }

    fn freeze_of(peer: &ScriptedPeer) -> OracleFreeze {
        peer.events()
            .into_iter()
            .find_map(|event| match event {
                UnitEvent::Observed {
                    observation: Observation::OracleFrozen { freeze },
                } => freeze,
                _ => None,
            })
            .expect("an oracle_frozen observation with a freeze payload")
    }

    #[test]
    fn a_t1_unit_passes_all_seven_stages_in_order() {
        let peer = ScriptedPeer::starting(order_v01("t1", 1));
        assert_eq!(run(&peer, "{}"), OK);
        assert_eq!(
            story(&peer),
            words(
                "provisioned [provision] [red] oracle_frozen [plan] [green] build_finished \
                 [check] checks_passed [review] review_finished(1,0) [deliver] result:pr_open"
            )
        );
        let last = peer.sent().pop().unwrap();
        assert_eq!(last.method.as_deref(), Some(method::UNIT_RESULT));
    }

    #[test]
    fn initialize_declares_protocol_0_2_and_what_a_fake_can_do() {
        let peer = ScriptedPeer::starting(order_v01("t1", 1));
        run(&peer, "{}");
        let hello: InitializeResult = peer.sent()[0].result_as().unwrap();
        assert_eq!(hello.protocol_version, "0.2");
        assert_eq!(hello.protocol_version, PROTOCOL_VERSION);
        assert_eq!(hello.harness.name, "reqdrive");
        assert_eq!(hello.harness.version, env!("CARGO_PKG_VERSION"));
        let declared = serde_json::to_value(&hello.capabilities).unwrap();
        assert_eq!(declared["isolation"], "none");
        assert_eq!(declared["metering"], "none");
        assert_eq!(declared["gates"], json!(["oracle"]));
        assert_eq!(declared["delivery"], "bundle");
        assert_eq!(declared["resume"], true);
        assert_eq!(declared["halt"], true);
        assert_eq!(declared["holdouts"], true);
        assert_eq!(
            declared["controls"],
            json!([
                "scope",
                "protected",
                "secrets",
                "dependencies",
                "eidos_gates",
                "oracle"
            ])
        );
        assert_eq!(declared["kinds"], json!(["build"]));
        assert_eq!(
            declared["presets"],
            json!([
                { "name": "cargo", "version": PRESETS_VERSION },
                { "name": "node", "version": PRESETS_VERSION }
            ])
        );
        assert_eq!(hello.capabilities.network, None::<Network>);
        assert!(hello.capabilities.profiles.is_empty());
    }

    #[test]
    fn the_freeze_payload_is_sent_at_every_tier_and_hashes_by_the_contract_scheme() {
        for tier in ["t1", "t2", "t3"] {
            let peer = ScriptedPeer::starting(order_v01(tier, 1)).answer_gates(true);
            assert_eq!(run(&peer, "{}"), OK);
            let freeze = freeze_of(&peer);
            assert_eq!(freeze.frozen_files.len(), 1);
            assert_eq!(freeze.frozen_files[0].path, "tests/scripted_ac1.rs");
            assert_eq!(
                freeze.frozen_files[0].sha256,
                file_sha256(b"// A scripted visible test for criterion ac1.\n")
            );
            assert_eq!(freeze.frozen_ids, vec!["scripted_ac1::ac1_holds"]);
            assert_eq!(freeze.holdout_ids, vec!["holdout_ac1::ac1_holds"]);
            assert_eq!(freeze.holdout_hash.as_deref().map(str::len), Some(64));
            assert!(freeze
                .holdout_bundle_path
                .is_some_and(|path| path.ends_with("unit-1.holdouts.tar")));
        }
    }

    #[test]
    fn a_gated_tier_asks_for_the_gate_straight_after_the_freeze_and_waits() {
        for tier in ["t2", "t3"] {
            let peer = ScriptedPeer::starting(order_v01(tier, 1)).answer_gates(true);
            assert_eq!(run(&peer, "{}"), OK);
            assert_eq!(
                story(&peer),
                words(
                    "provisioned [provision] [red] oracle_frozen gate/request [plan] [green] \
                     build_finished [check] checks_passed [review] review_finished(1,0) \
                     [deliver] result:pr_open"
                )
            );
            let freeze = freeze_of(&peer);
            let request = peer.sent().into_iter().find(gate_requested).unwrap();
            let gate: Value = request.params.unwrap();
            assert_eq!(gate["gate"], "oracle");
            assert_eq!(gate["test_files"], json!(["tests/scripted_ac1.rs"]));
            assert_eq!(gate["hash"], json!(bundle_hash(&freeze.frozen_files)));
            assert_eq!(gate["holdout_files"], json!(["tests/holdout_ac1.rs"]));
            assert_eq!(gate["holdout_hash"], json!(freeze.holdout_hash));
        }
    }

    #[test]
    fn an_unanswered_gate_holds_the_unit_before_any_plan() {
        // The script never answers: the wait ends only because the script runs out.
        let peer = ScriptedPeer::starting(order_v01("t2", 1));
        assert_eq!(run(&peer, "{}"), OK);
        assert_eq!(
            story(&peer),
            words("provisioned [provision] [red] oracle_frozen gate/request")
        );
        assert!(peer.result().is_none());
    }

    #[test]
    fn a_rejected_gate_ends_the_unit_failed_and_never_plans() {
        let peer = ScriptedPeer::starting(order_v01("t2", 1)).answer_gates(false);
        assert_eq!(run(&peer, "{}"), OK);
        assert_eq!(
            story(&peer),
            words("provisioned [provision] [red] oracle_frozen gate/request result:failed")
        );
        let result = peer.result().unwrap();
        assert_eq!(result.failure.unwrap().detail, "oracle rejected");
        assert!(result.evidence.is_none() && result.stop.is_none());
    }

    #[test]
    fn the_review_loop_runs_until_the_minimum_rounds_are_met() {
        let peer = ScriptedPeer::starting(order_v01("t1", 3));
        assert_eq!(run(&peer, "{}"), OK);
        let round = "[green] build_finished [check] checks_passed [review]";
        assert_eq!(
            story(&peer),
            words(&format!(
                "provisioned [provision] [red] oracle_frozen [plan] \
                 {round} review_finished(1,0) {round} review_finished(2,0) \
                 {round} review_finished(3,0) [deliver] result:pr_open"
            ))
        );
        assert_eq!(
            peer.result()
                .unwrap()
                .evidence
                .unwrap()
                .review
                .unwrap()
                .rounds,
            3
        );
    }

    #[test]
    fn review_blockers_send_the_unit_round_again() {
        let peer = ScriptedPeer::starting(order_v01("t1", 1));
        assert_eq!(run(&peer, r#"{"reviews": [2, 0]}"#), OK);
        let round = "[green] build_finished [check] checks_passed [review]";
        assert_eq!(
            story(&peer),
            words(&format!(
                "provisioned [provision] [red] oracle_frozen [plan] \
                 {round} review_finished(1,2) {round} review_finished(2,0) \
                 [deliver] result:pr_open"
            ))
        );
    }

    #[test]
    fn a_failed_check_is_followed_by_another_build_and_a_passing_check() {
        let peer = ScriptedPeer::starting(order_v01("t1", 1));
        assert_eq!(run(&peer, r#"{"checks": ["failed", "passed"]}"#), OK);
        assert_eq!(
            story(&peer),
            words(
                "provisioned [provision] [red] oracle_frozen [plan] [green] build_finished \
                 [check] checks_failed [green] build_finished [check] checks_passed \
                 [review] review_finished(1,0) [deliver] result:pr_open"
            )
        );
    }

    #[test]
    fn an_empty_diff_ends_no_change_with_nothing_after_the_observation() {
        let peer = ScriptedPeer::starting(order_v01("t1", 1));
        assert_eq!(run(&peer, r#"{"checks": ["empty_diff"]}"#), OK);
        assert_eq!(
            story(&peer),
            words(
                "provisioned [provision] [red] oracle_frozen [plan] [green] build_finished \
                 [check] empty_diff result:no_change"
            )
        );
        let result = peer.result().unwrap();
        assert_eq!(result.outcome, Outcome::NoChange);
        assert!(result.failure.is_none() && result.stop.is_none());
    }

    #[test]
    fn no_change_carries_evidence_that_names_the_commit_holding_the_frozen_tests() {
        let peer = ScriptedPeer::starting(order_v01("t1", 1));
        assert_eq!(run(&peer, r#"{"checks": ["empty_diff"]}"#), OK);
        let freeze = freeze_of(&peer);
        let evidence = peer
            .result()
            .unwrap()
            .evidence
            .expect("the protocol requires evidence with no_change");
        assert_eq!(evidence.branch, "agent/unit-1");
        assert_eq!(evidence.head_sha, FAKE_HEAD_SHA);
        assert!(matches!(
            &evidence.delivery,
            DeliveryEvidence::Bundle { bundle_path } if bundle_path.ends_with("unit-1.bundle")
        ));
        assert_eq!(
            evidence.oracle_hash,
            Some(bundle_hash(&freeze.frozen_files))
        );
        assert_eq!(
            evidence.test_report.unwrap().ids_passed,
            vec!["scripted_ac1::ac1_holds", "holdout_ac1::ac1_holds"]
        );
        assert!(evidence.controls.is_empty(), "no diff, so no control ran");
        assert_eq!(
            evidence.review, None,
            "nothing was built, so nothing was reviewed"
        );
    }

    /// Everything the harness sent after its `initialize` reply, as judged by the protocol's
    /// own monitor: the one the control plane and the conformance kit use. Panics on the first
    /// message the monitor calls a violation.
    fn monitored(peer: &ScriptedPeer) -> Vec<Inbound> {
        let sent = peer.sent();
        let hello: InitializeResult = sent[0].result_as().unwrap();
        let mut monitor = ProtocolMonitor::new(hello.capabilities, 2);
        sent[1..]
            .iter()
            .map(|message| {
                monitor
                    .on_line(Ok(message.clone()))
                    .unwrap_or_else(|violation| panic!("{violation:?}: {message:?}"))
            })
            .collect()
    }

    #[test]
    fn every_way_a_unit_ends_is_legal_to_the_protocols_own_monitor() {
        let stop = r#"{"stop": {"stage": "check", "reason": "check_unrunnable", "detail": "x"}}"#;
        let fail = r#"{"fail": {"stage": "review", "detail": "x"}}"#;
        let endings = [
            ("t1", true, "{}", Outcome::PrOpen),
            ("t2", true, "{}", Outcome::PrOpen),
            ("t3", false, "{}", Outcome::Failed),
            (
                "t1",
                true,
                r#"{"checks": ["failed", "passed"], "reviews": [1, 0]}"#,
                Outcome::PrOpen,
            ),
            (
                "t1",
                true,
                r#"{"checks": ["empty_diff"]}"#,
                Outcome::NoChange,
            ),
            ("t2", true, stop, Outcome::NeedsHuman),
            ("t1", true, fail, Outcome::Failed),
        ];
        for (tier, approve, scenario, outcome) in endings {
            let peer = ScriptedPeer::starting(order_v01(tier, 1)).answer_gates(approve);
            assert_eq!(run(&peer, scenario), OK);
            let judged = monitored(&peer);
            assert_eq!(
                judged.first(),
                Some(&Inbound::StartAck),
                "unit/start is answered before anything else is sent"
            );
            assert!(
                matches!(judged.last(), Some(Inbound::Result(r)) if r.outcome == outcome),
                "{tier} {scenario} should end {outcome:?}"
            );
        }
    }

    #[test]
    fn a_scripted_stop_ends_needs_human_with_its_reason_and_request() {
        let peer = ScriptedPeer::starting(order_v01("t1", 1));
        let stop = r#"{"stop": {"stage": "green", "reason": "scope_request",
                       "detail": "needs src/b.rs", "request": ["src/b.rs"]}}"#;
        assert_eq!(run(&peer, stop), OK);
        assert_eq!(
            story(&peer),
            words("provisioned [provision] [red] oracle_frozen [plan] [green] result:needs_human")
        );
        let result = peer.result().unwrap();
        assert_eq!(result.outcome, Outcome::NeedsHuman);
        let stop = result.stop.unwrap();
        assert_eq!(stop.reason, StopReason::ScopeRequest);
        assert_eq!(stop.detail, "needs src/b.rs");
        assert_eq!(stop.request, vec!["src/b.rs"]);
        assert!(result.evidence.is_none() && result.failure.is_none());
    }

    #[test]
    fn a_scripted_failure_ends_failed_with_its_detail() {
        let peer = ScriptedPeer::starting(order_v01("t1", 1));
        let fail = r#"{"fail": {"stage": "plan", "detail": "no usable plan"}}"#;
        assert_eq!(run(&peer, fail), OK);
        assert_eq!(
            story(&peer),
            words("provisioned [provision] [red] oracle_frozen [plan] result:failed")
        );
        let failure = peer.result().unwrap().failure.unwrap();
        assert_eq!(failure.detail, "no usable plan");
        assert_eq!(failure.scope, ErrorScope::Agent);
    }

    #[test]
    fn a_resumed_unit_builds_checks_and_reviews_again_without_a_second_freeze() {
        for tier in ["t1", "t2"] {
            let mut order = order_v01(tier, 1);
            order["resume"] = json!({ "oracle_frozen": true });
            let peer = ScriptedPeer::starting(order);
            assert_eq!(run(&peer, "{}"), OK);
            assert_eq!(
                story(&peer),
                words(
                    "provisioned [provision] [green] build_finished [check] checks_passed \
                     [review] review_finished(1,0) [deliver] result:pr_open"
                )
            );
        }
    }

    #[test]
    fn a_resume_that_is_not_frozen_freezes_with_the_same_hashes_as_before() {
        let fresh = ScriptedPeer::starting(order_v01("t2", 1)).answer_gates(true);
        run(&fresh, "{}");
        let mut order = order_v01("t2", 1);
        order["resume"] = json!({ "oracle_frozen": false });
        let again = ScriptedPeer::starting(order).answer_gates(true);
        run(&again, "{}");
        assert_eq!(freeze_of(&again), freeze_of(&fresh));
        assert_eq!(story(&again), story(&fresh));

        let mut order = order_v01("t2", 1);
        order["resume"] = json!({ "oracle_frozen": true });
        let resumed = ScriptedPeer::starting(order);
        run(&resumed, "{}");
        assert_eq!(
            resumed.result().unwrap().evidence.unwrap().oracle_hash,
            fresh.result().unwrap().evidence.unwrap().oracle_hash,
            "a resumed process reports the oracle it was frozen with"
        );
    }

    #[test]
    fn halt_between_stages_is_acknowledged_and_no_result_follows() {
        let peer = ScriptedPeer::starting(order_v01("t1", 1))
            .interrupt_when(method::UNIT_HALT, stage_started(Stage::Plan));
        assert_eq!(run(&peer, "{}"), OK);
        assert_eq!(
            story(&peer),
            words("provisioned [provision] [red] oracle_frozen [plan]")
        );
        let last = peer.sent().pop().unwrap();
        assert_eq!(last.kind(), MessageKind::Response { id: 900 });
        assert!(peer.result().is_none());
    }

    #[test]
    fn abandon_while_the_gate_is_pending_is_acknowledged_and_no_result_follows() {
        let peer = ScriptedPeer::starting(order_v01("t2", 1))
            .interrupt_when(method::UNIT_ABANDON, gate_requested);
        assert_eq!(run(&peer, "{}"), OK);
        let last = peer.sent().pop().unwrap();
        assert_eq!(last.kind(), MessageKind::Response { id: 900 });
        assert!(peer.result().is_none());
    }

    #[test]
    fn an_input_that_closes_mid_unit_ends_the_unit_quietly() {
        let peer =
            ScriptedPeer::starting(order_v01("t1", 1)).close_when(stage_started(Stage::Green));
        assert_eq!(run(&peer, "{}"), OK);
        assert_eq!(
            story(&peer),
            words("provisioned [provision] [red] oracle_frozen [plan] green:started")
        );
        assert!(peer.result().is_none());
    }

    #[test]
    fn an_input_that_closes_before_a_unit_starts_is_not_an_error() {
        assert_eq!(run(&ScriptedPeer::new(), "{}"), OK);
        let probe = ScriptedPeer::new().then(initialize(PROTOCOL_VERSION));
        assert_eq!(run(&probe, "{}"), OK);
        assert_eq!(probe.sent().len(), 1);
    }

    #[test]
    fn a_refused_version_exits_with_the_handshake_code() {
        let peer = ScriptedPeer::new().then(initialize("99.0"));
        assert_eq!(run(&peer, "{}"), ExitCode::from(EXIT_HANDSHAKE));
        assert_eq!(peer.sent().len(), 1);
    }

    #[test]
    fn a_work_order_without_the_0_2_fields_runs_and_claims_no_spec() {
        let order = order_v01("t1", 1);
        for field in [
            "kind", "spec", "source", "scope", "config", "controls", "profile",
        ] {
            assert!(
                order.get(field).is_none(),
                "{field} is absent from a 0.1 order"
            );
        }
        let peer = ScriptedPeer::starting(order);
        assert_eq!(run(&peer, "{}"), OK);
        let evidence = peer.result().unwrap().evidence.unwrap();
        assert_eq!(evidence.spec_hash, None);
        assert_eq!(evidence.map, None);
        assert_eq!(evidence.branch, "agent/unit-1");
        assert_eq!(evidence.test.command, "true");
    }

    #[test]
    fn evidence_carries_the_spec_hash_the_oracle_the_ids_the_controls_and_the_rounds() {
        let mut order = order_v01("t1", 2);
        order["spec"] = json!({
            "id": "SPEC-1", "bytes_path": "spec.md", "signed_hash": "abc123"
        });
        order["kind"] = json!("build");
        let peer = ScriptedPeer::starting(order);
        assert_eq!(run(&peer, "{}"), OK);
        let freeze = freeze_of(&peer);
        let evidence = peer.result().unwrap().evidence.unwrap();
        assert_eq!(evidence.spec_hash.as_deref(), Some("abc123"));
        assert_eq!(
            evidence.oracle_hash,
            Some(bundle_hash(&freeze.frozen_files))
        );
        assert_eq!(evidence.head_sha.len(), 40);
        assert_eq!(
            evidence.test_report.unwrap().ids_passed,
            vec!["scripted_ac1::ac1_holds", "holdout_ac1::ac1_holds"]
        );
        let names: Vec<ControlKind> = evidence.controls.iter().map(|c| c.name).collect();
        assert_eq!(names, CONTROLS);
        assert!(evidence
            .controls
            .iter()
            .all(|c| c.status == ControlStatus::Passed));
        let review = evidence.review.unwrap();
        assert_eq!((review.rounds, review.prior_rounds), (2, 0));
        assert!(evidence.pr.is_none());
    }

    #[test]
    fn a_windows_spelling_of_a_test_path_changes_neither_the_path_nor_a_hash() {
        let unix = r#"{"tests": [{"path": "tests/win_ac1.rs", "body": "x", "ids": ["a"]}]}"#;
        let windows = r#"{"tests": [{"path": "tests\\win_ac1.rs", "body": "x", "ids": ["a"]}]}"#;
        let (a, b) = (
            ScriptedPeer::starting(order_v01("t2", 1)).answer_gates(true),
            ScriptedPeer::starting(order_v01("t2", 1)).answer_gates(true),
        );
        run(&a, unix);
        run(&b, windows);
        assert_eq!(freeze_of(&b).frozen_files[0].path, "tests/win_ac1.rs");
        assert_eq!(freeze_of(&b), freeze_of(&a));
        assert_eq!(
            b.result().unwrap().evidence.unwrap().oracle_hash,
            a.result().unwrap().evidence.unwrap().oracle_hash
        );
    }

    #[test]
    fn a_windows_host_path_survives_the_wire_unchanged() {
        let peer = ScriptedPeer::starting(order_v01("t1", 1));
        let root = PathBuf::from(r"C:\Users\someone\ws");
        assert_eq!(drive(peer.clone(), Scenario::default(), root.clone()), OK);
        let sent = peer.sent().pop().unwrap();
        let line = serde_json::to_string(&sent).unwrap();
        let back: harness_protocol::RpcMessage = serde_json::from_str(&line).unwrap();
        let result: UnitResult = back.params_as().unwrap();
        let DeliveryEvidence::Bundle { bundle_path } = result.evidence.unwrap().delivery else {
            panic!("a bundle delivery");
        };
        assert_eq!(PathBuf::from(&bundle_path), root.join("unit-1.bundle"));
        assert!(bundle_path.starts_with(r"C:\Users\someone\ws"));
    }

    #[test]
    fn the_builders_log_lines_are_sent_inside_the_green_stage() {
        let peer = ScriptedPeer::starting(order_v01("t1", 1));
        assert_eq!(run(&peer, r#"{"log_lines": 2}"#), OK);
        let events = peer.events();
        let started = events
            .iter()
            .position(|e| {
                matches!(
                    e,
                    UnitEvent::Stage {
                        stage: Stage::Green,
                        status: StageStatus::Started,
                        ..
                    }
                )
            })
            .unwrap();
        assert!(
            matches!(&events[started + 1], UnitEvent::Log { line, .. } if line == "scripted builder line 1 of 2")
        );
        assert!(matches!(&events[started + 2], UnitEvent::Log { .. }));
        assert!(matches!(
            &events[started + 3],
            UnitEvent::Stage {
                stage: Stage::Green,
                status: StageStatus::Finished,
                ..
            }
        ));
    }

    #[test]
    fn an_unknown_stop_reason_is_refused_before_anything_is_read_or_written() {
        let peer = ScriptedPeer::starting(order_v01("t1", 1));
        let bad = r#"{"stop": {"stage": "green", "reason": "bored", "detail": "x"}}"#;
        assert_eq!(run(&peer, bad), ExitCode::from(EXIT_USAGE));
        assert!(peer.sent().is_empty());
    }

    #[test]
    fn a_unit_kind_this_harness_does_not_declare_is_refused_with_a_failed_result() {
        let mut order = order_v01("t1", 1);
        order["kind"] = json!("draft");
        let peer = ScriptedPeer::starting(order);
        assert_eq!(run(&peer, "{}"), OK);
        assert_eq!(story(&peer), words("result:failed"));
        let failure = peer.result().unwrap().failure.unwrap();
        assert_eq!(failure.scope, ErrorScope::Harness);
    }
}
```

- [ ] **Step 2: Run them and watch them fail**

Run: `cargo test -p cli --lib harness::`

Expected: it does not compile; the errors name `drive`, `Scenario`, `EXIT_HANDSHAKE`,
`CONTROLS` and the wire types the tests use through `super::*`.

- [ ] **Step 3: Write the implementation**

Put this above the test module in `crates/cli/src/harness.rs`:

```rust
//! `reqdrive harness`: one unit of work, spoken over the harness protocol.
//!
//! This is the walking skeleton. The stage machine is real (`engine`), the wire is real
//! (`speaker`), and every stage body is a fake: a scripted runtime and an in-memory workspace.
//! It starts no agent and no container, and reaches no network.
//!
//! What goes out, and in what order:
//!
//! - `provisioned` is the first event, sent before anything that could be slow.
//! - Each stage sends a `stage` event when it starts and when it finishes. The observation a
//!   stage produced follows that stage's `finished` event and precedes the next `started`. So
//!   no `stage` event ever sits between `oracle_frozen` and `gate/request`, or after
//!   `empty_diff`.
//! - `unit/result` is last, and the process then exits.

use engine::{transition, Action, CheckOutcome, Event, Failure as Failed, Finish, Params, State};
use factory_presets::PRESETS_VERSION;
use harness_protocol::{
    bundle_hash, file_sha256, Capabilities, ControlKind, ControlResult, ControlStatus, Delivery,
    DeliveryEvidence, ErrorScope, Evidence, Failure, FrozenFile, GateKind, GateRequest,
    HarnessInfo, Isolation, LogStream, Metering, Observation, OracleFreeze, Outcome, PresetInfo,
    ReviewEvidence, Stage, StageStatus, Stop, StopReason, TestReport, TestRun, UnitEvent, UnitKind,
    UnitResult, WorkOrder,
};
use runtime::fake::{Check, FakeRuntime, Scenario, Scripted, TestFile};
use speaker::{open, Identity, OpenError, Stopped, Transport, Unit};
use std::path::PathBuf;
use std::process::ExitCode;
use std::time::Duration;
use workspace::fake::{repo_path, FakeWorkspace};

/// A result was sent, or the unit was interrupted and said so, or the input closed.
pub const EXIT_OK: u8 = 0;
/// A fault in this harness. A `failed` result was sent first when the wire allowed it.
pub const EXIT_INTERNAL: u8 = 1;
/// Bad arguments or an unusable scenario. Nothing was written to stdout.
pub const EXIT_USAGE: u8 = 2;
/// The handshake failed, so no unit started.
pub const EXIT_HANDSHAKE: u8 = 3;

/// The six controls, in the order the protocol lists them.
const CONTROLS: [ControlKind; 6] = [
    ControlKind::Scope,
    ControlKind::Protected,
    ControlKind::Secrets,
    ControlKind::Dependencies,
    ControlKind::EidosGates,
    ControlKind::Oracle,
];

/// What `reqdrive harness --fake` declares at `initialize`. `isolation: none` and
/// `metering: none` are the honest description of a fake: the control plane will ask for a
/// per-unit opt-in before it runs a unit here.
pub fn fake_identity() -> Identity {
    let preset = |name: &str| PresetInfo {
        name: name.into(),
        version: PRESETS_VERSION.into(),
    };
    Identity {
        info: HarnessInfo {
            name: "reqdrive".into(),
            version: env!("CARGO_PKG_VERSION").into(),
        },
        capabilities: Capabilities {
            isolation: Isolation::None,
            metering: Metering::None,
            gates: vec![GateKind::Oracle],
            delivery: Delivery::Bundle,
            resume: true,
            halt: true,
            holdouts: true,
            controls: CONTROLS.to_vec(),
            network: None,
            profiles: Vec::new(),
            kinds: vec![UnitKind::Build],
            presets: vec![preset("cargo"), preset("node")],
        },
    }
}

/// The scripted stop, as the wire type. An unknown reason is refused here, before the unit
/// starts, and never reaches the wire.
fn scripted_stop(scenario: &Scenario) -> Result<Option<Stop>, String> {
    let Some(stop) = &scenario.stop else {
        return Ok(None);
    };
    let reason: StopReason = serde_json::from_value(serde_json::Value::String(stop.reason.clone()))
        .map_err(|_| format!("scenario: `{}` is not a stop reason", stop.reason))?;
    Ok(Some(Stop {
        reason,
        detail: stop.detail.clone(),
        request: stop.request.clone(),
    }))
}

fn frozen(files: &[TestFile]) -> Vec<FrozenFile> {
    files
        .iter()
        .map(|file| FrozenFile {
            path: repo_path(&file.path),
            sha256: file_sha256(file.body.as_bytes()),
        })
        .collect()
}

fn ids(files: &[TestFile]) -> Vec<String> {
    files.iter().flat_map(|file| file.ids.clone()).collect()
}

fn paths(files: &[FrozenFile]) -> Vec<String> {
    files.iter().map(|file| file.path.clone()).collect()
}

fn wire(stage: engine::Stage) -> Stage {
    match stage {
        engine::Stage::Provision => Stage::Provision,
        engine::Stage::Red => Stage::Red,
        engine::Stage::Plan => Stage::Plan,
        engine::Stage::Green => Stage::Green,
        engine::Stage::Check => Stage::Check,
        engine::Stage::Review => Stage::Review,
        engine::Stage::Deliver => Stage::Deliver,
    }
}

/// The scripted stage behind an engine stage. Provision and Deliver are the workspace's.
fn scripted(stage: engine::Stage) -> Option<runtime::fake::Stage> {
    match stage {
        engine::Stage::Red => Some(runtime::fake::Stage::Red),
        engine::Stage::Plan => Some(runtime::fake::Stage::Plan),
        engine::Stage::Green => Some(runtime::fake::Stage::Green),
        engine::Stage::Check => Some(runtime::fake::Stage::Check),
        engine::Stage::Review => Some(runtime::fake::Stage::Review),
        engine::Stage::Provision | engine::Stage::Deliver => None,
    }
}

/// What one stage body did.
struct Done {
    event: Event,
    log: Vec<String>,
    /// A note for the stage's `finished` event.
    note: Option<String>,
}

impl Done {
    fn plain(event: Event) -> Done {
        Done {
            event,
            log: Vec::new(),
            note: None,
        }
    }
}

/// One unit's fakes and what they have produced so far.
struct Run<'a> {
    order: &'a WorkOrder,
    runtime: FakeRuntime,
    workspace: FakeWorkspace,
    visible: Vec<FrozenFile>,
    holdouts: Vec<FrozenFile>,
    visible_ids: Vec<String>,
    holdout_ids: Vec<String>,
    stop: Option<Stop>,
    failure: Option<String>,
}

impl<'a> Run<'a> {
    fn new(order: &'a WorkOrder, scenario: Scenario, stop: Option<Stop>, root: PathBuf) -> Self {
        Run {
            order,
            workspace: FakeWorkspace::provision(root, &order.unit_id),
            visible: frozen(&scenario.tests),
            holdouts: frozen(&scenario.holdouts),
            visible_ids: ids(&scenario.tests),
            holdout_ids: ids(&scenario.holdouts),
            runtime: FakeRuntime::new(scenario),
            stop,
            failure: None,
        }
    }

    /// The freeze is a function of the scenario alone, so a respawned process reports the same
    /// hashes as the one that froze: an oracle is frozen once in a unit's life.
    fn freeze(&self) -> OracleFreeze {
        OracleFreeze {
            frozen_files: self.visible.clone(),
            frozen_ids: self.visible_ids.clone(),
            holdout_bundle_path: Some(self.workspace.holdout_bundle_path()),
            holdout_hash: Some(bundle_hash(&self.holdouts)),
            holdout_ids: self.holdout_ids.clone(),
        }
    }

    fn oracle_hash(&self) -> String {
        bundle_hash(&self.visible)
    }

    fn gate_request(&self) -> GateRequest {
        GateRequest::Oracle {
            test_files: paths(&self.visible),
            hash: self.oracle_hash(),
            summary: format!(
                "{} visible test file(s) and {} holdout file(s), scripted",
                self.visible.len(),
                self.holdouts.len()
            ),
            holdout_files: paths(&self.holdouts),
            holdout_hash: Some(bundle_hash(&self.holdouts)),
        }
    }

    /// Do one stage with the fakes.
    fn perform(&mut self, stage: engine::Stage) -> Done {
        let Some(script) = scripted(stage) else {
            return Done::plain(match stage {
                engine::Stage::Provision => Event::Provisioned,
                _ => Event::Delivered,
            });
        };
        match self.runtime.run(script) {
            Scripted::Authored { .. } => Done::plain(Event::Frozen),
            Scripted::Planned => Done::plain(Event::Planned),
            Scripted::Built { log } => Done {
                event: Event::Built,
                log,
                note: None,
            },
            Scripted::Checked(check) => Done::plain(Event::Checked(match check {
                Check::Passed => CheckOutcome::Passed,
                Check::Failed => CheckOutcome::Failed,
                Check::EmptyDiff => CheckOutcome::EmptyDiff,
            })),
            Scripted::Reviewed {
                unresolved_blockers,
            } => Done::plain(Event::Reviewed {
                unresolved_blockers,
            }),
            Scripted::Stop(stop) => Done {
                event: Event::Stopped,
                log: Vec::new(),
                note: Some(format!("stopped for a person: {}", stop.detail)),
            },
            Scripted::Fail(fail) => {
                self.failure = Some(fail.detail.clone());
                Done {
                    event: Event::Failed,
                    log: Vec::new(),
                    note: Some(format!("failed: {}", fail.detail)),
                }
            }
        }
    }

    /// The observation an event stands for on the wire, if it stands for one. `next` is the
    /// state after the event, which is where a review's round number lives.
    fn observation(&self, event: Event, next: &State) -> Option<Observation> {
        match event {
            Event::Frozen => Some(Observation::OracleFrozen {
                freeze: Some(self.freeze()),
            }),
            Event::Built => Some(Observation::BuildFinished),
            Event::Checked(CheckOutcome::Passed) => Some(Observation::ChecksPassed),
            Event::Checked(CheckOutcome::Failed) => Some(Observation::ChecksFailed),
            Event::Checked(CheckOutcome::EmptyDiff) => Some(Observation::EmptyDiff),
            Event::Reviewed {
                unresolved_blockers,
            } => Some(Observation::ReviewFinished {
                round: next.rounds(),
                unresolved_blockers,
                checks_green: true,
            }),
            _ => None,
        }
    }

    /// Evidence for `no_change`. The protocol requires it: `branch` and `head_sha` name the
    /// commit that holds the frozen tests the harness wrote, which the control plane then runs
    /// against the base itself. Nothing was built, so no control judged a diff and no review
    /// took place.
    fn frozen_evidence(&self) -> Evidence {
        Evidence {
            controls: Vec::new(),
            review: None,
            ..self.evidence(0)
        }
    }

    /// Evidence for a change that is handed over (`pr_open`).
    fn evidence(&self, rounds: u32) -> Evidence {
        let mut ids_passed = self.visible_ids.clone();
        ids_passed.extend(self.holdout_ids.iter().cloned());
        Evidence {
            branch: self.order.branch.clone(),
            head_sha: self.workspace.head_sha().into(),
            delivery: DeliveryEvidence::Bundle {
                bundle_path: self.workspace.bundle_path(),
            },
            pr: None,
            test: TestRun {
                command: self.order.test_cmd.clone(),
                exit_code: 0,
            },
            oracle_hash: Some(self.oracle_hash()),
            spec_hash: self.order.spec.as_ref().map(|s| s.signed_hash.clone()),
            map: None,
            test_report: Some(TestReport { ids_passed }),
            controls: CONTROLS
                .iter()
                .map(|name| ControlResult {
                    name: *name,
                    status: ControlStatus::Passed,
                    detail: "scripted: the fake workspace has no diff to check".into(),
                })
                .collect(),
            review: Some(ReviewEvidence {
                rounds,
                prior_rounds: 0,
                verdicts: Vec::new(),
            }),
        }
    }

    fn result(&self, finish: Finish, rounds: u32) -> UnitResult {
        let blank = |outcome| UnitResult {
            outcome,
            evidence: None,
            failure: None,
            stop: None,
        };
        match finish {
            Finish::PrOpen => UnitResult {
                evidence: Some(self.evidence(rounds)),
                ..blank(Outcome::PrOpen)
            },
            Finish::NoChange => UnitResult {
                evidence: Some(self.frozen_evidence()),
                ..blank(Outcome::NoChange)
            },
            Finish::NeedsHuman(_) => UnitResult {
                stop: self.stop.clone(),
                ..blank(Outcome::NeedsHuman)
            },
            Finish::Failed(Failed::OracleRejected) => failed(ErrorScope::Agent, "oracle rejected"),
            Finish::Failed(Failed::Stage(stage)) => failed(
                ErrorScope::Agent,
                self.failure
                    .as_deref()
                    .unwrap_or(&format!("the {stage:?} stage failed")),
            ),
        }
    }
}

fn failed(scope: ErrorScope, detail: &str) -> UnitResult {
    UnitResult {
        outcome: Outcome::Failed,
        evidence: None,
        failure: Some(Failure {
            scope,
            detail: detail.into(),
        }),
        stop: None,
    }
}

/// How the stage loop ended, when it was not interrupted.
enum End {
    Finished(Finish, u32),
    /// The engine refused an event: a fault in this harness.
    Fault(String),
}

/// Ask the engine what to do, do it with the fakes, tell the control plane, and repeat.
fn conduct<T: Transport>(
    unit: &mut Unit<T>,
    run: &mut Run,
    params: Params,
) -> Result<End, Stopped> {
    let pause = run.runtime.pause();
    let mut state = State::start(params);
    loop {
        let event = match state.action() {
            Action::Finish(finish) => return Ok(End::Finished(finish, state.rounds())),
            Action::AwaitGate => {
                if unit.gate(&run.gate_request())? {
                    Event::GateApproved
                } else {
                    Event::GateRejected
                }
            }
            Action::Run(stage) => {
                if stage == engine::Stage::Provision {
                    // Nothing may delay `provisioned`: not even the scenario's pause.
                    unit.checkpoint(Duration::ZERO)?;
                    unit.observe(Observation::Provisioned)?;
                } else {
                    unit.checkpoint(pause)?;
                }
                unit.stage(wire(stage), StageStatus::Started, None)?;
                let done = run.perform(stage);
                for line in done.log {
                    unit.event(&UnitEvent::Log {
                        stream: LogStream::Agent,
                        line,
                    })?;
                }
                unit.stage(wire(stage), StageStatus::Finished, done.note)?;
                done.event
            }
        };
        let next = match transition(&state, event) {
            Ok(next) => next,
            Err(rejected) => return Ok(End::Fault(rejected.to_string())),
        };
        if let Some(observation) = run.observation(event, &next) {
            unit.observe(observation)?;
        }
        state = next;
    }
}

/// Run one unit over `transport` with the fakes. `root` is where the fake workspace pretends
/// to live; nothing is written there.
pub fn drive<T: Transport>(transport: T, scenario: Scenario, root: PathBuf) -> ExitCode {
    let stop = match scripted_stop(&scenario) {
        Ok(stop) => stop,
        Err(why) => {
            eprintln!("reqdrive harness: {why}");
            return ExitCode::from(EXIT_USAGE);
        }
    };
    let (mut unit, order) = match open(transport, &fake_identity()) {
        Ok(opened) => opened,
        Err(OpenError::Closed | OpenError::Interrupted) => return ExitCode::from(EXIT_OK),
        Err(error) => {
            eprintln!("reqdrive harness: {error}");
            return ExitCode::from(EXIT_HANDSHAKE);
        }
    };
    if order.kind.is_some_and(|kind| kind != UnitKind::Build) {
        let refusal = failed(ErrorScope::Harness, "this harness runs build units only");
        let _ = unit.finish(&refusal);
        return ExitCode::from(EXIT_OK);
    }

    let params = Params {
        gate_required: order.tier.requires_oracle(),
        min_review_rounds: order.caps.min_review_rounds,
        resume_frozen: order.resume.as_ref().is_some_and(|r| r.oracle_frozen),
    };
    let mut run = Run::new(&order, scenario, stop, root);
    match conduct(&mut unit, &mut run, params) {
        // Halted, abandoned, or the control plane is gone: no result, and an orderly exit.
        Err(Stopped::Halt | Stopped::Abandon | Stopped::Closed) => ExitCode::from(EXIT_OK),
        Ok(End::Finished(finish, rounds)) => {
            let _ = unit.finish(&run.result(finish, rounds));
            ExitCode::from(EXIT_OK)
        }
        Ok(End::Fault(why)) => {
            eprintln!("reqdrive harness: internal fault: {why}");
            let _ = unit.finish(&failed(ErrorScope::Harness, &why));
            ExitCode::from(EXIT_INTERNAL)
        }
    }
}
```

- [ ] **Step 4: Run the tests**

Run: `cargo test -p cli --lib`

Expected: `test result: ok. 29 passed` (28 in `harness`, and the scaffold's one).

- [ ] **Step 5: Commit**

```bash
git add crates/cli/src/harness.rs crates/cli/src/lib.rs
git commit -m "feat(cli): drive one unit through seven stages over the fakes"
```

### Task 8: The `harness` command, as a real process

**Files:**
- Create: `crates/cli/src/command.rs`, `crates/cli/tests/contract_harness_process.rs`
- Modify: `crates/cli/src/lib.rs`, `forms/contract.lock.json`

**Interfaces:**
- Consumes: `cli::harness::{drive, EXIT_USAGE}`, `speaker::StdioTransport`, `runtime::fake::Scenario`, `clap`.
- Produces:
  - the command `reqdrive harness [--fake] [--scenario <FILE>]`; `--scenario` needs `--fake`;
    without `--fake` the command exits 2, because no real runtime or workspace exists yet;
  - `cli::command::load_scenario(path: Option<&Path>) -> Result<Scenario, String>`
  - `cli::command::harness(fake: bool, scenario: Option<&Path>) -> ExitCode`
  - one line on stderr at start: `reqdrive <version> harness starting (fake runtime, fake workspace)`

- [ ] **Step 1: Write the failing tests**

Create `crates/cli/tests/contract_harness_process.rs`:

```rust
//! Locked contract tests of `reqdrive harness --fake` as a real process, over real pipes.
//! They guard what an in-memory transport cannot show: exit codes, a closed stdin, a full
//! stdout pipe, and a scenario file read from disk.
//!
//! This file is hash-frozen in `forms/contract.lock.json`: change it only with the owner's
//! review, then re-lock with `cargo xtask lock accept`.

use std::io::{BufRead, BufReader, Read, Write};
use std::path::PathBuf;
use std::process::{Child, ChildStdin, Command, ExitStatus, Stdio};
use std::sync::mpsc::{self, Receiver};
use std::time::{Duration, Instant};

use harness_protocol::{
    method, Empty, InitializeParams, MessageKind, Outcome, RpcMessage, UnitResult, PROTOCOL_VERSION,
};
use serde_json::{json, Value};

const PATIENCE: Duration = Duration::from_secs(20);

fn order(tier: &str) -> Value {
    json!({
        "unit_id": "unit-1",
        "work_item": { "kind": "issue", "ref": "example/repo#1" },
        "tier": tier,
        "task": "A scripted unit. It touches no repository.",
        "repo": {
            "url": "https://example.invalid/repo.git",
            "slug": "example/repo",
            "base_branch": "main"
        },
        "branch": "agent/unit-1",
        "test_cmd": "true",
        "caps": { "usd": 1.0, "wall_clock_secs": 60, "min_review_rounds": 1 }
    })
}

fn line(message: &RpcMessage) -> String {
    format!("{}\n", serde_json::to_string(message).unwrap())
}

fn handshake(tier: &str) -> String {
    let initialize = RpcMessage::request(
        1,
        method::INITIALIZE,
        &InitializeParams {
            protocol_version: PROTOCOL_VERSION.into(),
            accepted_versions: Vec::new(),
        },
    );
    let start = RpcMessage::request(2, method::UNIT_START, &order(tier));
    format!("{}{}", line(&initialize), line(&start))
}

/// A running `reqdrive`, with its stdout read on a thread so a test can wait with a limit.
struct Harness {
    child: Child,
    stdin: Option<ChildStdin>,
    /// Lines of stdout, once something has asked for one. Until then nothing reads the pipe.
    stdout: Option<Receiver<String>>,
}

impl Harness {
    fn spawn(args: &[&str]) -> Harness {
        let mut child = Command::new(env!("CARGO_BIN_EXE_reqdrive"))
            .args(args)
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .spawn()
            .expect("the reqdrive binary starts");
        let stdin = child.stdin.take();
        Harness {
            child,
            stdin,
            stdout: None,
        }
    }

    /// Start reading stdout, on a thread, the first time a test asks for a message.
    fn listen(&mut self) -> &Receiver<String> {
        let child = &mut self.child;
        self.stdout.get_or_insert_with(|| {
            let out = child.stdout.take().expect("stdout is piped");
            let (lines, stdout) = mpsc::channel();
            std::thread::spawn(move || {
                for text in BufReader::new(out).lines().map_while(Result::ok) {
                    if lines.send(text).is_err() {
                        break;
                    }
                }
            });
            stdout
        })
    }

    fn write(&mut self, text: &str) {
        self.write_bytes(text.as_bytes());
    }

    fn write_bytes(&mut self, bytes: &[u8]) {
        let stdin = self.stdin.as_mut().expect("stdin is still open");
        stdin.write_all(bytes).expect("the harness reads its stdin");
        stdin.flush().expect("the harness reads its stdin");
    }

    fn close_stdin(&mut self) {
        self.stdin = None;
    }

    /// The next message on stdout, or `None` once stdout has closed.
    fn next(&mut self) -> Option<RpcMessage> {
        match self.listen().recv_timeout(PATIENCE) {
            Ok(text) => Some(serde_json::from_str(&text).expect("every stdout line is a message")),
            Err(mpsc::RecvTimeoutError::Disconnected) => None,
            Err(mpsc::RecvTimeoutError::Timeout) => {
                panic!("the harness went quiet without exiting")
            }
        }
    }

    /// Every remaining message, up to the end of stdout.
    fn rest(&mut self) -> Vec<RpcMessage> {
        std::iter::from_fn(|| self.next()).collect()
    }

    fn exit(&mut self) -> ExitStatus {
        let deadline = Instant::now() + PATIENCE;
        loop {
            if let Some(status) = self.child.try_wait().expect("the child can be waited on") {
                return status;
            }
            assert!(Instant::now() < deadline, "the harness did not exit");
            std::thread::sleep(Duration::from_millis(10));
        }
    }

    fn stderr(&mut self) -> String {
        let mut text = String::new();
        if let Some(mut err) = self.child.stderr.take() {
            let _ = err.read_to_string(&mut text);
        }
        text
    }
}

impl Drop for Harness {
    fn drop(&mut self) {
        let _ = self.child.kill();
        let _ = self.child.wait();
    }
}

fn result_of(messages: &[RpcMessage]) -> Option<UnitResult> {
    messages
        .iter()
        .find(|m| m.method.as_deref() == Some(method::UNIT_RESULT))
        .map(|m| m.params_as().expect("a unit/result carries a UnitResult"))
}

/// A file under the system's temporary directory, removed when dropped.
struct Scratch(PathBuf);

impl Scratch {
    fn file(name: &str, bytes: &[u8]) -> Scratch {
        let path = std::env::temp_dir().join(format!("reqdrive-{}-{name}", std::process::id()));
        std::fs::write(&path, bytes).expect("the temporary directory is writable");
        Scratch(path)
    }

    fn path(&self) -> &str {
        self.0.to_str().expect("a UTF-8 temporary path")
    }
}

impl Drop for Scratch {
    fn drop(&mut self) {
        let _ = std::fs::remove_file(&self.0);
    }
}

#[test]
fn a_unit_runs_to_its_result_and_the_process_exits_zero_with_stdin_still_open() {
    let mut harness = Harness::spawn(&["harness", "--fake"]);
    harness.write(&handshake("t1"));
    let messages = harness.rest();
    assert_eq!(result_of(&messages).unwrap().outcome, Outcome::PrOpen);
    let last = messages.last().unwrap();
    assert_eq!(last.method.as_deref(), Some(method::UNIT_RESULT));
    assert_eq!(harness.exit().code(), Some(0));
    assert!(
        harness.stdin.is_some(),
        "the harness exited without waiting for stdin to close"
    );
    assert!(harness
        .stderr()
        .contains("harness starting (fake runtime, fake workspace)"));
}

#[test]
fn without_fake_the_harness_refuses_and_writes_nothing_to_stdout() {
    let mut harness = Harness::spawn(&["harness"]);
    assert_eq!(harness.exit().code(), Some(2));
    assert!(harness.rest().is_empty());
    assert!(harness.stderr().contains("pass --fake"));
}

#[test]
fn a_flood_on_stdin_while_stdout_is_unread_does_not_deadlock() {
    // The scripted builder prints about a megabyte, which no pipe buffer holds, and until this
    // test asks for a message nothing reads the harness's stdout: so the harness blocks there,
    // in Green, and cannot finish. Meanwhile this test writes about a megabyte of requests to
    // its stdin. A harness that stopped draining stdin while it was blocked on stdout would
    // now be stuck against us for good. This one reads stdin on its own thread into a queue
    // with no bound, so every byte of the flood is taken.
    let scenario = Scratch::file("flood.json", br#"{"log_lines": 12000}"#);
    let mut harness = Harness::spawn(&["harness", "--fake", "--scenario", scenario.path()]);

    let request = line(&RpcMessage::request(50, method::UNIT_RESUME, &Empty {}));
    let flood = request.repeat(1_048_576 / request.len() + 1);
    let text = format!("{}{flood}", handshake("t1"));
    let mut stdin = harness.stdin.take().expect("stdin is open");
    let (done, written) = mpsc::channel();
    std::thread::spawn(move || {
        let complete = stdin.write_all(text.as_bytes()).is_ok();
        // Hand stdin back still open: closing it would tell the harness to shut down.
        let _ = done.send((stdin, complete));
    });
    let (stdin, complete) = written
        .recv_timeout(PATIENCE)
        .expect("writing to the harness's stdin deadlocked while its stdout was full");
    assert!(complete, "the harness stopped reading its stdin");
    harness.stdin = Some(stdin);

    let messages = harness.rest();
    let acknowledged = messages
        .iter()
        .filter(|m| m.kind() == MessageKind::Response { id: 50 })
        .count();
    assert_eq!(
        acknowledged,
        flood.len() / request.len(),
        "every request was answered"
    );
    assert_eq!(result_of(&messages).unwrap().outcome, Outcome::PrOpen);
    assert_eq!(
        messages.last().unwrap().method.as_deref(),
        Some(method::UNIT_RESULT)
    );
    assert_eq!(harness.exit().code(), Some(0));
}

#[test]
fn closing_stdin_mid_unit_ends_the_process_without_a_result() {
    let scenario = Scratch::file("slow.json", br#"{"step_ms": 300}"#);
    let mut harness = Harness::spawn(&["harness", "--fake", "--scenario", scenario.path()]);
    harness.write(&handshake("t1"));
    let mut seen = Vec::new();
    while seen.len() < 3 {
        seen.push(
            harness
                .next()
                .expect("the handshake replies and a first event"),
        );
    }
    harness.close_stdin();
    seen.extend(harness.rest());
    assert!(
        result_of(&seen).is_none(),
        "a harness whose controller is gone reports to no one"
    );
    assert_eq!(harness.exit().code(), Some(0));
}

#[test]
fn a_line_that_is_not_utf8_ends_the_unit_without_a_result_and_says_why() {
    // The control plane sent bytes that cannot be read. That line might have been an abandon,
    // so the harness does not skip it and carry on: it stops reading, says why on stderr, and
    // ends the unit exactly as it does when stdin closes. Stdin is still open throughout.
    let scenario = Scratch::file("garbled.json", br#"{"step_ms": 300}"#);
    let mut harness = Harness::spawn(&["harness", "--fake", "--scenario", scenario.path()]);
    harness.write(&handshake("t1"));
    let mut seen = Vec::new();
    while seen.len() < 3 {
        seen.push(
            harness
                .next()
                .expect("the handshake replies and a first event"),
        );
    }
    harness.write_bytes(b"{\"jsonrpc\":\"2.0\",\"method\":\"\xff\xfe\"}\n");
    seen.extend(harness.rest());
    assert!(result_of(&seen).is_none());
    assert_eq!(harness.exit().code(), Some(0));
    assert!(
        harness.stdin.is_some(),
        "it stopped because of the line, not because stdin closed"
    );
    assert!(harness
        .stderr()
        .contains("a line from the control plane is not UTF-8"));
}

#[test]
fn halt_mid_unit_is_acknowledged_and_the_process_exits_without_a_result() {
    let scenario = Scratch::file("halt.json", br#"{"step_ms": 300}"#);
    let mut harness = Harness::spawn(&["harness", "--fake", "--scenario", scenario.path()]);
    harness.write(&handshake("t1"));
    let mut seen = Vec::new();
    while seen.len() < 3 {
        seen.push(
            harness
                .next()
                .expect("the handshake replies and a first event"),
        );
    }
    harness.write(&line(&RpcMessage::request(9, method::UNIT_HALT, &Empty {})));
    seen.extend(harness.rest());
    assert_eq!(
        seen.last().unwrap().kind(),
        MessageKind::Response { id: 9 },
        "the acknowledgement is the last thing written"
    );
    assert!(result_of(&seen).is_none());
    assert_eq!(harness.exit().code(), Some(0));
}

#[test]
fn a_scenario_saved_with_crlf_and_a_byte_order_mark_is_read_from_disk() {
    let text = "\u{feff}{\r\n  \"checks\": [\"empty_diff\"]\r\n}\r\n";
    let scenario = Scratch::file("crlf.json", text.as_bytes());
    let mut harness = Harness::spawn(&["harness", "--fake", "--scenario", scenario.path()]);
    harness.write(&handshake("t1"));
    assert_eq!(
        result_of(&harness.rest()).unwrap().outcome,
        Outcome::NoChange
    );
    assert_eq!(harness.exit().code(), Some(0));
}

#[test]
fn an_unusable_scenario_is_a_usage_error_before_the_handshake() {
    let misspelt = Scratch::file("misspelt.json", br#"{"check": ["failed"]}"#);
    for path in [misspelt.path(), "no-such-scenario.json"] {
        let mut harness = Harness::spawn(&["harness", "--fake", "--scenario", path]);
        assert_eq!(harness.exit().code(), Some(2), "{path}");
        assert!(harness.rest().is_empty(), "{path}");
    }
}

#[test]
fn a_gate_left_pending_is_interrupted_by_abandon() {
    let mut harness = Harness::spawn(&["harness", "--fake"]);
    harness.write(&handshake("t2"));
    let gate = loop {
        let message = harness.next().expect("a gate/request before stdout closes");
        if message.method.as_deref() == Some(method::GATE_REQUEST) {
            break message;
        }
    };
    assert!(matches!(gate.kind(), MessageKind::Request { .. }));
    harness.write(&line(&RpcMessage::request(
        9,
        method::UNIT_ABANDON,
        &Empty {},
    )));
    let rest = harness.rest();
    assert_eq!(rest.last().unwrap().kind(), MessageKind::Response { id: 9 });
    assert!(result_of(&rest).is_none());
    assert_eq!(harness.exit().code(), Some(0));
}
```

Replace the test module at the end of `crates/cli/src/lib.rs` with:

```rust
#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn an_unknown_command_or_flag_is_a_usage_error() {
        assert_eq!(main_from(["reqdrive"]), ExitCode::from(2));
        assert_eq!(main_from(["reqdrive", "frobnicate"]), ExitCode::from(2));
        assert_eq!(
            main_from(["reqdrive", "harness", "--real"]),
            ExitCode::from(2)
        );
    }

    #[test]
    fn a_scenario_needs_the_fake_runtime() {
        assert_eq!(
            main_from(["reqdrive", "harness", "--scenario", "s.json"]),
            ExitCode::from(2)
        );
    }

    #[test]
    fn harness_without_fake_is_refused_until_real_parts_exist() {
        assert_eq!(main_from(["reqdrive", "harness"]), ExitCode::from(2));
    }

    #[test]
    fn version_and_help_succeed() {
        assert_eq!(main_from(["reqdrive", "--version"]), ExitCode::SUCCESS);
        assert_eq!(
            main_from(["reqdrive", "harness", "--help"]),
            ExitCode::SUCCESS
        );
    }
}
```

- [ ] **Step 2: Run them and watch them fail**

```bash
cargo test -p cli --features testkit --test contract_harness_process
cargo test -p cli --lib tests::
```

Expected: the first compiles and reports `1 passed; 8 failed`: the binary still refuses every
command, so only `an_unusable_scenario_is_a_usage_error_before_the_handshake` passes. The
second reports `tests::version_and_help_succeed ... FAILED` (`31 passed; 1 failed`).

- [ ] **Step 3: Write the command**

Create `crates/cli/src/command.rs`:

```rust
//! The commands of the `reqdrive` binary: where the process's own stdin, stdout, files and
//! temporary directory are handed to the code that does the work.

use crate::harness::{drive, EXIT_USAGE};
use runtime::fake::Scenario;
use speaker::StdioTransport;
use std::path::Path;
use std::process::ExitCode;

/// Read a scenario file, or take the happy path when there is none.
pub fn load_scenario(path: Option<&Path>) -> Result<Scenario, String> {
    let Some(path) = path else {
        return Ok(Scenario::default());
    };
    let text = std::fs::read_to_string(path).map_err(|e| format!("{}: {e}", path.display()))?;
    Scenario::parse(&text).map_err(|e| format!("{}: {e}", path.display()))
}

/// `reqdrive harness [--fake] [--scenario FILE]`.
pub fn harness(fake: bool, scenario: Option<&Path>) -> ExitCode {
    if !fake {
        eprintln!(
            "reqdrive harness: no real runtime or workspace is built yet; pass --fake to run on fakes"
        );
        return ExitCode::from(EXIT_USAGE);
    }
    let scenario = match load_scenario(scenario) {
        Ok(scenario) => scenario,
        Err(why) => {
            eprintln!("reqdrive harness: {why}");
            return ExitCode::from(EXIT_USAGE);
        }
    };
    eprintln!(
        "reqdrive {} harness starting (fake runtime, fake workspace)",
        env!("CARGO_PKG_VERSION")
    );
    let root = std::env::temp_dir().join("reqdrive-fake");
    drive(StdioTransport::stdio(), scenario, root)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn no_scenario_file_is_the_happy_path() {
        assert_eq!(load_scenario(None).unwrap(), Scenario::default());
    }

    #[test]
    fn a_missing_scenario_file_is_an_error_that_names_the_file() {
        let missing = load_scenario(Some(Path::new("no-such-scenario.json"))).unwrap_err();
        assert!(missing.starts_with("no-such-scenario.json: "));
    }

    #[test]
    fn without_fake_the_command_is_refused() {
        assert_eq!(harness(false, None), ExitCode::from(EXIT_USAGE));
    }
}
```

Replace everything above the test module in `crates/cli/src/lib.rs` with:

```rust
//! `cli`: the `reqdrive` binary's library half. Wiring only: it parses the command line and is
//! the one place where real or fake implementations of the other crates are chosen.
//!
//! One command exists so far: `reqdrive harness --fake`.

pub mod command;
pub mod harness;

#[cfg(any(test, feature = "testkit"))]
pub mod testkit;

use clap::{Parser, Subcommand};
use std::path::PathBuf;
use std::process::ExitCode;

#[derive(Debug, Parser)]
#[command(
    name = "reqdrive",
    version,
    about = "A software factory harness: a signed spec goes in, a verified change comes out."
)]
struct Cli {
    #[command(subcommand)]
    command: Command,
}

#[derive(Debug, Subcommand)]
enum Command {
    /// Speak the harness protocol on stdin and stdout, for one unit of work.
    Harness {
        /// Use the scripted runtime and the in-memory workspace: no agent, no container.
        #[arg(long)]
        fake: bool,
        /// A scenario file for the scripted runtime (JSON). Needs --fake.
        #[arg(long, value_name = "FILE", requires = "fake")]
        scenario: Option<PathBuf>,
    },
}

/// The binary's whole behaviour, given its arguments (the program name first).
pub fn main_from<I, S>(args: I) -> ExitCode
where
    I: IntoIterator<Item = S>,
    S: Into<std::ffi::OsString> + Clone,
{
    let cli = match Cli::try_parse_from(args) {
        Ok(cli) => cli,
        Err(error) => {
            let _ = error.print();
            return if error.use_stderr() {
                ExitCode::from(harness::EXIT_USAGE)
            } else {
                ExitCode::SUCCESS
            };
        }
    };
    match cli.command {
        Command::Harness { fake, scenario } => command::harness(fake, scenario.as_deref()),
    }
}
```

- [ ] **Step 4: Run the tests**

```bash
cargo test -p cli --lib
cargo test -p cli --features testkit --test contract_harness_process
```

Expected: `test result: ok. 35 passed`, then `test result: ok. 9 passed`.

- [ ] **Step 5: See it run**

```bash
cargo build
{ printf '%s\n' \
  '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocol_version":"0.2"}}' \
  '{"jsonrpc":"2.0","id":2,"method":"unit/start","params":{"unit_id":"demo","work_item":{"kind":"issue","ref":"example/repo#1"},"tier":"t1","task":"demo","repo":{"url":"https://example.invalid/r.git","slug":"example/repo","base_branch":"main"},"branch":"agent/demo","test_cmd":"true","caps":{"usd":1.0,"wall_clock_secs":60,"min_review_rounds":1}}}'; \
  sleep 1; } | target/debug/reqdrive harness --fake | wc -l
```

Expected: `22`: two replies, nineteen events and the result.

- [ ] **Step 6: Lock the contract test**

```bash
cargo xtask lock accept
cargo xtask lock check
```

Expected: `lock: regenerated with 3 contract tests`; then
`lock: OK (3 locked contract tests unchanged)`.

- [ ] **Step 7: Commit**

```bash
cargo fmt --all
git add crates/cli forms/contract.lock.json
git commit -m "feat(cli): reqdrive harness --fake, with locked process-level contract tests"
```

### Task 9: Turn the conformance kit on, and prove the milestone

**Files:**
- Modify: `forms/contract.lock.json` (one flag), `forms/registry.md` (five states), `docs/STATUS.md`

**Interfaces:**
- Consumes: `cargo xtask test contract`; the kit at `contracts-v0.2.0`.
- Produces: a contract tier that installs and runs the conformance kit and fails if it is
  missing; the five `speaker` gates `live`.

- [ ] **Step 1: Run the contract tier as it is**

Run: `cargo xtask test contract`

Expected: the three locked files pass, and the last line is
`contract: OK (3 locked test file(s), conformance kit: false)`. The kit has not run.

- [ ] **Step 2: Require the kit**

In `forms/contract.lock.json`, change `"conformance_kit": false` to `"conformance_kit": true`.
Change nothing else in the file by hand.

- [ ] **Step 3: Run the contract tier**

Run: `cargo xtask test contract`

Expected: after the locked tests, `cargo install` builds the kit into `.kit/contracts-v0.2.0/`
(a minute or two, once), then one `PASS` line per case, a summary with `0 skipped, 0 failed`,
`conformance: OK (… kit contracts-v0.2.0)`, and
`contract: OK (3 locked test file(s), conformance kit: true)`.

A `FAIL` or a `SKIP` here is a real finding. Do not edit a locked test, the kit's arguments or
the lock to get past it. Report the case and the kit's line for it.

- [ ] **Step 4: Mark the speaker gates live**

In `forms/registry.md`, in each of the five rows `speaker.G1` to `speaker.G5`, change the last
cell from `planned` to `live`. Then:

Run: `cargo xtask parity`

Expected: `parity: OK`. A live gate's location must exist and its tier must run in CI, and a
Form with a live gate must list interface files that exist; this run proves all three for
`speaker`.

- [ ] **Step 5: Bring the status file up to date**

In `docs/STATUS.md`, replace the paragraph that begins `**Readiness.**` with:

```markdown
**Readiness.** Milestone 0's walking skeleton works. `reqdrive harness --fake` drives a scripted
unit through all seven stages on protocol 0.2, over a real stage machine (`engine`) and a real
wire (`speaker`), with a scripted runtime and an in-memory workspace in place of an agent and a
container. It passes the control plane's conformance kit, which the contract tier installs and
runs. Nothing runs a real model, and `harness` without `--fake` is refused.
```

Replace the two list items under `**Known gaps.**` that begin `- No Form exists yet` and
`- The contract tier holds no test` with:

```markdown
- The skeleton's engine has both loops and no counting: no escalation and no limit on rounds.
- The fakes report every control as passed. That is a statement about the fake, not about a
  repository; `isolation: none` in the declared capabilities says so on the wire.
- Seven of the eight Forms describe crates that are still empty; their gates are `planned`.
```

Add at the top of `## Session log`:

```markdown
### <today's date> — milestone 0 walking skeleton

Pinned the contract crates to `contracts-v0.2.0`. Built the skeleton's stage machine, the
scripted runtime, the in-memory workspace, the protocol speaker and `reqdrive harness --fake`.
Three contract test files are locked; the contract tier runs the conformance kit.
```

- [ ] **Step 6: Run the lane's Verify table**

Run every command in the "Verify" table at the top of this lane except the last, and keep the
output.

- [ ] **Step 7: Commit, push and open the pull request**

```bash
git add forms/contract.lock.json forms/registry.md docs/STATUS.md
git commit -m "feat(contract): run the conformance kit in the contract tier; speaker gates live"
git push -u origin feat/m0-skeleton
```

Write the body to `/d/MajorProjects/.swarm-wt/m0-rd-skel-pr.md`:

```markdown
## What changed

- The contract crates pinned to `contracts-v0.2.0` (root `Cargo.toml`, `Cargo.lock`).
- `engine`: the skeleton's stage machine. `runtime::fake`: a scripted runtime and its scenario
  file. `workspace::fake`: an in-memory workspace. `speaker`: transport, handshake, unit, and a
  scripted peer in its testkit. `cli`: `reqdrive harness --fake [--scenario FILE]`.
- The contract tier now runs the control plane's conformance kit; the five `speaker` gates are live.

## Lock

`forms/contract.lock.json` now locks three files and requires the kit:
`crates/cli/tests/contract_pins.rs`, `crates/cli/tests/contract_harness_process.rs`,
`crates/speaker/tests/contract_speaker.rs`. All three are new in this pull request.

## How it was verified

<paste the output of each Verify command, including the kit's PASS lines>

## Requests and notes

<what you needed outside your ownership; anything the tagged crates did differently from this
plan; or "none">
```

```bash
gh pr create --base factory/m0 --head feat/m0-skeleton \
  --title "M0 walking skeleton: reqdrive harness --fake passes the conformance kit" \
  --body-file /d/MajorProjects/.swarm-wt/m0-rd-skel-pr.md
gh pr checks --watch
```

Expected: every job passes on Linux and on Windows. Do not merge.

---

## Lane SANDBOX

**Owns:**
- in `reqdrive`: `docs/repo-config.md`;
- in `adbarc92/command-center-agent-sandbox` (the `node` preset): `.reqdrive/config.toml`, and
  the companions that file names or needs: `package-lock.json`, `.gitignore`, `src/add.js`,
  `test/add.test.js`;
- in `adbarc92/command-center-agent-sandbox-cargo` (the `cargo` preset): every file, since the
  repository starts empty: `.reqdrive/config.toml`, `Cargo.toml`, `Cargo.lock`,
  `crates/sandbox/Cargo.toml`, `crates/sandbox/src/lib.rs`, `crates/sandbox/tests/add.rs`,
  `.config/nextest.toml`, `.gitignore`, `README.md`.

The `reqdrive init` command that will draft `.reqdrive/config.toml` is milestone 1. Here the
two files are written by hand, and the format they follow is documented.

**Reads:** this plan; the protocol's `RepoConfig` type (the file mirrors it field for field);
the findings of spikes S6 and S7 when they exist (private; read them, never paste from them).

**Worktree and branch:**
- `reqdrive`: worktree `D:\MajorProjects\.swarm-wt\m0-rd-sandbox`, branch `feat/m0-repo-config`
  cut from `origin/factory/m0`, pull request against `factory/m0`.
- Each sandbox repository: a fresh clone under `D:\MajorProjects\.swarm-wt\`
  (`m0-rd-sandbox-node`, `m0-rd-sandbox-cargo`), branch `feat/onboard-reqdrive`, pull request
  against that repository's `main`. Neither has an integration branch.

**Needs:** RD-COORD merged into `factory/m0` (A2), for Task 1. The control plane's presets lane,
for the two preset names. Owner action A7 for Task 3. Owner action A8 for Task 4. `node` and
`npm` for Task 2; `uv` for the TOML check.

**Blocks:** milestone 1's functional smoke, which runs a unit in a sandbox repository.

**Verify:**

| Where | Command | Expected |
|---|---|---|
| `reqdrive` | `test -f docs/repo-config.md && cargo xtask test static` | exit 0 |
| each sandbox | `uv run --no-project python -c "import tomllib; d=tomllib.load(open('.reqdrive/config.toml','rb')); print(sorted(d)); print(sorted(d['commands'])); assert len(d['image'].split('@sha256:')[1])==64"` | `['commands', 'env', 'image', 'lockfiles', 'manifests', 'preset', 'test_dirs', 'test_report']` then `['build', 'format_check', 'lint', 'setup', 'test']` |
| node sandbox | the five commands of its `[commands]`, in order | each exits 0; `reqdrive-junit.xml` holds one `<testcase` |
| cargo sandbox | `cargo fetch --locked`, then its `build`, `format_check` and `lint` commands | each exits 0 |
| each sandbox | `git status --short`, after committing and running the commands again | empty: no command leaves an untracked file |

### Task 1: Document the configuration file

**Files:**
- Create (in `reqdrive`): `docs/repo-config.md`

**Interfaces:**
- Consumes: `harness_protocol::RepoConfig { preset, image, env, commands: RepoCommands { setup, build, test, format_check, lint }, test_report, test_dirs, manifests, lockfiles }`.
- Produces: the public description of `.reqdrive/config.toml`, which the README already links.

- [ ] **Step 1: Create the worktree**

```bash
git -C /d/MajorProjects/INFRASTRUCTURE/reqdrive fetch origin
git -C /d/MajorProjects/INFRASTRUCTURE/reqdrive worktree add --no-track -b feat/m0-repo-config \
  /d/MajorProjects/.swarm-wt/m0-rd-sandbox origin/factory/m0
cd /d/MajorProjects/.swarm-wt/m0-rd-sandbox
grep -n "repo-config.md" README.md
```

Expected: one line of the README links `docs/repo-config.md`, and `test -f docs/repo-config.md`
fails: the link has no target yet.

- [ ] **Step 2: Write the page**

Create `docs/repo-config.md`:

````markdown
# The repository configuration: `.reqdrive/config.toml`

A repository is **onboarded** when it has this file on its base branch. It tells the harness and
the control plane how to build and test the repository without guessing. A repository without
it, or on a stack with no preset, is refused before any unit starts.

`reqdrive init` will draft this file from what it finds in a repository (milestone 1). Until
then it is written by hand, from this page. Either way a person reviews and commits it: the file
is read from the base commit, and no unit may change it.

## The file

```toml
preset = "cargo"
image = "docker.io/library/rust@sha256:<64 hex digits>"
test_report = "target/nextest/ci/junit.xml"
test_dirs = ["crates/sandbox/tests/"]
manifests = ["Cargo.toml", "crates/sandbox/Cargo.toml"]
lockfiles = ["Cargo.lock"]

[env]
CARGO_TERM_COLOR = "never"

[commands]
setup = "cargo fetch --locked"
build = "cargo build --workspace --all-targets --locked --offline"
test = "cargo nextest run --workspace --profile ci --locked --offline"
format_check = "cargo fmt --all -- --check"
lint = "cargo clippy --workspace --all-targets --locked --offline -- -D warnings"
```

The six top-level keys come first, then the two tables. The file maps field for field onto the
protocol's `RepoConfig` type, which is how it travels in a work order.

## Fields

| Key | Required | Meaning |
|---|---|---|
| `preset` | yes | The stack's rule set: `cargo` or `node`. The preset knows how to read this stack's test report, find its test ids, and tell which files no unit may change |
| `image` | yes | The container image every command runs in, **by digest** (`name@sha256:…`), never by tag: the same commit must always run in the same image |
| `test_report` | yes | Where `commands.test` writes a JUnit XML report, relative to the repository root. Evidence is read from this report, test by test; the command's exit code alone is never accepted |
| `test_dirs` | yes | Directories that hold test files. A path ends in `/` |
| `manifests` | yes | The dependency manifests |
| `lockfiles` | yes | The lockfiles. The host regenerates them; an agent never writes one |
| `[env]` | no | Environment variables for every command. Not for secrets: nothing secret belongs in this file |
| `[commands]` | yes | All five commands below |

Paths are relative to the repository root, use `/`, and contain no globs.

## Commands

Each is one command line. It runs from the repository root, inside the image, started by the
host. A command must exit non-zero when it fails.

| Key | Runs with network? | Must |
|---|---|---|
| `setup` | yes | Fetch dependencies into a cache, and nothing else. It is the only command that sees a network. Turn off install-time scripts where the ecosystem allows |
| `build` | no | Compile everything, tests included |
| `test` | no | Run the whole suite and write `test_report`. It must write the report even when a test fails |
| `format_check` | no | Check formatting without rewriting a file |
| `lint` | no | Run the linters, with warnings as errors |

Because `build`, `test`, `format_check` and `lint` run offline against the cache that `setup`
filled, each must work with no network at all.

## Writing test names

The preset reads test ids from the test **source** before any test has run, and again from the
report afterwards; the two must match. So a test name must be one the preset can find by
reading the file: written out literally, not built at run time. A name carries the marker of
the acceptance criterion it checks, for example `ac3`.

## Protected

`.reqdrive/` and everything in it is protected: a unit that changes this file fails its
controls. To change the configuration, a person commits the change to the base branch.

## Assumptions still to be confirmed

The commands in the two sandbox repositories were written before the spikes on test reports
and offline runs reported. Each sandbox's configuration lists what it assumes; the list is
closed against the spike findings before milestone 1 relies on either repository.
````

- [ ] **Step 3: Check, commit and open the pull request**

```bash
test -f docs/repo-config.md && cargo xtask test static
git add docs/repo-config.md
git commit -m "docs: the repository configuration file, .reqdrive/config.toml"
git push -u origin feat/m0-repo-config
gh pr create --base factory/m0 --head feat/m0-repo-config \
  --title "M0: document .reqdrive/config.toml" \
  --body "Adds docs/repo-config.md, the format of the file a target repository declares. The README already links it. Verified: cargo xtask test static passes. No code changed."
```

Expected: the static tier passes; the pull request opens. Do not merge.

### Task 2: Onboard the `node` sandbox

**Files** (in `adbarc92/command-center-agent-sandbox`):
- Create: `.reqdrive/config.toml`, `.gitignore`, `src/add.js`, `test/add.test.js`, `package-lock.json`

**Interfaces:**
- Consumes: the format in `docs/repo-config.md`; the repository as it is: `README.md` and a
  `package.json` whose only script is `"test": "node --test"`.
- Produces: an onboarded repository on the `node` preset, with one passing test and a JUnit
  report at `reqdrive-junit.xml`.

- [ ] **Step 1: Clone and look**

```bash
gh repo clone adbarc92/command-center-agent-sandbox /d/MajorProjects/.swarm-wt/m0-rd-sandbox-node
cd /d/MajorProjects/.swarm-wt/m0-rd-sandbox-node
git checkout --no-track -b feat/onboard-reqdrive
git ls-files
cat package.json
```

Expected: `README.md` and `package.json`, and a `package.json` with no dependencies. If the
repository holds more than that, do not overwrite anything: write only `.reqdrive/config.toml`,
adjust `test_dirs`, `manifests` and `lockfiles` to what is really there, and say so in the
pull request.

- [ ] **Step 2: Write the configuration**

Create `.reqdrive/config.toml`:

```toml
# reqdrive repository configuration. Format: docs/repo-config.md in adbarc92/reqdrive.
# Read from the base commit; no unit may change anything under .reqdrive/.
#
# ASSUMED, not yet confirmed (spikes S6 and S7 decide):
#   A1  node's built-in runner writes JUnit with these two flags, and creates the report file.
#   A2  test ids in that report are stable and match ids read from the test source.
#   A3  `npm ci --ignore-scripts` fills a cache that the other commands can use offline.
#   A4  the image below (node:22-bookworm-slim, resolved 2026-10-04) is enough to run them.

preset = "node"
image = "docker.io/library/node@sha256:43ac6c60b8f89723f746e8a92ce91abd5017e627ce1ddfe4238355d3a30b772c"
test_report = "reqdrive-junit.xml"
test_dirs = ["test/"]
manifests = ["package.json"]
lockfiles = ["package-lock.json"]

[env]
CI = "true"

[commands]
setup = "npm ci --ignore-scripts"
build = "npm run build --if-present"
test = "node --test --test-reporter=junit --test-reporter-destination=reqdrive-junit.xml"
format_check = "npm run format:check --if-present"
lint = "npm run lint --if-present"
```

- [ ] **Step 3: Add what the configuration names**

Create `.gitignore` (the test command writes its report into the tree; it must never show up
as a change):

```
/node_modules/
/reqdrive-junit.xml
```

Create `src/add.js`:

```javascript
'use strict';

/** Adds two numbers. */
function add(a, b) {
  return a + b;
}

module.exports = { add };
```

Create `test/add.test.js`:

```javascript
'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');

const { add } = require('../src/add.js');

test('add_sums_two_numbers', () => {
  assert.equal(add(2, 3), 5);
});
```

Generate the lockfile; do not write it by hand:

```bash
npm install --package-lock-only --ignore-scripts
cat package-lock.json
```

Expected: a `package-lock.json` with `"lockfileVersion": 3` and one package, the root, with no
dependencies.

- [ ] **Step 4: Run every command the configuration declares**

```bash
npm ci --ignore-scripts
npm run build --if-present
node --test --test-reporter=junit --test-reporter-destination=reqdrive-junit.xml
grep -c '<testcase' reqdrive-junit.xml
npm run format:check --if-present
npm run lint --if-present
git status --short
```

Expected: every command exits 0; the `grep` prints `1`; `git status --short` lists only the new
files and folders (`.gitignore`, `.reqdrive/`, `package-lock.json`, `src/`, `test/`), and neither
`reqdrive-junit.xml` nor `node_modules`.

On Node 22.17.1, where this was rehearsed, the report gave the test `classname="test"`, not the
file's name. Two files with a test of the same name would then share an id. Note what your
Node version writes: it is one of the things Task 4 settles.

- [ ] **Step 5: Check the file parses, then commit and open the pull request**

Run the `uv` command from the lane's Verify table. Then:

```bash
git add .reqdrive/config.toml .gitignore src/add.js test/add.test.js package-lock.json
git commit -m "chore: onboard for reqdrive on the node preset"
git push -u origin feat/onboard-reqdrive
gh pr create --base main --head feat/onboard-reqdrive \
  --title "Onboard for reqdrive (node preset)" \
  --body "Adds .reqdrive/config.toml and what it names: a lockfile, a .gitignore for the test report, and one passing test. The commands were run on the host with Node <version>; each exited 0 and the report held one test case. Four assumptions are listed at the top of the config file; they are closed against the spike findings before milestone 1 relies on this repository."
```

Do not merge.

### Task 3: Create the `cargo` sandbox's contents

**Files** (in `adbarc92/command-center-agent-sandbox-cargo`, which owner action A7 creates with
only a README):
- Create: `.reqdrive/config.toml`, `Cargo.toml`, `Cargo.lock`, `crates/sandbox/Cargo.toml`,
  `crates/sandbox/src/lib.rs`, `crates/sandbox/tests/add.rs`, `.config/nextest.toml`, `.gitignore`
- Modify: `README.md`

**Interfaces:**
- Consumes: the format in `docs/repo-config.md`.
- Produces: the smallest onboarded repository on the `cargo` preset: a workspace with one
  library crate, one passing test, and the configuration.

- [ ] **Step 1: Clone**

```bash
gh repo view adbarc92/command-center-agent-sandbox-cargo --json name,visibility
gh repo clone adbarc92/command-center-agent-sandbox-cargo /d/MajorProjects/.swarm-wt/m0-rd-sandbox-cargo
cd /d/MajorProjects/.swarm-wt/m0-rd-sandbox-cargo
git checkout --no-track -b feat/onboard-reqdrive
```

Expected: the repository exists and is private. If `gh repo view` fails, owner action A7 has
not happened: stop this task and report. Do not create the repository yourself.

- [ ] **Step 2: Write the workspace**

Create `Cargo.toml`:

```toml
[workspace]
resolver = "2"
members = ["crates/sandbox"]

[workspace.package]
edition = "2021"
version = "0.0.0"
license = "MIT"
publish = false
```

Create `crates/sandbox/Cargo.toml`:

```toml
[package]
name = "sandbox"
description = "A throwaway library for reqdrive agent runs on the cargo preset."
edition.workspace = true
version.workspace = true
license.workspace = true
publish.workspace = true
```

Create `crates/sandbox/src/lib.rs`:

```rust
//! A throwaway library for reqdrive agent runs. Nothing depends on it.

/// Adds two numbers.
pub fn add(a: i64, b: i64) -> i64 {
    a + b
}
```

Create `crates/sandbox/tests/add.rs`:

```rust
use sandbox::add;

#[test]
fn add_sums_two_numbers() {
    assert_eq!(add(2, 3), 5);
}
```

Create `.config/nextest.toml`:

```toml
# cargo-nextest writes this profile's JUnit report to target/nextest/ci/junit.xml,
# which is the test_report in .reqdrive/config.toml.
[profile.ci]
fail-fast = false

[profile.ci.junit]
path = "junit.xml"
```

Create `.gitignore`:

```
/target/
```

Replace `README.md` with:

```markdown
# command-center-agent-sandbox-cargo

A throwaway sandbox for reqdrive agent runs on the `cargo` preset. Nothing depends on it.

It is onboarded: see `.reqdrive/config.toml`.
```

- [ ] **Step 3: Write the configuration**

Create `.reqdrive/config.toml`:

```toml
# reqdrive repository configuration. Format: docs/repo-config.md in adbarc92/reqdrive.
# Read from the base commit; no unit may change anything under .reqdrive/.
#
# ASSUMED, not yet confirmed (spikes S6 and S7 decide):
#   A1  cargo-nextest writes JUnit to target/nextest/<profile>/<path> from .config/nextest.toml.
#   A2  test ids in that report are stable and match ids read from the test source.
#   A3  `cargo fetch --locked` fills a cache that the other commands can use with --offline.
#   A4  the image below (rust:1.93-slim-bookworm, resolved 2026-10-04) lacks cargo-nextest;
#       milestone 1's image adds it, and this digest is replaced then.

preset = "cargo"
image = "docker.io/library/rust@sha256:5b9332190bb3b9ece73b810cd1f1e9f06343b294ce184bcb067f0747d7d333ea"
test_report = "target/nextest/ci/junit.xml"
test_dirs = ["crates/sandbox/tests/"]
manifests = ["Cargo.toml", "crates/sandbox/Cargo.toml"]
lockfiles = ["Cargo.lock"]

[env]
CARGO_TERM_COLOR = "never"

[commands]
setup = "cargo fetch --locked"
build = "cargo build --workspace --all-targets --locked --offline"
test = "cargo nextest run --workspace --profile ci --locked --offline"
format_check = "cargo fmt --all -- --check"
lint = "cargo clippy --workspace --all-targets --locked --offline -- -D warnings"
```

- [ ] **Step 4: Generate the lockfile and run the commands**

```bash
cargo generate-lockfile
cargo fetch --locked
cargo build --workspace --all-targets --locked --offline
cargo fmt --all -- --check
cargo clippy --workspace --all-targets --locked --offline -- -D warnings
cargo test --workspace --locked --offline 2>&1 | grep "test result"
git status --short
```

Expected: every command exits 0; one of the `test result` lines says `1 passed`;
`git status --short` lists the new files and not `target`.

The configured test command uses cargo-nextest. If `cargo nextest --version` works on your
machine, also run `cargo nextest run --workspace --profile ci --locked --offline` and check
that `target/nextest/ci/junit.xml` exists and holds one `<testcase`. If nextest is not
installed, do not install it: say in the pull request that the test command itself was not
exercised.

- [ ] **Step 5: Check the file parses, then commit and open the pull request**

Run the `uv` command from the lane's Verify table. Then:

```bash
git add -A
git commit -m "chore: a minimal cargo workspace, onboarded for reqdrive on the cargo preset"
git push -u origin feat/onboard-reqdrive
gh pr create --base main --head feat/onboard-reqdrive \
  --title "Minimal workspace, onboarded for reqdrive (cargo preset)" \
  --body "A workspace with one library crate and one passing test, and .reqdrive/config.toml. On the host: fetch, build, format check and clippy each exited 0, and cargo test passed. The configured test command (cargo-nextest) was <run and wrote its report | not run: nextest is not installed here>. Four assumptions are listed at the top of the config file."
```

In your final report, add this note for the control plane's presets lane:
`.config/nextest.toml` is test-runner configuration, so the `cargo` preset's protected patterns
need to cover it. Do not merge.

### Task 4: Close the assumptions against the spike findings

**Files:** `.reqdrive/config.toml` in each sandbox; `docs/repo-config.md` in `reqdrive` if a
finding changes the format.

**Interfaces:**
- Consumes: the findings of spike S6 (are test ids stable, unique and readable from both the
  report and the source, per runner?) and spike S7 (can setup fill a cache once, and can the
  other commands then run offline in a throwaway copy of the tree?). They are in the private
  nexus repository under `docs/spikes/`, named `2026-10-s6-…md` and `2026-10-s7-…md`.
- Produces: two configuration files whose header lists no unconfirmed assumption.

- [ ] **Step 1: Find the findings**

```bash
ls /d/MajorProjects/NEXUS/docs/spikes/2026-10-s6-*.md /d/MajorProjects/NEXUS/docs/spikes/2026-10-s7-*.md
```

Expected: one file for each spike. Read them; change nothing in that repository. If either is
missing, the spike has not reported: stop this task, leave both headers as they are, and report
"blocked on A8". Tasks 1 to 3 stand without this one.

- [ ] **Step 2: Go through each assumption, in each file**

Each configuration file's header lists four: A1 (how the runner writes JUnit, and where), A2
(test ids match between report and source), A3 (setup fills a cache the other commands can use
offline), A4 (the image is enough).

| The finding | Do |
|---|---|
| Confirms the assumption as written | Delete that line from the header |
| Gives a different command, flag or path | Change the value in the file to the finding's, exactly; delete the header line; note the old and new value for the pull request |
| Says the runner cannot do it (for example, ids are not unique) | Change nothing. Report it: this is a decision for the owner, and it may change the preset, not the file |
| Does not address it | Leave the header line |

When a file's header has no assumption left, delete the whole `ASSUMED` block.

- [ ] **Step 3: Re-run what changed**

For every command you changed, run it as in Task 2 step 4 or Task 3 step 4, and run the `uv`
check again.

Expected: as before: each exits 0, the report holds the test case, `git status --short` is clean
after a commit.

- [ ] **Step 4: Commit and report**

In each sandbox clone:

```bash
git add .reqdrive/config.toml
git commit -m "chore: reconcile the reqdrive configuration with the spike findings"
git push
```

If a pull request from Task 2 or 3 is still open, this lands on it. If it has merged, open a
new one with the same commands as before and the title
`Reconcile the reqdrive configuration with the spike findings`. In the body, give one row per
assumption: what it was, what the finding said, what changed.

If `docs/repo-config.md` needs to change (a field means something different from what the page
says), make that change in the `reqdrive` worktree on a new branch from `origin/factory/m0`
and open its own pull request against `factory/m0`.

---

## Self-review

What was actually checked while this plan was written and revised, and what could not be.

**Run, with the result seen.**

- [x] Every Rust file in this plan was written into a scratch workspace and built with Rust
      1.93.1 on Windows 11, in two states: after lane RD-COORD, and after lane RD-SKEL.
- [x] **Against the real contract crates.** The first draft was compiled against a stand-in.
      This revision was compiled and tested against `harness-protocol`, `factory-spec` and
      `factory-presets` as the control plane's milestone 0 plans build them, pinned through a
      local repository carrying the tag `contracts-v0.2.0`. That found one compile error (the
      reader's two new errors, `InvalidUtf8` and `LineTooLong`) and one protocol fault (a
      `no_change` result with no evidence, which the protocol's monitor refuses). Both are
      fixed here, each with a test. Nothing else in lanes RD-COORD or RD-SKEL needed changing:
      once the reader was fixed, the whole workspace built clippy-clean with warnings denied
      and every existing test passed.
- [x] RD-COORD state: `cargo xtask test static` passed (`deps: OK (11 crates, 31 source
      files)`, `parity: OK (4 gates, 0 Forms)`); `unit` passed (40 in `xtask`, 1 in `cli`);
      `contract`, `integration`, `e2e` and `live` printed `no tests in this tier yet`.
- [x] The `xtask` build-up of RD-COORD Tasks 2 to 8 was replayed one module at a time: at every
      step the crate was format-clean, clippy-clean with warnings denied, and its tests passed
      (4, 7, 15, 25, 33, 37, 40).
- [x] RD-SKEL state, against the real contract crates: `static` passed (`deps: OK (11 crates,
      38 source files)`, `parity: OK (9 gates, 1 Forms)` with the worked-example Form and its
      five rows); `unit` passed (`cli` 35, `engine` 8, `runtime` 6, `speaker` 8, `workspace` 4,
      `xtask` 40); the three contract files passed (9, 5, 14).
- [x] The intermediate states of RD-SKEL Tasks 7 and 8 were built: the driver without the
      command compiles clean and passes 29 tests; before the command exists the process tests
      report `1 passed; 8 failed`, as Task 8 step 2 says.
- [x] Every way the skeleton ends a unit (`pr_open` at T1 and T2, a rejected gate, a failed
      check and a blocked review before `pr_open`, `no_change`, `needs_human`, `failed`) was
      replayed through the real `ProtocolMonitor` without a violation. With the `no_change`
      evidence removed again, that test fails with `InvalidResult("no_change without
      evidence")`.
- [x] The conformance kit path was run end to end: `cargo install --git … --tag
      contracts-v0.2.0 harness-conformance --bin harness-conformance --locked --root .kit/…`,
      then the kit against `reqdrive harness --fake`: `6 passed, 0 skipped, 0 failed`, and the
      cached kit reused on a second run. The kit was the 0.1 kit's six cases rebuilt against the
      real protocol crate (see below).
- [x] Review Focus 1 was checked by mutation: with the inbound queue bounded, the flood test
      fails after its time limit with its deadlock message; unbounded, it passes.
- [x] The archive move of RD-COORD Task 1 was rehearsed on a copy of `origin/main`: 103 files
      renamed, three left in place, and the Bash suite run from its new location:
      `202 passed, 0 failed`, freeze gate `OK — 202/202`.
- [x] Both sandbox configuration files parse as TOML with the expected keys. The `node`
      sandbox's five commands were run on the host (Node 22.17.1) and the JUnit report was
      written. The `cargo` sandbox's fetch, build, format check, clippy and `cargo test` were run.
- [x] The two image digests were resolved from the registry on 2026-10-04.
- [x] The README's demonstration command was run; its first form (stdin closing at once) ended
      without a result, which is why it now keeps stdin open.
- [x] Searched this file for "TBD", "TODO", "placeholder", "similar to Task" and "appropriately":
      none outside this sentence.
- [x] Every type, function and file name used in a later task is defined in an earlier one,
      with the same spelling; the Interfaces blocks were written from the compiled code.
- [x] Every line of every source file that was compiled appears in this plan: the listings were
      assembled from those files by a script and checked against them afterwards.

**Still unverified.**

- **Nothing was run on Linux.** Every result above is from Windows.
- **The CI workflow has never executed**, and its YAML was not linted.
- **The tag itself.** `contracts-v0.2.0` does not exist on GitHub yet. The crates this was
  built against are the ones the control plane's milestone 0 plans produce, in a scratch
  copy; what is finally tagged could still differ. RD-SKEL Task 1 is where that would show,
  and the plan says to stop and report.
- **The conformance kit at the tag.** The kit that was run is the 0.1 kit's six cases, rebuilt
  against the real protocol crate. The kit the control plane's plans build for 0.2 checks more
  (among them: a mismatched minor version is refused, `unit/start` is answered before anything
  else, and every result carries what its outcome requires). The skeleton has its own tests
  for each of those, and its transcripts pass the real protocol monitor that the 0.2 kit is
  built on, but that kit itself was not run.
- The `cargo install` line was run against a local repository carrying the tag, not against
  GitHub.
- `cargo metadata`'s `source` string for a tagged git dependency was seen as
  `git+<url>?tag=<tag>` on cargo 1.93.1; the code also accepts a trailing `#<commit>`.
- The expected failure messages of the "watch it fail" steps were observed for the `xtask`
  chain's final state, the process tests, the monitor test and the flood mutation. For the
  other steps they are stated as the names the compiler will report missing, which is
  certain, not as exact text.
- cargo-nextest is not installed here: the `cargo` sandbox's test command and its report path
  are unverified. No command was run inside either container image.
- The fit between the milestone 1 harness plan's `speaker` blocks and this plan's was not
  re-checked after this revision. That plan builds on `Stopped` having exactly three variants
  and on the four `EXIT_*` constants; this revision changes neither.

**Choices a reviewer may want to overturn.**

- `provisioned` is sent before the `provision` stage's own started/finished pair, so that it is
  the first event. The other reading (the pair wraps it) is equally easy to build.
- `reqdrive harness` needs `--fake` and refuses without it, so that the command line says which
  implementations were chosen. The conformance invocation is therefore
  `… -- <reqdrive> harness --fake`.
- **An unreadable line ends the unit quietly.** After a line that is not UTF-8 or is too long,
  the harness stops reading and the unit ends as for a closed stdin: no result, exit code 0,
  and the reason on stderr only. The alternative is a `failed` result and a non-zero exit. It
  was not chosen because it needs a fourth `Stopped` variant or a fifth exit code, and
  milestone 1's plan is written against three and four.
- **A line that is readable text but not a message is still dropped**, not fatal. The same
  argument that makes an undecodable line fatal (it might have been an abandon) applies to it
  too. It was left alone because it was not part of this correction and milestone 1's plan was
  written on the present behaviour; the owner may want the two cases to agree.
- **`characterisation_*.rs` runs in the `unit` tier**, with the crate's own tests, as the
  program's rule says. The control plane's scaffold plan, as written, places those targets in
  `integration`. This repository has no such file, so nothing here depends on which is right,
  but the two `xtask`s should agree before either repository gains one.
- The parity check is an `xtask` subcommand in Rust, not a shell script, so it runs the same on
  Windows and Linux with nothing else installed.
- The old `archive/` folder moved inside `archive/bash-v0.3/`, making the archive a whole
  snapshot. The Bash suite is not run in CI.
- `docs/STATUS.md`, `docs/ROADMAP.md` and `archive/README.md` are additions to what was asked.
- CI runs the contract tier on Windows as well as Linux.
- The `node` sandbox gains a lockfile, a `.gitignore`, and one source file with one test, so
  that its configuration names things that exist.
