# pr (canon)

`lib/pr-create.sh` — 44 governing requirements.

## Purpose

Assembles the pull-request body — summary, commit list, Pipeline Verification
table, validation checklist, scope findings — pushes the branch, and submits via
`gh`. Also appends review findings to an existing PR. This module produces the
project's only user-visible output.

## Public interface

| Symbol | Kind | Signature | Anchor | Notes |
|--------|------|-----------|--------|-------|
| `create_pr` | function | `<req_id> <branch> <base> <agent_dir> <draft_flag>` | lib/pr-create.sh:78 | never decides draft itself — forwards `$5` |
| `update_pr_with_review` | function | `<pr_url> <findings_json>` | lib/pr-create.sh:13 | `gh pr edit --body` (:69) |

## Invariants

- The draft flag is fail-closed *at this layer*: `create_pr` only forwards what the caller passed, expanded as `${draft_flag:+"$draft_flag"}` at :262 and :276 — verified to survive the label-dropping retry and `set -u`. The **decision** is [pipeline](pipeline.md)'s. (lib/run.sh:1177-1190)
- Every label reaching `gh` has passed `sanitize_label`, and labels expand as a quoted array. (lib/pr-create.sh:200,210,265)
- The Pipeline Verification section exists iff `verification-summary.json` exists. (lib/pr-create.sh:131)
- The `### Scope findings` section exists iff `scope-findings.txt` exists and is non-empty. (lib/pr-create.sh:185)
- Review findings are **appended to**, never substituted for, the existing body — the current body is fetched first. (lib/pr-create.sh:65-69)
- A `create_pr` failure is always terminal: the caller writes status `failed`, fires the completion hook, and exits `EXIT_PR_ERROR`. (lib/run.sh:1198-1203)

## Data flows

- **body assembly**: prd.json → checklist lib/pr-create.sh:112-121 · verification-summary.json → table :138-178 · scope-findings.txt → :183-191 · git log → commits · all spliced into the heredoc at :223-255 → `gh pr create --body` :261
- **review append**: lib/run.sh:661 → `gh pr view` :65 → concat :67 → `gh pr edit --body` :69

## Dependencies

Internal: `safety` (`sanitize_label`, `sanitize_for_prompt`, auto-sourced
:6-8), `pipeline` (sole caller, :1174), `evidence` (produces both artifacts it
reads), `config` (`REQDRIVE_PR_LABELS`). External: `gh` (`pr create`, `pr view`,
`pr edit`), `git` (push, log), `jq`.

## Gotchas

- `echo "  Pushing branch …"` goes to **stdout** while every other diagnostic in the file uses `>&2`; the caller captures that stdout as the PR URL. One-line fix: add `>&2` to :95. (lib/pr-create.sh:95) → [drift INT-030](../requirements/drift-report.md#INT-030)
- Three sections are built as `section=$(printf '…\n\n')` — command substitution strips the trailing newlines, fusing the next line onto the heading. Affects `### Scope findings` (:186) and the review findings table (:40-42). (lib/pr-create.sh:40) → [drift RDM-077](../requirements/drift-report.md#RDM-077), [US-REV-05](../requirements/drift-report.md#US-REV-05)
- `sanitize_for_prompt` is applied to PR markdown at :52, publishing literal `\$` into the stored body and rewriting backticks to single quotes — destroying code spans in review findings. (lib/pr-create.sh:52) → [drift](../requirements/drift-report.md#SANITIZE-PR-BODY)
- PR-number extraction is `grep -o '[0-9]*$'` on the URL, so a trailing slash or query string breaks it. (lib/pr-create.sh:56)
- The label-dropping retry drops **all** labels, including the REQ-specific one. (lib/pr-create.sh:275-280)
- `jq` output on MSYS carries CRLF; `lib/policy.sh:21` strips `\r` explicitly for exactly this reason — this file does not. (lib/pr-create.sh:45)
- This file sets neither `set -e` nor `set -u`, unlike run.sh/policy.sh/verification.sh. Inert in practice: it is only ever sourced into `bin/reqdrive`, which sets `set -euo pipefail`. (lib/pr-create.sh:1-8)

## Requirement coverage

44 governing reqs: **28 satisfied · 11 drifted · 3 intent-met ·
2 not-code-verifiable**. Canon (intended) behavior for the drifted ones:

| REQ | Status | Canon (intended) | Link |
|-----|--------|------------------|------|
| US-PR-01 | drifted | `create_pr` emits the PR URL on stdout | [drift-report](../requirements/drift-report.md#INT-030) |
| INT-030 / INT-048 | drifted | `run.json.pr_url` and the hook's `PR_URL` are the PR URL | [drift-report](../requirements/drift-report.md#INT-030) |
| US-REV-05 | drifted | review findings render as a markdown table | [drift-report](../requirements/drift-report.md#US-REV-05) |
| RDM-077 | drifted | scope findings render under a `### Scope findings` heading | [drift-report](../requirements/drift-report.md#RDM-077) |
| RDM-045 | drifted | `projectName` supplies the PR title | [drift-report](../requirements/drift-report.md#RDM-045) |
| INT-016 | drifted | exit 6 means PR creation failed **after retry** | [drift-report](../requirements/drift-report.md#INT-016) |
| DES-114 / DES-131 | drifted | classification and findings reach the checkpoint | [drift-report](../requirements/drift-report.md#DES-116) |
| CLD-084 | drifted | the PR body carries an iteration-log summary | [drift-report](../requirements/drift-report.md#CLD-084) |
| CLD-091 | drifted | `pr-create.sh` consumes the `REQDRIVE_POLICY_*` exports | [drift-report](../requirements/drift-report.md#CLD-091) |
| CLD-098 | drifted | library scripts set `set -e` | [drift-report](../requirements/drift-report.md#CLD-098) |

**Verified TRUE, and load-bearing for the project's public claims:** the PR body
really does contain a validation checklist rendered from the PRD's
`acceptanceCriteria` (built :112-121, spliced :246, reaching `gh pr create
--body` :267 — rendered end-to-end under a fake `gh`), a Pipeline Verification
table from `verification-summary.json` (:160-178), a scope-findings section
(:183-191), and appended review findings (:69). See
[claims-audit.md](../claims-audit.md) for how far that carries the stated claim,
and drift entry [`PR-OVERSTATES-COMPLETION`](../requirements/drift-report.md#PR-OVERSTATES-COMPLETION)
for the body's one factually false line.

## Pointers

Draft decision: [pipeline.md](pipeline.md). Artifacts it reads:
[evidence.md](evidence.md).
