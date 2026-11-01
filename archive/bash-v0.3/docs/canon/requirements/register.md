# Requirements Register (canon)

Source of truth for intended behavior. **602 requirements from 5 documents**,
extracted 2026-07-24 at commit `7420d69`. Per-REQ anchors live in each module
doc's *Requirement coverage* table — this file is the index, the conflict
record, and the spec-stale record.

## Canonical sources and precedence

| Doc | Prefix | Count | Governs | Horizon | Precedence note |
|-----|--------|-------|---------|---------|-----------------|
| `tests/BEHAVIOR-SPEC.md` | `US-*` | 202 | lib/**, bin/** | current | behavioral contract; 1:1 with test names, frozen in `tests/oracle.lock.json` |
| `docs/superpowers/specs/2026-07-23-…-design.md` | `DES-` | 140 | whole pipeline | current (3 roadmap) | states intent + decisions D1–D12; most specific on the P0–P7 work |
| `README.md` | `RDM-` | 81 | whole repo | current | user-facing contract; normative sections only |
| `CLAUDE.md` | `CLD-` | 110 | whole repo | current (12 roadmap) | architecture + roadmap + decision log |
| `docs/INTEGRATION.md` | `INT-` | 69 | CLI contract, run artifacts | current | integrator contract: exit codes, artifacts, hook env |

Descriptive, **not** canon (context only): `ROADMAP.md` (explicitly superseded),
`docs/superpowers/plans/…` (sequencing, not obligations), `docs/PIPELINE-ANALYSIS.md`,
`docs/SIMPLIFICATION-SUMMARY.md`, `docs/audits/…`, `docs/STATUS.md`,
`docs/QUICKSTART.md`, `docs/VERIFICATION-PLAN.md`, `docs/LAUNCH-TEST-PLAN.md`,
`tests/README.md`, `tests/FINDINGS.md`, `skills/README.md`.

## Coverage by module

Attribution is the requirement's **first governing module**; the offending code
may live elsewhere (the drift report records the real anchor).

| Module | n | satisfied | drifted | intent-met | unimplemented | not-code-verifiable |
|--------|---|-----------|---------|------------|---------------|---------------------|
| pipeline | 149 | 136 | DES-002, CLD-001, CLD-059, INT-030, INT-031, INT-048, INT-056 | INT-068, CLD-063 | CLD-092, CLD-096, CLD-097 *(roadmap)* | DES-133 |
| config | 108 | 105 | RDM-045, CLD-091 | RDM-038 | — | — |
| test-harness | 88 | 56 | US-DOC-02, DES-008, DES-059, DES-060, DES-072, DES-081, DES-101, DES-121 | DES-011, -019, -029, -049, -050, -051, -052, -061, -082, -087, -099, -102, -124, -125, -126, -127 | — | DES-001, -033, -055, -058, -096, -122, -123, -128 |
| safety | 85 | 75 | CLD-006, CLD-108, CLD-110, RDM-070, INT-005, INT-013, INT-014, INT-015, INT-016, INT-017 | — | — | — |
| cli | 77 | 70 | RDM-012, CLD-030, CLD-058, CLD-098, CLD-106 | — | CLD-093 *(roadmap)* | INT-069 |
| evidence | 55 | 50 | DES-114, DES-116, DES-131, RDM-077, CLD-086 | — | — | — |
| ci-and-install | 20 | 11 | DES-120, RDM-005, RDM-008, RDM-009, RDM-010, INT-007, CLD-099 | RDM-011, CLD-101 | — | — |
| pr | 19 | 13 | US-PR-01, US-REV-05, INT-006, CLD-084 | — | CLD-094, CLD-095 *(roadmap)* | — |
| skills-and-archive | 1 | 1 | — | — | — | — |

**Totals:** 517 satisfied · **48 drifted** (→ [drift-report.md](drift-report.md))
· 21 intent-met · 6 unimplemented (**all 6 are `horizon: roadmap`** → see
`index.json#unbuilt_features`; the real gap count is **0**) · 10
not-code-verifiable.

> **DES-002 override.** The module explorer scored DES-002 (*"make the draft-PR
> gate fail-closed"*) `satisfied` from reading the gate condition. Two
> independent Phase-3 verifiers refuted that reading with end-to-end
> reproductions, so it is recorded here as **drifted**. This is the single most
> consequential entry in the canon — see
> [drift-report.md#DES-002](drift-report.md#DES-002).

## Mechanism drift / spec is stale (`intent-met`)

Code achieves the requirement's *goal* by a different — usually superior —
mechanism than the spec names. **Not bugs; not in the drift report.** The fix is
to amend the requirement.

| REQ | Canon (spec mechanism) | As-built (better mechanism) | Suggested amendment |
|-----|------------------------|-----------------------------|---------------------|
| RDM-038 | `version` defaults to `"0.3.0"` | no loader default; absence *warns* rather than silently assuming a version (lib/config.sh:46) | amend README's default column to "(none — absence warns)" |
| CLD-063 | rely on `sanitize_for_prompt` to mitigate expansion risk in a variable-bearing prompt | the prompt is a **quoted** heredoc with `@@TOKEN@@` substitution (lib/run.sh:324), a strictly stronger guarantee | delete CLD-063; it is superseded by CLD-088 |
| INT-068 | per-iteration `testCommand` failures never influence any gate | they feed the scope check, which under `"block"` *can* abort (lib/run.sh:1089) — a stronger control the doc predates | amend INT-068 to name the scope-check exception |
| RDM-011, CLD-101 | (process/build obligations) | met by CI configuration rather than the named mechanism | no change needed |
| DES-011 … DES-127 (16 reqs, test-harness) | specific P0/P2 harness mechanisms | implementation chose equivalent-or-stronger forms (e.g. whole-file hashing subsuming per-body hashing) | fold into a single "freeze mechanism" requirement |

## Not code-verifiable (infra / process)

Excluded from both drift and gap counts.

- `INT-069` — PID liveness may be unreliable on MSYS2 (runtime platform property).
- `DES-133` — a deferral decision about future work, not present behavior.
- `DES-001, -033, -055, -058, -096, -122, -123, -128` — process obligations
  (sequencing of the P0–P7 effort, "run the suite before committing", "record the
  reason for each deferral"): source code cannot confirm they were honored.

## Requirement conflicts

**Nine canon-vs-canon contradictions.** An unresolved spec conflict is itself a
finding; none of these is a code defect.

| # | Contested point | Doc A | Doc B | Which is right |
|---|-----------------|-------|-------|----------------|
| 1 | Is there a Phase 3 verification stage before PR creation? | README.md:140-148 lists five stages, no verification | docs/INTEGRATION.md:145 places `verification-summary.json` at "the end of Phase 3, before PR creation" | **INTEGRATION** — Phase 3 exists (lib/run.sh:1131-1164). README's stage list is incomplete |
| 2 | The full exit-code set | README.md:56 documents 9 and 10 for `verify` | docs/INTEGRATION.md:46-58 stops at 8 | **README** — `lib/errors.sh:7-17` defines 0–10 |
| 3 | Meaning of exit 8 | README.md:187-190 reuses 8 for a `scopeCheck: "block"` abort | docs/INTEGRATION.md:58 defines 8 as git state only, and :451 advises "do not retry on 8 — git state issue" | **README** — the reuse is real (lib/run.sh:1092); INTEGRATION's retry advice misclassifies it |
| 4 | Can a per-iteration `testCommand` failure abort the run? | README.md:174-190 — yes, under `block` | docs/INTEGRATION.md:459 — "logged but don't abort or force retries" flatly | **README** — see conflict 3. Tracked as `intent-met` on INT-068 |
| 5 | Is the scope check a hard gate? | CLAUDE.md:212 "hard gate, not advisory"; docs/STATUS.md:21-22, :94 repeat it | README.md:181-197, design D6, and `lib/policy.sh:56` all say warn-by-default | **README/D6/code** — CLAUDE.md and STATUS.md are wrong. → [CLD-086](drift-report.md#CLD-086) |
| 6 | Required dependencies | README.md:23 adds `timeout` and `sha256sum` | docs/INTEGRATION.md:34,52 and CLAUDE.md:128 omit them | **README** — `timeout` is invoked at lib/run.sh:465, `sha256sum` at tests/oracle-gate.sh:23 |
| 7 | Run-directory contents | README.md:113-121 lists 6 artifacts | docs/INTEGRATION.md:397-414 lists 11 | **INTEGRATION**, and even it is incomplete — neither lists `scope-findings.txt` |
| 8 | Test count | CLAUDE.md:26 "157 tests"; CLAUDE.md:232 "all 152 tests must pass"; design doc:109 "157 test names" | docs/STATUS.md:97 "202/202" | **STATUS** — measured 202 in the suite, the lock and BEHAVIOR-SPEC, and a local run reports 202/0 |
| 9 | What `orchestrate` will do | `bin/reqdrive:580-585` promises **sequential** multi-requirement processing | CLAUDE.md:222 defines it as **parallelism via git worktrees** | unresolved — both describe an unbuilt command; pick one before building it |

Two further internal inconsistencies in `CLAUDE.md` are recorded as drift rather
than conflicts because code settles them: the heredoc entry (Decision Log :147
and Known Pitfalls :268 describe an *unquoted* heredoc at `lib/run.sh:274`,
while Tier 2 :214 correctly reports the quoted form at :324 — the code is quoted,
so :147/:268 are stale), and `select_next_story` cited at `lib/run.sh:347`
(:46, :50) when it is at **:413**. `reqdrive verify` is missing from the CLAUDE.md
Commands table, and `maxStoryRetries` and `policy` are missing from its
Configuration table.
