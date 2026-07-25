# Convention: artifact contracts (canon)

## Rule

Machine state is **JSON**; human/agent context is **Markdown**. Every JSON
artifact the pipeline writes carries `"version": "0.3.0"` (CLAUDE.md:234). All
run state lives under `.reqdrive/runs/<lowercased REQ-ID>/` (lib/run.sh:685,691).
Schema predicates in `lib/schema.sh` police the boundary; enforcement strength is
the call site's choice.

## Applies to

`lib/**`, `bin/**`, `tests/fixtures/**`

## Examples

| Artifact | Written by | Version field? |
|----------|-----------|----------------|
| `run.json` | lib/run.sh:24 | **no** — the sole exception |
| `prd.json` | the agent (schema at lib/schema.sh:125) | yes, agent-supplied |
| `checkpoint.json` | lib/run.sh:88 | yes (:107) |
| `verification-summary.json` | lib/verification.sh:98 | yes (:137) |
| `iteration-N.summary.json` | lib/run.sh:170 | agent-supplied |
| `reqdrive.json` | lib/init.sh:57 | yes (:59) |
| `progress.txt`, `prompt.md`, `iteration-N.log`, `scope-findings.txt`, `output.log` | various | markdown/plain — no version |

- Atomic write, done right: `verify_write_summary` writes `<file>.tmp` then `mv` (lib/verification.sh:135-164)
- Tri-state kept honest: `verification_passed` is the JSON literal `true`/`false`/`null`, never a quoted string (lib/verification.sh:160)
- `remaining` is `null` exactly when `prd_present` is false (lib/verification.sh:107-112)

## Exceptions

- `run.json` carries no `version` field, unlike every other pipeline-written JSON. (lib/run.sh:71-83)
- `cmd_migrate` rewrites files with `echo "$tmp" > "$file"` — truncate-then-write, not the atomic pattern used elsewhere. (bin/reqdrive:363-364,383-384)
- `reqdrive init` interpolates raw answers into its heredoc with no JSON escaping, so it can emit an unparseable `reqdrive.json`. → [drift RDM-012](../requirements/drift-report.md#RDM-012)
- `run.json.pr_url` is JSON-*escaped* correctly (`jq -Rn`, lib/run.sh:48) but holds the wrong *value* — a two-line string including `create_pr`'s progress output. → [drift INT-030](../requirements/drift-report.md#INT-030)
- The PRD schema does not validate `attempts` at all, and makes `passes` and `priority` optional. → [drift ATTEMPTS-UNVALIDATED](../requirements/drift-report.md#ATTEMPTS-UNVALIDATED)
- Every `verify_collect` jq read ends `|| echo "0"`, so an unreadable `prd.json` is indistinguishable from a complete one. This is the mechanism behind the headline drift finding. → [drift DES-002](../requirements/drift-report.md#DES-002)
- `README.md:113-121` lists a strictly smaller run-directory contents than `docs/INTEGRATION.md:397-414`, and neither lists `scope-findings.txt`. Recorded as a canon-vs-canon conflict in the register.
- Two independent `0.3.0` literals exist — `bin/reqdrive:11` and `lib/schema.sh:4` — with nothing asserting they agree.
