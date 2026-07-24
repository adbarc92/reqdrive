# reqdrive Behavior Specification

Behavioral contract for the core library modules, expressed as user stories.
Each story maps to one or more tests in `tests/simple-test.sh`.

---

## Module 1: errors.sh

### US-ERR-01: Exit code constants
**Test:** `errors: defines the base exit codes 0-8`

**As** a library consumer,
**When** I source `errors.sh`,
**Then** I get named exit codes: `EXIT_SUCCESS=0`, `EXIT_GENERAL_ERROR=1`, `EXIT_MISSING_DEPENDENCY=2`, `EXIT_CONFIG_ERROR=3`, `EXIT_GIT_ERROR=4`, `EXIT_AGENT_ERROR=5`, `EXIT_PR_ERROR=6`, `EXIT_USER_ABORT=7`, `EXIT_PREFLIGHT_FAILED=8`.

### US-ERR-02: Human-readable error messages
**Test:** `errors: EXIT_MESSAGES covers the base codes 0-8`

**As** a library consumer,
**When** I source `errors.sh`,
**Then** every exit code (0-8) has a corresponding entry in `EXIT_MESSAGES`.

### US-ERR-03: Get exit message for known code
**Test:** `errors: get_exit_message returns correct messages`

**As** a library consumer,
**When** I call `get_exit_message` with a known code (e.g. 0, 3, 8),
**Then** I get the matching human-readable message (e.g. "Success", "Configuration error", "Pre-flight checks failed").

### US-ERR-04: Get exit message for unknown code
**Test:** `errors: get_exit_message returns 'Unknown error' for unknown code`

**As** a library consumer,
**When** I call `get_exit_message` with an unrecognized code (e.g. 99),
**Then** I get `"Unknown error"`.

### US-ERR-05: die with code and custom message
**Test:** `errors: die exits with code and custom message`

**As** a library consumer,
**When** I call `die 3 "bad config"`,
**Then** the process exits with code 3 and prints `[ERROR] bad config` to stderr.

### US-ERR-06: die with code, no custom message
**Test:** `errors: die uses EXIT_MESSAGES when no custom message`

**As** a library consumer,
**When** I call `die 5` (no second argument),
**Then** the process exits with code 5 and prints `[ERROR] Agent execution failed` (from EXIT_MESSAGES) to stderr.

### US-ERR-07: die with no arguments
**Test:** `errors: die defaults to exit code 1`

**As** a library consumer,
**When** I call `die` with no arguments,
**Then** the process exits with code 1.

### US-ERR-08: die_on_error after success
**Test:** `errors: die_on_error is silent after success`

**As** a library consumer,
**When** the previous command succeeded (`$?` is 0) and I call `die_on_error`,
**Then** nothing happens and execution continues.

### US-ERR-09: die_on_error after failure
**Test:** `errors: die_on_error exits after failure`

**As** a library consumer,
**When** the previous command failed (`$?` is non-zero) and I call `die_on_error "it broke"`,
**Then** the process exits with code 1 and prints the message including "it broke" to stderr.

### US-ERR-10: Verification and concurrency exit codes are defined
**Test:** `errors: verification and concurrency codes are defined`

**As** a maintainer wiring `reqdrive verify` into the exit-code contract,
**When** `lib/errors.sh` is sourced,
**Then** `EXIT_VERIFICATION_FAILED` is `9` and `EXIT_CONCURRENT_RUN` is `10`, and `get_exit_message` returns a non-empty message other than "Unknown error" for both.

---

## Module 2: schema.sh

### US-SCH-01: Schema version — exact match passes
**Test:** `schema: check_schema_version passes on exact version`

**As** a config loader,
**When** I call `check_schema_version` on a file with `"version": "0.3.0"`,
**Then** it returns 0 with no output.

### US-SCH-02: Schema version — missing version warns
**Test:** `schema: check_schema_version warns on missing version`

**As** a config loader,
**When** I call `check_schema_version` on a file with no `version` field,
**Then** it returns 0 (backward compatible) but prints a warning mentioning "No version field" to stderr.

### US-SCH-03: Schema version — incompatible major rejects
**Test:** `schema: check_schema_version rejects incompatible major`

**As** a config loader,
**When** I call `check_schema_version` on a file with `"version": "9.0.0"`,
**Then** it returns 1 and prints an error mentioning "Incompatible" to stderr.

### US-SCH-04: Schema version — nonexistent file passes
**Test:** `schema: check_schema_version passes for nonexistent file`

**As** a config loader,
**When** I call `check_schema_version` on a path that doesn't exist,
**Then** it returns 0 (no-op).

### US-SCH-05: Schema version — older minor accepted
**Test:** `schema: check_schema_version accepts older minor (0.2.0)`

**As** a config loader,
**When** I call `check_schema_version` on a file with `"version": "0.2.0"`,
**Then** it returns 0 (same major = compatible).

### US-SCH-06: Schema version — newer minor warns
**Test:** `schema: check_schema_version warns on newer minor (0.9.0)`

**As** a config loader,
**When** I call `check_schema_version` on a file with `"version": "0.9.0"`,
**Then** it returns 0 but prints a warning mentioning "newer than supported" to stderr.

### US-SCH-07: Schema version — patch difference accepted
**Test:** `schema: check_schema_version accepts patch difference (0.3.1)`

**As** a config loader,
**When** I call `check_schema_version` on a file with `"version": "0.3.1"`,
**Then** it returns 0 with no error.

### US-SCH-08: Config schema — valid config passes
**Test:** `schema: validate_config_schema passes for valid config`

**As** a validator,
**When** I call `validate_config_schema` on a well-formed manifest with correct types,
**Then** it returns 0.

### US-SCH-09: Config schema — empty object passes
**Test:** `schema: validate_config_schema passes for empty object`

**As** a validator,
**When** I call `validate_config_schema` on `{}`,
**Then** it returns 0 (all fields are optional).

### US-SCH-10: Config schema — invalid JSON rejects
**Test:** `schema: validate_config_schema rejects invalid JSON`

**As** a validator,
**When** I call `validate_config_schema` on a file containing non-JSON text,
**Then** it returns 1 and prints an error mentioning "Invalid JSON".

### US-SCH-11: Config schema — rejects non-string requirementsDir
**Test:** `schema: validate_config_schema rejects non-string requirementsDir`

**As** a validator,
**When** I call `validate_config_schema` on a file where `requirementsDir` is a number,
**Then** it returns 1 and prints "requirementsDir must be a string".

### US-SCH-24: Config schema — rejects non-number maxIterations
**Test:** `schema: validate_config_schema rejects non-number maxIterations`

**As** a validator,
**When** I call `validate_config_schema` on a file where `maxIterations` is a string,
**Then** it returns 1 and prints "maxIterations must be a number".

### US-SCH-25: Config schema — rejects non-array prLabels
**Test:** `schema: validate_config_schema rejects non-array prLabels`

**As** a validator,
**When** I call `validate_config_schema` on a file where `prLabels` is a string,
**Then** it returns 1 and prints "prLabels must be an array".

### US-SCH-12: Config schema — multiple errors reported
**Test:** `schema: validate_config_schema reports multiple type errors`

**As** a validator,
**When** a config has multiple type violations,
**Then** `validate_config_schema` reports all of them (not just the first).

### US-SCH-13: PRD schema — valid PRD passes
**Test:** `schema: validate_prd_schema passes for valid PRD`

**As** a validator,
**When** I call `validate_prd_schema` on a file with `project`, `sourceReq`, and a valid `userStories` array,
**Then** it returns 0.

### US-SCH-14: PRD schema — invalid JSON rejects
**Test:** `schema: validate_prd_schema rejects invalid JSON`

**As** a validator,
**When** I call `validate_prd_schema` on non-JSON text,
**Then** it returns 1.

### US-SCH-15: PRD schema — missing project rejected
**Test:** `schema: validate_prd_schema rejects missing project`

**As** a validator,
**When** a PRD file is missing `project`,
**Then** `validate_prd_schema` returns 1 and names the missing field.

### US-SCH-26: PRD schema — missing sourceReq rejected
**Test:** `schema: validate_prd_schema rejects missing sourceReq`

**As** a validator,
**When** a PRD file is missing `sourceReq`,
**Then** `validate_prd_schema` returns 1 and names the missing field.

### US-SCH-27: PRD schema — missing userStories rejected
**Test:** `schema: validate_prd_schema rejects missing userStories`

**As** a validator,
**When** a PRD file is missing `userStories`,
**Then** `validate_prd_schema` returns 1 and names the missing field.

### US-SCH-16: PRD schema — non-array userStories rejected
**Test:** `schema: validate_prd_schema rejects non-array userStories`

**As** a validator,
**When** `userStories` is a string instead of an array,
**Then** `validate_prd_schema` returns 1 and prints "userStories must be an array".

### US-SCH-17: PRD schema — empty stories array passes
**Test:** `schema: validate_prd_schema passes with empty stories array`

**As** a validator,
**When** `userStories` is `[]`,
**Then** `validate_prd_schema` returns 0.

### US-SCH-18: PRD schema — story missing id rejected
**Test:** `schema: validate_prd_schema rejects story missing id`

**As** a validator,
**When** a story is missing `id`,
**Then** `validate_prd_schema` returns 1 and identifies the missing field with the story index.

### US-SCH-28: PRD schema — story missing title rejected
**Test:** `schema: validate_prd_schema rejects story missing title`

**As** a validator,
**When** a story is missing `title`,
**Then** `validate_prd_schema` returns 1 and identifies the missing field with the story index.

### US-SCH-29: PRD schema — story missing acceptanceCriteria rejected
**Test:** `schema: validate_prd_schema rejects story missing acceptanceCriteria`

**As** a validator,
**When** a story is missing `acceptanceCriteria`,
**Then** `validate_prd_schema` returns 1 and identifies the missing field with the story index.

### US-SCH-19: PRD schema — rejects non-array acceptanceCriteria
**Test:** `schema: validate_prd_schema rejects non-array acceptanceCriteria`

**As** a validator,
**When** a story has `acceptanceCriteria` as a string instead of an array,
**Then** `validate_prd_schema` returns 1 with a specific type error.

### US-SCH-30: PRD schema — rejects non-boolean passes
**Test:** `schema: validate_prd_schema rejects non-boolean passes`

**As** a validator,
**When** a story has `passes` as a string instead of a boolean,
**Then** `validate_prd_schema` returns 1 with a specific type error.

### US-SCH-33: PRD schema — rejects non-number priority
**Test:** `schema: validate_prd_schema rejects non-number priority`

**As** a validator,
**When** a story has `priority` as the string `"high"` instead of a number,
**Then** `validate_prd_schema` returns 1 and prints "priority must be a number".

### US-SCH-34: PRD schema — priority is optional
**Test:** `schema: validate_prd_schema passes when priority is missing`

**As** a validator,
**When** a story has no `priority` field at all,
**Then** `validate_prd_schema` returns 0 (priority is optional).

### US-SCH-20: Checkpoint schema — valid checkpoint passes
**Test:** `schema: validate_checkpoint_schema passes for valid checkpoint`

**As** a validator,
**When** I call `validate_checkpoint_schema` on a file with `req_id`, `branch`, and numeric `iteration`,
**Then** it returns 0.

### US-SCH-21: Checkpoint schema — invalid JSON rejects
**Test:** `schema: validate_checkpoint_schema rejects invalid JSON`

**As** a validator,
**When** I call `validate_checkpoint_schema` on non-JSON text,
**Then** it returns 1.

### US-SCH-22: Checkpoint schema — missing req_id rejected
**Test:** `schema: validate_checkpoint_schema rejects missing req_id`

**As** a validator,
**When** a checkpoint is missing `req_id`,
**Then** `validate_checkpoint_schema` returns 1 and names the missing field.

### US-SCH-31: Checkpoint schema — missing branch rejected
**Test:** `schema: validate_checkpoint_schema rejects missing branch`

**As** a validator,
**When** a checkpoint is missing `branch`,
**Then** `validate_checkpoint_schema` returns 1 and names the missing field.

### US-SCH-32: Checkpoint schema — missing iteration rejected
**Test:** `schema: validate_checkpoint_schema rejects missing iteration`

**As** a validator,
**When** a checkpoint is missing `iteration`,
**Then** `validate_checkpoint_schema` returns 1 and names the missing field.

### US-SCH-23: Checkpoint schema — non-number iteration rejected
**Test:** `schema: validate_checkpoint_schema rejects non-number iteration`

**As** a validator,
**When** `iteration` is a string like `"three"`,
**Then** `validate_checkpoint_schema` returns 1 and prints "iteration must be a number".

---

## Module 3: sanitize.sh

### US-SAN-01: sanitize_for_prompt — escapes backticks and dollar signs
**Test:** `sanitize_for_prompt: escapes backticks and dollar signs`

**As** a prompt builder,
**When** I call `sanitize_for_prompt` on text containing `` `cmd` `` and `$(cmd)`,
**Then** backticks are replaced with single quotes and `$` is escaped to `\$`.

### US-SAN-02: sanitize_for_prompt — clean content passes through
**Test:** `sanitize_for_prompt: clean content passes through unchanged`

**As** a prompt builder,
**When** I call `sanitize_for_prompt` on plain text with no shell metacharacters,
**Then** the output is identical to the input.

### US-SAN-03: sanitize_for_prompt — empty input
**Test:** `sanitize_for_prompt: empty input returns empty`

**As** a prompt builder,
**When** I call `sanitize_for_prompt ""`,
**Then** the result is empty.

### US-SAN-04: sanitize_for_prompt — escapes variable expansion
**Test:** `sanitize_for_prompt: escapes ${VAR} expansion`

**As** a prompt builder,
**When** I call `sanitize_for_prompt` on text containing `${HOME}`,
**Then** the `$` is escaped to `\$`, producing `\${HOME}`.

### US-SAN-05: sanitize_label — clean label passes through
**Test:** `sanitize_label: clean label passes through`

**As** a PR creator,
**When** I call `sanitize_label "agent-generated"`,
**Then** the output is `"agent-generated"` unchanged.

### US-SAN-06: sanitize_label — strips whitespace
**Test:** `sanitize_label: strips whitespace`

**As** a PR creator,
**When** I call `sanitize_label "  my-label  "`,
**Then** the output is `"my-label"`.

### US-SAN-07: sanitize_label — removes semicolons
**Test:** `sanitize_label: removes semicolons`

**As** a PR creator,
**When** I call `sanitize_label` on text containing a semicolon (`;`),
**Then** the semicolon is removed from the output.

### US-SAN-17: sanitize_label — removes pipes
**Test:** `sanitize_label: removes pipes`

**As** a PR creator,
**When** I call `sanitize_label` on text containing a pipe (`|`),
**Then** the pipe is removed from the output.

### US-SAN-18: sanitize_label — removes ampersands
**Test:** `sanitize_label: removes ampersands`

**As** a PR creator,
**When** I call `sanitize_label` on text containing an ampersand (`&`),
**Then** the ampersand is removed from the output.

### US-SAN-19: sanitize_label — removes redirect characters
**Test:** `sanitize_label: removes redirect characters`

**As** a PR creator,
**When** I call `sanitize_label` on text containing redirect characters (`>` or `<`),
**Then** those characters are removed from the output.

### US-SAN-20: sanitize_label — removes dollar signs
**Test:** `sanitize_label: removes dollar signs`

**As** a PR creator,
**When** I call `sanitize_label` on text containing a dollar sign (`$`),
**Then** the dollar sign is removed from the output.

### US-SAN-21: sanitize_label — removes backslashes
**Test:** `sanitize_label: removes backslashes`

**As** a PR creator,
**When** I call `sanitize_label` on text containing a backslash (`\`),
**Then** the backslash is removed from the output.

### US-SAN-08: sanitize_label — replaces double quotes with single quotes
**Test:** `sanitize_label: replaces double quotes with single`

**As** a PR creator,
**When** I call `sanitize_label` on text containing a double quote (`"`),
**Then** it is replaced with a single quote (`'`).

### US-SAN-22: sanitize_label — replaces backticks with single quotes
**Test:** `sanitize_label: replaces backticks with single quotes`

**As** a PR creator,
**When** I call `sanitize_label` on text containing a backtick (`` ` ``),
**Then** it is replaced with a single quote (`'`).

### US-SAN-09: sanitize_label — truncates to 50 characters
**Test:** `sanitize_label: truncates to 50 chars`

**As** a PR creator,
**When** I call `sanitize_label` on a 70-character string,
**Then** the output is exactly 50 characters.

### US-SAN-10: sanitize_label — empty input
**Test:** `sanitize_label: empty input returns empty`

**As** a PR creator,
**When** I call `sanitize_label ""`,
**Then** the result is empty.

### US-SAN-11: validate_requirement_content — clean content passes
**Test:** `validate_requirement_content: clean content returns 0`

**As** a pipeline runner,
**When** I call `validate_requirement_content` on normal text with no suspicious patterns,
**Then** it returns 0 with no warnings.

### US-SAN-12: validate_requirement_content — warns in non-strict mode
**Test:** `validate_requirement_content: warns but returns 0 in non-strict`

**As** a pipeline runner,
**When** I call `validate_requirement_content` on text containing `$(rm -rf /)` without strict mode,
**Then** it prints "Suspicious pattern" warnings to stderr but still returns 0.

### US-SAN-13: validate_requirement_content — rejects in strict mode
**Test:** `validate_requirement_content: returns 1 in strict mode`

**As** a pipeline runner,
**When** I call `validate_requirement_content` with `strict=true` on suspicious content,
**Then** it returns 1 and prints "Strict mode enabled" to stderr.

### US-SAN-14: validate_requirement_content — detects backtick substitution
**Test:** `validate_requirement_content: detects backtick substitution`

**As** a pipeline runner,
**When** I call `validate_requirement_content` on text containing backtick substitution (`` `cmd` ``),
**Then** it prints a "Suspicious pattern" warning.

### US-SAN-23: validate_requirement_content — detects variable expansion
**Test:** `validate_requirement_content: detects ${} expansion`

**As** a pipeline runner,
**When** I call `validate_requirement_content` on text containing variable expansion (`${VAR}`),
**Then** it prints a "Suspicious pattern" warning.

### US-SAN-24: validate_requirement_content — detects redirect to absolute path
**Test:** `validate_requirement_content: detects redirect to abs path`

**As** a pipeline runner,
**When** I call `validate_requirement_content` on text containing a redirect to an absolute path (`> /path`),
**Then** it prints a "Suspicious pattern" warning.

### US-SAN-25: validate_requirement_content — detects destructive rm -rf /
**Test:** `validate_requirement_content: detects rm -rf /`

**As** a pipeline runner,
**When** I call `validate_requirement_content` on text containing `rm -rf /`,
**Then** it prints a "Suspicious pattern" warning.

### US-SAN-26: validate_requirement_content — detects curl piped to sh
**Test:** `validate_requirement_content: detects curl pipe to sh`

**As** a pipeline runner,
**When** I call `validate_requirement_content` on text containing `curl ... | sh`,
**Then** it prints a "Suspicious pattern" warning.

### US-SAN-27: validate_requirement_content — detects eval injection
**Test:** `validate_requirement_content: detects eval`

**As** a pipeline runner,
**When** I call `validate_requirement_content` on text containing `eval `,
**Then** it prints a "Suspicious pattern" warning.

### US-SAN-28: validate_requirement_content — detects chmod 777
**Test:** `validate_requirement_content: detects chmod 777`

**As** a pipeline runner,
**When** I call `validate_requirement_content` on text containing `chmod 777`,
**Then** it prints a "Suspicious pattern" warning.

### US-SAN-29: validate_requirement_content — detects semicolon-chained rm
**Test:** `validate_requirement_content: detects semicolon-chained rm`

**As** a pipeline runner,
**When** I call `validate_requirement_content` on text containing `; rm`,
**Then** it prints a "Suspicious pattern" warning.

### US-SAN-30: validate_requirement_content — detects chained sudo escalation
**Test:** `validate_requirement_content: detects &&sudo`

**As** a pipeline runner,
**When** I call `validate_requirement_content` on text containing `&& sudo`,
**Then** it prints a "Suspicious pattern" warning.

### US-SAN-31: validate_requirement_content — detects pipe to sudo
**Test:** `validate_requirement_content: detects pipe to sudo`

**As** a pipeline runner,
**When** I call `validate_requirement_content` on text containing `| sudo`,
**Then** it prints a "Suspicious pattern" warning.

### US-SAN-15: validate_file_path — normal path passes
**Test:** `validate_file_path: passes for normal relative path`

**As** a path validator,
**When** I call `validate_file_path "src/main.sh" "/project"`,
**Then** it returns 0.

### US-SAN-16: validate_file_path — rejects leading path traversal
**Test:** `validate_file_path: rejects .. traversal`

**As** a path validator,
**When** I call `validate_file_path` with a path starting with traversal segments (e.g. `../../etc/passwd`),
**Then** it returns 1 and prints "Path traversal detected".

### US-SAN-32: validate_file_path — rejects mid-path traversal
**Test:** `validate_file_path: rejects mid-path .. traversal`

**As** a path validator,
**When** I call `validate_file_path` with a path containing traversal segments mid-path (e.g. `src/../../../etc/passwd`),
**Then** it returns 1 and prints "Path traversal detected".

---

## Module 4: config.sh

### US-CFG-01: find_manifest — finds in current directory
**Test:** `find_manifest: finds manifest in current dir`

**As** a CLI user,
**When** I run from a directory containing `reqdrive.json`,
**Then** `reqdrive_find_manifest` returns the full path to that file.

### US-CFG-02: find_manifest — walks up to parent
**Test:** `find_manifest: finds manifest in parent dir`

**As** a CLI user,
**When** I run from a nested subdirectory and `reqdrive.json` exists in a parent,
**Then** `reqdrive_find_manifest` finds and returns the parent's manifest path.

### US-CFG-03: find_manifest — returns 1 when not found
**Test:** `find_manifest: returns 1 when no manifest found`

**As** a CLI user,
**When** no `reqdrive.json` exists anywhere up the directory tree,
**Then** `reqdrive_find_manifest` returns 1.

### US-CFG-04: load_config — loads all settings from manifest
**Test:** `load_config: loads all settings`

**As** a pipeline runner,
**When** I call `reqdrive_load_config` with a fully-populated manifest,
**Then** `REQDRIVE_REQUIREMENTS_DIR`, `REQDRIVE_TEST_COMMAND`, `REQDRIVE_MODEL`, `REQDRIVE_MAX_ITERATIONS`, `REQDRIVE_BASE_BRANCH`, and `REQDRIVE_PROJECT_NAME` are all set to the manifest values.

### US-CFG-05: load_config — applies sensible defaults
**Test:** `load_config: uses defaults for missing fields`

**As** a pipeline runner,
**When** I call `reqdrive_load_config` on an empty `{}` manifest,
**Then** defaults are: `requirementsDir=docs/requirements`, `model=claude-sonnet-4-20250514`, `maxIterations=10`, `baseBranch=main`, `testCommand=""`, `projectName=""`, `prLabels=agent-generated`.

### US-CFG-06: load_config — sets REQDRIVE_MANIFEST to the manifest path
**Test:** `load_config: sets REQDRIVE_MANIFEST path`

**As** a pipeline runner,
**When** I call `reqdrive_load_config`,
**Then** `REQDRIVE_MANIFEST` is set to the full path of the found manifest.

### US-CFG-13: load_config — sets REQDRIVE_PROJECT_ROOT to the manifest's directory
**Test:** `load_config: sets REQDRIVE_PROJECT_ROOT to manifest dir`

**As** a pipeline runner,
**When** I call `reqdrive_load_config` from a subdirectory of the project,
**Then** `REQDRIVE_PROJECT_ROOT` is set to the manifest's parent directory.

### US-CFG-07: load_config — joins prLabels array into comma-separated string
**Test:** `load_config: joins prLabels with commas`

**As** a pipeline runner,
**When** the manifest has `"prLabels": ["a", "b", "c"]`,
**Then** `REQDRIVE_PR_LABELS` is set to `"a,b,c"`.

### US-CFG-14: load_config — defaults prLabels when omitted
**Test:** `load_config: defaults prLabels to agent-generated`

**As** a pipeline runner,
**When** I call `reqdrive_load_config` on a manifest with no `prLabels` field,
**Then** `REQDRIVE_PR_LABELS` is set to `"agent-generated"`.

### US-CFG-15: load_config — defaults testCommand when omitted
**Test:** `load_config: defaults testCommand to empty string`

**As** a pipeline runner,
**When** I call `reqdrive_load_config` on a manifest with no `testCommand` field,
**Then** `REQDRIVE_TEST_COMMAND` is set to `""`.

### US-CFG-16: load_config — defaults maxStoryRetries to 3
**Test:** `load_config: defaults maxStoryRetries to 3`

**As** a pipeline runner,
**When** I call `reqdrive_load_config` on a manifest with no `maxStoryRetries` field,
**Then** `REQDRIVE_MAX_STORY_RETRIES` is set to `"3"`.

### US-CFG-17: load_config — loads custom maxStoryRetries
**Test:** `load_config: loads custom maxStoryRetries`

**As** a pipeline runner,
**When** the manifest has `"maxStoryRetries": 5`,
**Then** `REQDRIVE_MAX_STORY_RETRIES` is set to `"5"`.

### US-CFG-18: load_config — defaults projectName when omitted
**Test:** `load_config: defaults projectName to empty string`

**As** a pipeline runner,
**When** I call `reqdrive_load_config` on a manifest with no `projectName` field,
**Then** `REQDRIVE_PROJECT_NAME` is set to `""`.

### US-CFG-08: load_config — exits on missing manifest
**Test:** `load_config: exits with error when no manifest`

**As** a CLI user,
**When** I call `reqdrive_load_config` and no manifest exists,
**Then** the process exits non-zero and prints "No reqdrive.json found" to stderr.

### US-CFG-09: load_config — exits on incompatible schema version
**Test:** `load_config: exits on incompatible schema version`

**As** a CLI user,
**When** I call `reqdrive_load_config` and the manifest has `"version": "9.0.0"`,
**Then** the process exits non-zero and prints "Incompatible config version" to stderr.

### US-CFG-10: get_req_file — finds matching requirement
**Test:** `get_req_file: finds matching requirement`

**As** a pipeline runner,
**When** I call `reqdrive_get_req_file "REQ-01"` and `docs/requirements/REQ-01-test-feature.md` exists,
**Then** it returns the full path to that file.

### US-CFG-11: get_req_file — returns 1 when no match
**Test:** `get_req_file: returns 1 when no match`

**As** a pipeline runner,
**When** I call `reqdrive_get_req_file "REQ-99"` and no matching file exists,
**Then** it returns 1.

### US-CFG-19: get_req_file — returns full path to matched file
**Test:** `get_req_file: returns full path to matched file`

**As** a pipeline runner,
**When** I call `reqdrive_get_req_file "REQ-02"` and `docs/requirements/REQ-02-another-feature.md` exists,
**Then** the returned path ends with `REQ-02-another-feature.md`.

### US-CFG-12: get_req_file — respects custom requirementsDir
**Test:** `get_req_file: respects custom requirementsDir`

**As** a pipeline runner,
**When** the manifest sets `"requirementsDir": "specs"` and `specs/REQ-05-custom.md` exists,
**Then** `reqdrive_get_req_file "REQ-05"` finds it.

---

## Module 5: run.sh

### US-RUN-01: write_run_status — creates valid run.json with all fields
**Test:** `run_status: creates valid run.json with all fields`

**As** a pipeline runner,
**When** I call `write_run_status` with a run directory, status `"running"`, and req ID `"REQ-01"`,
**Then** `run.json` exists and its `.status` is `"running"`, `.req_id` is `"REQ-01"`, `.pid` contains digits, and `.started_at` is non-empty.

### US-RUN-02: write_run_status — preserves started_at across calls
**Test:** `run_status: preserves started_at on subsequent calls`

**As** a status reporter,
**When** `write_run_status` is called a second time on the same run directory (with status `"completed"`, iteration 5, exit code 0),
**Then** `.started_at` in `run.json` is unchanged from the first call's value.

### US-RUN-03: write_run_status — records the writing process's PID
**Test:** `run_status: records current PID`

**As** a status reporter,
**When** `write_run_status` writes `run.json`,
**Then** the `.pid` field equals `$$`, the PID of the process that wrote it.

### US-RUN-04: write_run_status — includes summary when accumulators are set
**Test:** `run_status: includes summary when RUN_SUMMARY_* vars set`

**As** a pipeline runner,
**When** the `RUN_SUMMARY_*` variables (iterations, tests passed/failed, commits verified/missing, stories completed/failed/total, verification passed) are set before calling `write_run_status`,
**Then** `run.json`'s `.summary.iterations_run`, `.summary.tests_passed`, `.summary.tests_failed`, `.summary.commits_verified`, `.summary.commits_missing`, `.summary.stories_completed`, `.summary.stories_total`, and `.summary.verification_passed` each equal the corresponding `RUN_SUMMARY_*` value.

### US-RUN-05: write_run_status — summary is null when accumulators are unset
**Test:** `run_status: summary is null when accumulators not set`

**As** a pipeline runner,
**When** `RUN_SUMMARY_ITERATIONS` (and the other accumulators) are unset before calling `write_run_status`,
**Then** `.summary` in `run.json` is the JSON literal `null`.

### US-RUN-06: write_run_status — summary output is valid JSON
**Test:** `run_status: run.json with summary is valid JSON`

**As** a pipeline runner,
**When** `write_run_status` writes `run.json` with the `RUN_SUMMARY_*` accumulators populated,
**Then** `jq empty run.json` succeeds — the file parses as valid JSON.

### US-RUN-07: save_checkpoint — creates valid checkpoint.json
**Test:** `checkpoint: save_checkpoint creates valid checkpoint.json`

**As** a pipeline runner,
**When** I call `save_checkpoint` with req ID `"REQ-01"`, branch `"reqdrive/req-01"`, and iteration `3`,
**Then** `checkpoint.json` exists with `.req_id` containing `"REQ-01"`, `.branch` containing `"reqdrive/req-01"`, and `.iteration` equal to `"3"`.

### US-RUN-08: save_checkpoint — records completed story IDs from the PRD
**Test:** `checkpoint: records completed story IDs from PRD`

**As** a pipeline runner,
**When** `save_checkpoint` runs against a PRD where only `US-001` has `"passes": true`,
**Then** `checkpoint.json`'s `.stories_complete[0]` is `"US-001"` and `.stories_complete` has length `1`.

### US-RUN-09: load_checkpoint — returns the path for a matching req_id
**Test:** `checkpoint: load returns path for matching req_id`

**As** a pipeline runner,
**When** I call `load_checkpoint` on a directory whose `checkpoint.json` has `"req_id": "REQ-01"`, passing `"REQ-01"`,
**Then** the result is non-empty and ends in `checkpoint.json`.

### US-RUN-10: load_checkpoint — returns empty for a mismatched req_id
**Test:** `checkpoint: load returns empty for mismatched req_id`

**As** a pipeline runner,
**When** I call `load_checkpoint` on a directory whose `checkpoint.json` has `"req_id": "REQ-01"`, passing `"REQ-99"`,
**Then** the result is empty.

### US-RUN-11: load_checkpoint — returns empty when the file is missing
**Test:** `checkpoint: load returns empty for missing file`

**As** a pipeline runner,
**When** I call `load_checkpoint` on a directory with no `checkpoint.json`,
**Then** the result is empty.

### US-RUN-12: save_checkpoint — includes last_commit_sha
**Test:** `checkpoint: save_checkpoint includes last_commit_sha`

**As** a pipeline runner,
**When** `save_checkpoint` runs inside a git repository with at least one commit,
**Then** `checkpoint.json`'s `.last_commit_sha` is non-empty and not the literal string `"null"`.

### US-RUN-13: select_next_story — returns the lowest-priority incomplete story
**Test:** `story: select_next_story returns lowest-priority incomplete`

**As** the pipeline orchestrator,
**When** the PRD has `US-001` (priority 1, `passes: true`), `US-002` (priority 2, `passes: false`), and `US-003` (priority 3, `passes: false`),
**Then** `select_next_story` returns `"US-002"` — the lowest-priority-number story that has not yet passed.

### US-RUN-14: select_next_story — returns empty when every story passes
**Test:** `story: select_next_story returns empty when all pass`

**As** the pipeline orchestrator,
**When** every story in the PRD has `"passes": true`,
**Then** `select_next_story` returns an empty string.

### US-RUN-15: select_next_story — returns empty for a missing PRD file
**Test:** `story: select_next_story returns empty for missing PRD`

**As** the pipeline orchestrator,
**When** `select_next_story` is called with a path to a PRD file that does not exist,
**Then** it returns an empty string (no error).

### US-RUN-16: get_story_details — returns the correct story by ID
**Test:** `story: get_story_details returns correct story by ID`

**As** the pipeline orchestrator,
**When** I call `get_story_details` with `"US-002"` against a PRD containing `US-001` ("First Story") and `US-002` ("Second Story"),
**Then** the returned JSON's `.title` is `"Second Story"`.

### US-RUN-17: select_next_story — skips stories with attempts at or above the max
**Test:** `story: select_next_story skips stories with attempts >= max`

**As** the pipeline orchestrator,
**When** the PRD has `US-001` (priority 1, `attempts: 3`) and `US-002` (priority 2, `attempts: 1`), and `select_next_story` is called with max `3`,
**Then** it returns `"US-002"`, skipping `US-001` whose `attempts` (3) is not less than the max (3).

### US-RUN-18: select_next_story — returns a story with attempts below the max
**Test:** `story: select_next_story returns story with attempts < max`

**As** the pipeline orchestrator,
**When** the PRD has `US-001` (priority 1, `attempts: 2`) and `US-002` (priority 2, no `attempts` field), and `select_next_story` is called with max `3`,
**Then** it returns `"US-001"` — its attempts (2) are below the max, and it has the lower priority number.

### US-RUN-19: select_next_story — returns empty when all stories are exhausted or complete
**Test:** `story: select_next_story returns empty when all exhausted`

**As** the pipeline orchestrator,
**When** the PRD has `US-001` (`passes: false`, `attempts: 3`) and `US-002` (`passes: true`), and `select_next_story` is called with max `3`,
**Then** it returns an empty string — the incomplete story has exhausted its retries and the other has already passed.

### US-RUN-20: build_planning_prompt — includes the requirement content
**Test:** `prompt: build_planning_prompt includes requirement content`

**As** a pipeline runner,
**When** I call `build_planning_prompt` with requirement text `"This is the requirement content."`,
**Then** the generated prompt file contains that text verbatim.

### US-RUN-21: build_planning_prompt — includes the PRD schema
**Test:** `prompt: build_planning_prompt includes PRD schema`

**As** a pipeline runner,
**When** I call `build_planning_prompt`,
**Then** the generated prompt file contains both the literal string `"PRD Schema"` and `"userStories"`.

### US-RUN-22: build_planning_prompt — preserves dollar signs in content
**Test:** `prompt: build_planning_prompt preserves dollar signs in content`

**As** a pipeline runner,
**When** I call `build_planning_prompt` with requirement text `"Check $HOME variable"`,
**Then** the generated prompt file contains the literal text `$HOME` — the planning prompt's quoted heredoc does not expand it.

### US-RUN-23: run_completion_hook — executes the configured command with env vars
**Test:** `hook: executes command with env vars`

**As** a pipeline runner,
**When** `REQDRIVE_COMPLETION_HOOK` is set to a command that echoes `$REQ_ID $STATUS $PR_URL $BRANCH $EXIT_CODE`, and I call `run_completion_hook "REQ-01" "completed" "https://pr.url" "reqdrive/req-01" "0"`,
**Then** the hook's output contains `"REQ-01"`, `"completed"`, and `"https://pr.url"` — the function exports these as env vars for the hook command.

### US-RUN-24: run_completion_hook — no-op when the hook is unset
**Test:** `hook: no-op when hook is empty`

**As** a pipeline runner,
**When** `REQDRIVE_COMPLETION_HOOK` is `""` and I call `run_completion_hook`,
**Then** it returns success without running any command.

### US-RUN-25: run_completion_hook — a failing hook does not propagate
**Test:** `hook: handles failing hook gracefully`

**As** a pipeline runner,
**When** `REQDRIVE_COMPLETION_HOOK` is set to `"exit 42"` and I call `run_completion_hook`,
**Then** `run_completion_hook` itself still returns success — the hook's non-zero exit does not abort the caller.

### US-RUN-26: extract_iteration_summary — extracts a valid summary block
**Test:** `summary: extract_iteration_summary extracts valid block`

**As** a pipeline runner,
**When** the agent output contains a fenced ` ```json:iteration-summary ` block with `"storyId": "US-003"`,
**Then** `iteration-1.summary.json` is created and its `.storyId` is `"US-003"`.

### US-RUN-27: extract_iteration_summary — handles output with no summary block
**Test:** `summary: handles missing summary gracefully`

**As** a pipeline runner,
**When** the agent output contains no ` ```json:iteration-summary ` block,
**Then** `extract_iteration_summary` does not create `iteration-1.summary.json`.

### US-RUN-28: build_implementation_prompt — neutralizes $(cmd) in the story title
**Test:** `impl prompt: neutralizes $(cmd) in story title`

**As** a pipeline runner,
**When** a story's `title` is `$(echo pwned)` and I call `build_implementation_prompt`,
**Then** the prompt file contains the literal (unexpanded) text `$(echo pwned)` and the word `pwned` never appears alone on its own line — the command substitution was never executed.

### US-RUN-29: build_implementation_prompt — neutralizes backticks in the story description
**Test:** `impl prompt: neutralizes backticks in story description`

**As** a pipeline runner,
**When** a story's `description` is `` Use `whoami` to attack `` and I call `build_implementation_prompt`,
**Then** the prompt file contains no raw `` `whoami` `` backtick sequence, but does contain the sanitized text `Use 'whoami' to attack` and the title line `**Title:** Safe title`.

### US-RUN-30: build_implementation_prompt — neutralizes ${VAR} in acceptance criteria
**Test:** `impl prompt: neutralizes ${VAR} in acceptance criteria`

**As** a pipeline runner,
**When** a story's `acceptanceCriteria` includes `"Check ${HOME} variable"` and I call `build_implementation_prompt`,
**Then** the prompt file does not contain the shell-expanded `$HOME` path, but does contain the criterion text `Check ${HOME} variable` (the `$` reaches the agent without a stray backslash, per Task 28) and `US-003`.

### US-RUN-31: select_next_story — selects a story that omits the passes field
**Test:** `story: select_next_story selects a story omitting passes`

**As** the pipeline orchestrator,
**When** the PRD has `US-001` (`passes: true`, priority 1) and `US-002` (priority 2, no `passes` field at all), and `select_next_story` is called,
**Then** it returns `"US-002"` — a story that omits `passes` is treated as incomplete (`passes != true`), matching Phase 3's completion predicate, so it remains selectable rather than being permanently skipped.

---

### US-RUN-32: build_implementation_prompt — matches the frozen golden file byte for byte
**Test:** `prompt: implementation prompt matches golden file`

**As** the maintainer preparing to rewrite `build_implementation_prompt`'s unquoted heredoc,
**When** the function is called with the fixed fixture `tests/fixtures/golden-story.json` (id `US-042`, a title/description/criteria containing `&`, `\`, a backtick, `$`, and a literal `@@STORY_ID@@` placeholder) and requirement content `Requirement body with & and $VAR`,
**Then** the generated prompt is byte-identical to `tests/fixtures/golden-impl-prompt.md` — this characterization test locks the current output, including the forgery-strip guard that turns the fixture's literal `@@STORY_ID@@` into inert text `STORY_ID`, so a future heredoc rewrite can be verified byte-identical against this oracle before any further deliberate behavior change is made.

---

### US-RUN-33: build_implementation_prompt — the patsub_replacement shopt guard survives bash without that option
**Test:** `prompt: shopt guard tolerates bash without patsub_replacement`

**As** the maintainer running the pipeline on a pre-5.2 bash where `patsub_replacement` does not exist,
**When** `shopt -u definitely_not_an_option 2>/dev/null || true` is executed under `set -e` (standing in for an unknown shopt name), and separately, `lib/run.sh` is checked for the literal guard line,
**Then** the unknown-option case does not abort the script (`SURVIVED` is printed) and `lib/run.sh` contains `shopt -u patsub_replacement 2>/dev/null || true` — pinning both the general `|| true` idiom and the exact guard line `build_implementation_prompt` relies on to stay portable across bash versions.

---

### US-RUN-34: build_implementation_prompt — PRD content cannot forge a placeholder token
**Test:** `prompt: PRD content cannot forge a placeholder token`

**As** the maintainer defending against prompt-injection via the PRD,
**When** `build_implementation_prompt` is called with a story titled `@@STORY_ID@@ and @@REQUIREMENT@@` and requirement content `body text`,
**Then** the rendered prompt contains no `@@` sequence anywhere and still contains the literal text `body text` — the forgery-strip guard removes `@@` from every injected value before substitution, so a PRD-supplied value cannot masquerade as a placeholder that a later substitution pass would expand.

---

### US-RUN-35: build_implementation_prompt — an ampersand in a title is not expanded to the match
**Test:** `prompt: ampersand in a title is not expanded to the match`

**As** the maintainer relying on bash's `${var//pat/repl}` substitution semantics,
**When** `build_implementation_prompt` is called with a story titled `auth & billing`,
**Then** the rendered prompt contains the line `**Title:** auth & billing` verbatim — the unquoted `&`-expands-to-match behavior (default before bash 5.2, or without the `patsub_replacement` guard) does not corrupt injected PRD content.

---

### US-RUN-36: build_implementation_prompt — dollar signs reach the agent without stray backslashes
**Test:** `prompt: dollar signs reach the agent without stray backslashes`

**As** the maintainer who removed the unquoted-heredoc justification for escaping `$`,
**When** `build_implementation_prompt` is called with a story titled `Fix $HOME handling`,
**Then** the rendered prompt contains the line `**Title:** Fix $HOME handling` verbatim, contains no stray `\$` before `HOME`, and the commit-message line reads `feat: [US-9] - Fix $HOME handling` — `sanitize_for_prompt`'s `$` → `\$` escaping (still load-bearing for its other callers) is reversed at injection time so the agent never sees a backslash that was only ever needed for the old unquoted heredoc.

### US-RUN-37: write_run_status — JSON-escapes pr_url (F8 root cause)
**Test:** `run_status: pr_url with special chars stays valid JSON`

**As** the maintainer closing out F8,
**When** `write_run_status` is called with a `pr_url` containing an embedded newline and a double-quote,
**Then** `run.json` still parses as valid JSON (`jq -e .` succeeds) and `.pr_url` round-trips the original value — `pr_url` is now interpolated via `jq -Rn --arg` instead of raw double-quoting, so raw `gh`/`git` stdout containing special characters can no longer corrupt `run.json` for every downstream `jq` consumer (`status`, `verify`'s pid guard).

---

## Module 6: bin/reqdrive (CLI)

### US-CLI-01: --version prints the schema version
**Test:** `cli: --version shows 0.3.0`

**As** a CLI user,
**When** I run `reqdrive --version`,
**Then** the output contains the string `0.3.0`.

### US-CLI-02: --help prints command usage
**Test:** `cli: --help shows usage`

**As** a CLI user,
**When** I run `reqdrive --help`,
**Then** the output contains `Usage:` and mentions the `init`, `run`, and `validate` commands.

### US-CLI-03: --help lists the security-related flags
**Test:** `cli: --help shows security flags`

**As** a CLI user,
**When** I run `reqdrive --help`,
**Then** the output contains the flags `--interactive`, `--unsafe`, `--force`, and `--resume`.

### US-CLI-04: Unknown command prints an error message
**Test:** `cli: unknown command shows error`

**As** a CLI user,
**When** I run `reqdrive unknown-cmd`,
**Then** the output contains the message `Unknown command`.

### US-CLI-05: validate reports a passing manifest
**Test:** `cli: validate command works`

**As** a CLI user,
**When** I run `reqdrive validate` against a project with a valid `reqdrive.json` and an existing `requirementsDir`,
**Then** the output contains `Validation PASSED`.

### US-CLI-06: run requires a REQ-ID argument
**Test:** `cli: run requires REQ-ID argument`
**Environment:** requires the `claude` binary; skipped under the same test name when absent.

**As** a CLI user,
**When** I run `reqdrive run` with no REQ-ID argument,
**Then** the output contains `Usage: reqdrive run`.

### US-CLI-07: status with no runs reports none found
**Test:** `cli: status with no runs shows 'No runs found'`

**As** a CLI user,
**When** I run `reqdrive status` in a project with a valid `reqdrive.json` and no `.reqdrive/runs/` entries,
**Then** the output contains `No runs found`.

### US-CLI-08: status with a run.json prints its status fields
**Test:** `cli: status with run.json shows status fields`

**As** a CLI user,
**When** I run `reqdrive status` and `.reqdrive/runs/req-01/run.json` exists with `req_id: "REQ-01"` and `status: "completed"`,
**Then** the output contains both `REQ-01` and `completed`.

### US-CLI-09: logs with no log file reports an error
**Test:** `cli: logs with missing log file shows error`

**As** a CLI user,
**When** I run `reqdrive logs REQ-01` and no `output.log` exists for that run,
**Then** the output contains `No log file found`.

### US-CLI-10: migrate adds a version field to a versionless config
**Test:** `cli: migrate adds version to versionless config`

**As** a CLI user,
**When** I run `reqdrive migrate` against a `reqdrive.json` with no `version` field,
**Then** the output contains `Updated: reqdrive.json` and the config's `.version` field is set to `0.3.0`.

### US-CLI-11: migrate skips a config that already has a version
**Test:** `cli: migrate skips config that already has version`

**As** a CLI user,
**When** I run `reqdrive migrate` against a `reqdrive.json` that already has `"version":"0.3.0"`,
**Then** the output contains `Skipped: reqdrive.json`.

### US-CLI-12: plan requires a REQ-ID argument
**Test:** `cli: plan without args shows usage`
**Environment:** requires the `claude` binary; skipped under the same test name when absent.

**As** a CLI user,
**When** I run `reqdrive plan` with no REQ-ID argument,
**Then** the output contains `Usage: reqdrive plan`.

### US-CLI-13: orchestrate reports it is not yet implemented
**Test:** `cli: orchestrate shows 'coming soon'`

**As** a CLI user,
**When** I run `reqdrive orchestrate`,
**Then** the output contains the case-insensitive phrase `coming soon`.

### US-CLI-14: verify re-runs verification and preserves the evidence trail
**Test:** `verify: merge mode preserves the evidence trail`

**As** an operator re-verifying a completed run,
**When** I run `reqdrive verify REQ-01` against a run whose `verification-summary.json` already records `iterations.run` and `commits.verified`,
**Then** those two fields are unchanged afterward — merge mode refreshes the pass/fail verdict without zeroing the evidence trail `pr-create` renders into the PR table.

### US-CLI-15: verify exits 9 when the re-run test command fails
**Test:** `verify: exits 9 when verification fails`

**As** an operator re-verifying a run whose `testCommand` now fails,
**When** I run `reqdrive verify REQ-01` and the configured `testCommand` exits non-zero,
**Then** the command exits `9` (`EXIT_VERIFICATION_FAILED`).

### US-CLI-16: verify exits 3 for a REQ-ID with no run directory
**Test:** `verify: exits 3 for an unknown REQ-ID`

**As** an operator who mistyped a REQ-ID,
**When** I run `reqdrive verify REQ-99` and no `.reqdrive/runs/req-99/` directory exists,
**Then** the command exits `3` (`EXIT_CONFIG_ERROR`) and the error message names `req-99`.

### US-CLI-17: verify refuses to run while the run's PID is alive
**Test:** `verify: exits 10 while the run PID is alive`

**As** an operator who might otherwise race a still-running pipeline,
**When** I run `reqdrive verify REQ-01` and `run.json`'s recorded `pid` belongs to a live process,
**Then** the command exits `10` (`EXIT_CONCURRENT_RUN`) instead of writing a concurrent `verification-summary.json`.

### US-CLI-18: verify refuses a run with no checkpoint when no --ref is given
**Test:** `verify: refuses a run with no checkpoint when no --ref given`

**As** an operator verifying a run whose Phase-2 loop never wrote a checkpoint (e.g. an empty `userStories` array or `maxIterations: 0`),
**When** I run `reqdrive verify REQ-01` with no `--ref` and `checkpoint.json` is missing,
**Then** the command exits `3` (`EXIT_CONFIG_ERROR`) instead of silently recording whatever branch happens to be checked out as that REQ-ID's evidence.

### US-CLI-19: verify exits 4 when --ref names a nonexistent branch
**Test:** `verify: exits 4 when --ref names a nonexistent branch`

**As** an operator who mistyped a `--ref` branch name,
**When** I run `reqdrive verify REQ-01 --ref does-not-exist` and that branch does not exist,
**Then** the command exits `4` (`EXIT_GIT_ERROR`) — matching the README's documented exit code — instead of aborting with git's raw exit status `1` under `set -euo pipefail`.

---

## Module 7: preflight.sh

### US-PRE-01: check_git_repo fails outside a git repository
**Test:** `preflight: check_git_repo fails outside repo`

**As** a preflight checker,
**When** I call `check_git_repo` from a directory with no `.git`,
**Then** it returns non-zero.

### US-PRE-02: check_clean_working_tree passes on a clean repo
**Test:** `preflight: check_clean_working_tree passes on clean repo`

**As** a preflight checker,
**When** I call `check_clean_working_tree` in a repo with a committed file and no pending changes,
**Then** it returns 0.

### US-PRE-03: check_clean_working_tree fails on a dirty repo
**Test:** `preflight: check_clean_working_tree fails on dirty repo`

**As** a preflight checker,
**When** I call `check_clean_working_tree` in a repo with an uncommitted modification,
**Then** it returns non-zero.

### US-PRE-04: check_base_branch_exists passes for a local branch
**Test:** `preflight: check_base_branch_exists passes for local branch`

**As** a preflight checker,
**When** I call `check_base_branch_exists` with the name of the currently checked-out local branch,
**Then** it returns 0.

### US-PRE-05: check_requirements_dir passes when the dir has .md files
**Test:** `preflight: check_requirements_dir passes with .md files`

**As** a preflight checker,
**When** I call `check_requirements_dir` on a directory that exists and contains at least one `.md` file,
**Then** it returns 0.

### US-PRE-06: check_requirement_exists finds a matching requirement file
**Test:** `preflight: check_requirement_exists finds matching file`

**As** a preflight checker,
**When** I call `check_requirement_exists "REQ-01"` against a requirements directory containing `REQ-01-test-feature.md`,
**Then** it returns 0.

### US-PRE-07: check_test_command_configured warns when testCommand is empty
**Test:** `preflight: warns when no testCommand is configured`

**As** a preflight checker,
**When** I call `check_test_command_configured` with `REQDRIVE_TEST_COMMAND` unset/empty,
**Then** it prints a warning containing "all PRs will be created as drafts" and still returns 0.

### US-PRE-08: check_test_command_configured is silent when testCommand is set
**Test:** `preflight: silent when testCommand is configured`

**As** a preflight checker,
**When** I call `check_test_command_configured` with `REQDRIVE_TEST_COMMAND` set to a non-empty command,
**Then** it prints nothing.

---

## Module 8: pr-create.sh

### US-PR-01: create_pr writes the PR URL to stdout
**Test:** `pr: create_pr outputs URL to stdout`

**As** a pipeline runner,
**When** I call `create_pr` and the (mocked) `gh pr create` succeeds,
**Then** `create_pr`'s stdout contains the PR URL (`https://github.com/test/repo/pull/42`).

### US-PR-02: create_pr retries without labels when the labeled attempt fails
**Test:** `pr: create_pr retries without labels on failure`

**As** a pipeline runner,
**When** `REQDRIVE_PR_LABELS` is set and the first `gh pr create` attempt (with labels) fails,
**Then** `create_pr` retries `gh pr create` without labels, and its stdout contains the PR URL from the successful retry (`https://github.com/test/repo/pull/99`).

### US-PR-03: create_pr returns non-zero when gh fails with no labels to drop
**Test:** `pr: create_pr returns non-zero on gh failure without labels`

**As** a pipeline runner,
**When** `REQDRIVE_PR_LABELS` is empty and `gh pr create` fails,
**Then** `create_pr` returns non-zero (there is no unlabeled retry left to attempt).

### US-PR-04: PR body includes the verification section when a summary exists
**Test:** `pr: body includes verification section from summary`

**As** a pipeline runner,
**When** `verification-summary.json` exists in the run directory and I call `create_pr`,
**Then** the PR body passed to `gh pr create` contains a "Pipeline Verification" heading, along with `"2 / 3 completed"` (stories) and `"5 / 10 used"` (iterations) drawn from the summary.

### US-PR-05: PR body omits the verification section when no summary exists
**Test:** `pr: body omits verification section when no summary file`

**As** a pipeline runner,
**When** no `verification-summary.json` exists in the run directory and I call `create_pr`,
**Then** the PR body passed to `gh pr create` does not contain "Pipeline Verification".

### US-PR-06: PR body states why verification was not run
**Test:** `pr: body states why verification was not run`

**As** a pipeline runner,
**When** a full scripted pipeline run completes with no `testCommand` configured (`verification_passed` is `null`),
**Then** the PR body passed to `gh pr create` contains the reason "no test command configured".

---

## Module 9: init.sh

### US-INIT-01: init creates reqdrive.json with version 0.3.0
**Test:** `init: creates reqdrive.json with version 0.3.0`

**As** a CLI user,
**When** I run the init wizard accepting the default answer at every prompt,
**Then** `reqdrive.json` is created and its `.version` field is `0.3.0`.

### US-INIT-02: init creates the .reqdrive/runs directory
**Test:** `init: creates .reqdrive/runs/ directory`

**As** a CLI user,
**When** I run the init wizard accepting the default answer at every prompt,
**Then** a `.reqdrive/runs` directory is created.

---

## Module 10: review phase

### US-REV-01: load_config defaults reviewCommand to empty string
**Test:** `review: config defaults reviewCommand to empty string`

**As** a pipeline runner,
**When** I call `reqdrive_load_config` on a manifest with no `reviewCommand` field,
**Then** `REQDRIVE_REVIEW_COMMAND` is set to `""`.

### US-REV-02: load_config reads reviewCommand from the manifest
**Test:** `review: config reads reviewCommand from JSON`

**As** a pipeline runner,
**When** the manifest has `"reviewCommand": "builtin"` and I call `reqdrive_load_config`,
**Then** `REQDRIVE_REVIEW_COMMAND` is set to `"builtin"`.

### US-REV-03: Config schema accepts a string reviewCommand
**Test:** `review: schema accepts string reviewCommand`

**As** a validator,
**When** I call `validate_config_schema` on a file where `reviewCommand` is a string,
**Then** it returns 0.

### US-REV-04: Config schema rejects a non-string reviewCommand
**Test:** `review: schema rejects non-string reviewCommand`

**As** a validator,
**When** I call `validate_config_schema` on a file where `reviewCommand` is a number,
**Then** it returns 1 and prints "reviewCommand must be a string".

### US-REV-05: update_pr_with_review formats findings into the PR body
**Test:** `review: update_pr_with_review formats findings correctly`

**As** a pipeline runner,
**When** I call `update_pr_with_review` against a `review-findings.json` containing findings with `severity`, `file`, and `message` fields,
**Then** the updated PR body (passed to `gh pr edit --body`) contains a "Code Review Findings" heading and includes each finding's message (e.g. "Missing null check") and severity (e.g. "warning").

---

## Module 11: validate + harness

### US-VAL-01: validate reports PASSED for a valid manifest
**Test:** `validate: passes for valid manifest`

**As** a CLI user,
**When** I source `validate.sh` against a loaded config with a valid `reqdrive.json` and an existing `requirementsDir`,
**Then** the output contains "Validation PASSED".

### US-VAL-02: validate exits non-zero for invalid JSON
**Test:** `validate: fails for invalid JSON`

**As** a CLI user,
**When** `reqdrive.json` contains invalid JSON and I source `validate.sh`,
**Then** it exits with a non-zero status.

### US-VAL-03: validate exits EXIT_CONFIG_ERROR on malformed config
**Test:** `validate: exits 3 (EXIT_CONFIG_ERROR) on malformed config`

**As** a CLI user,
**When** I run `reqdrive validate` against a `reqdrive.json` that is not valid JSON at all,
**Then** it exits with status 3 (`EXIT_CONFIG_ERROR`), not a bare 1.

### US-VAL-04: validate exits EXIT_CONFIG_ERROR on a schema type violation
**Test:** `validate: exits 3 on a config type violation`

**As** a CLI user,
**When** I run `reqdrive validate` against a `reqdrive.json` where a field has the wrong type (e.g. `maxIterations` is a string),
**Then** it exits with status 3 (`EXIT_CONFIG_ERROR`), not a bare 1.

### US-HARN-01: Suite refuses to run when mktemp fails
**Test:** `harness: aborts when mktemp fails`

**As** a test runner,
**When** `mktemp -d` fails and the suite is invoked,
**Then** it prints `FATAL: mktemp failed` and exits non-zero before any assertion runs, so no assertion can operate on an empty `TEST_TEMP`.

---

## Module 12: pipeline harness

### US-PIPE-01: A scripted run drives run_pipeline through to PR creation
**Test:** `pipeline: scripted run reaches PR creation`

**As** a test author,
**When** I use `tests/lib/pipeline-harness.sh` to scaffold a scratch git repo, install a fake `claude` (mode `full`) and a fake `gh`, and call `ph_run REQ-01`,
**Then** `run_pipeline` completes with exit code 0 and the fake `gh` log records a `pr create` invocation, proving the pipeline actually reached PR creation rather than stopping earlier.

### US-PIPE-02: verification-summary.json keeps its full shape after the Phase 3 extraction
**Test:** `verification: summary keeps its full shape`

**As** a maintainer who extracted `run_pipeline`'s inline Phase 3 block into `lib/verification.sh` (`verify_collect`, `verify_run_tests`, `verify_write_summary`),
**When** a scripted `ph_run REQ-01` completes,
**Then** `verification-summary.json` still has `.version`, `.stories.{total,completed,failed,remaining}`, `.iterations.{run,max}` with `.iterations.max` not null, `.prd_present`, `.tests.{passed,failed,skipped}`, and `.commits.{verified,missing}` — proving the refactor is output-preserving, not just syntactically valid.

## Module 13: draft gate

### US-DRAFT-01: No testCommand means no evidence, so the PR is a draft
**Test:** `draft gate: no testCommand forces draft`

**As** a maintainer relying on the draft-PR gate as a safety net,
**When** a run completes with `testCommand` unset (so `verification_passed` is `null`, not the literal string `"false"`),
**Then** the gate does not treat `null` as passing evidence — `gh pr create` is invoked with `--draft`.

### US-DRAFT-02: A missing prd.json means planning failed, so the pipeline aborts with no PR
**Test:** `draft gate: planning failure aborts with no PR`

**As** a maintainer relying on the pipeline's fail-safes,
**When** the agent never produces `prd.json` (planning exhausts its retries with no PRD on disk),
**Then** the pipeline hard-aborts with `EXIT_AGENT_ERROR` (5), the run is marked `failed`, and `gh pr create` is never invoked — no empty draft PR is opened for a run that never planned.

### US-DRAFT-03: Stories omitting 'passes' are not complete, so the PR is a draft
**Test:** `draft gate: stories omitting passes force draft`

**As** a maintainer relying on the draft-PR gate as a safety net,
**When** every story in `prd.json` omits the optional `passes` field,
**Then** counting `select(.passes != true)` (not `select(.passes == false)`) correctly treats every such story as incomplete, and `gh pr create` is invoked with `--draft`.

### US-DRAFT-04: Full evidence produces a non-draft PR
**Test:** `draft gate: full evidence produces non-draft PR`

**As** a maintainer relying on the draft-PR gate as a safety net,
**When** `prd.json` exists, every story has `passes: true`, and `testCommand` runs and passes (`verification_passed` is the literal string `"true"`),
**Then** `gh pr create` is invoked without `--draft` — proving the fix does not simply force every PR to draft unconditionally.

## Module 14: doc coverage

### US-DOC-01: Every dispatch command is documented in README
**Test:** `docs: every CLI command is documented in README`

**As** a maintainer relying on the README as the source of truth for the CLI surface,
**When** the dispatch `case` block in `bin/reqdrive` is parsed for command labels (excluding `-v|--version`, `-h|--help|""`, and `*`),
**Then** every remaining command appears in `README.md` — so adding a new dispatch command without documenting it fails the suite.

### US-DOC-02: Every config field is documented in README
**Test:** `docs: every config field is documented in README`

**As** a maintainer relying on the README as the source of truth for `reqdrive.json`,
**When** every `REQDRIVE_[A-Z_]+` variable exported by `lib/config.sh` is collected, the three derived-path variables (`REQDRIVE_MANIFEST`, `REQDRIVE_PROJECT_ROOT`, `REQDRIVE_ROOT`) are exempted as not settable config fields, and each remaining variable's snake_case suffix is converted to its camelCase `reqdrive.json` field name (e.g. `MAX_STORY_RETRIES` -> `maxStoryRetries`),
**Then** every derived field name appears in `README.md` — so adding a new config field without documenting it fails the suite.

### US-DOC-03: Every accepted CLI flag is documented in README
**Test:** `docs: every CLI flag is documented in README`

**As** a maintainer relying on the README as the source of truth for the CLI's accepted flags,
**When** the option-parsing `case` blocks in `bin/reqdrive` (the `run`/`launch` block and the `plan` block) are parsed for case labels matching `^(-[a-z]\|)?--[a-z-]+(\|--[a-z-]+)*\)$` and split on `|` — so free `--` literals inside strings, such as the `--help` inside the usage message `echo "Run 'reqdrive run --help' for usage."`, are not mistaken for flags,
**Then** every extracted flag (`--interactive`, `--unsafe`, `--dangerously-skip-permissions`, `--force`, `--resume`) appears in `README.md` — so adding a new accepted flag, or an alias like `--dangerously-skip-permissions`, without documenting it fails the suite.

## Module 15: launch lifecycle

State-transition cases from `docs/LAUNCH-TEST-PLAN.md` (cases 2, 5, 7, 8):
asserted directly on `run.json` and CLI output, without spawning a real
background process. Cases 1, 4 and 6 need real process liveness and signal
semantics that are unreliable under MSYS2, so they run only in the
Linux-only `launch-lifecycle` CI job (`tests/launch-lifecycle.sh`), which is
not part of this spec (no story, not locked).

### US-LAUNCH-01: Status reports a completed run with its PR URL
**Test:** `launch: status reports a completed run with its PR URL`

**As** an operator checking on a finished background run,
**When** `run.json` has `status: "completed"`, `exit_code: 0`, and a `pr_url`, and `reqdrive status REQ-01` is invoked,
**Then** the output shows `completed` and the PR URL, so a finished run's outcome is visible without reading `run.json` by hand.

### US-LAUNCH-02: Status reports a crashed run when the PID is gone
**Test:** `launch: status reports a crashed run when the PID is gone`

**As** an operator checking on a background run that may have died unexpectedly,
**When** `run.json` still says `status: "running"` but its recorded `pid` (`999999`, reliably dead — above Linux's default `pid_max`) is no longer alive, and `reqdrive status REQ-01` is invoked,
**Then** the output reports `crashed`, so a stale "running" status left behind by a killed process is not mistaken for an active run.

### US-LAUNCH-03: Completion hook passes REQ_ID, STATUS and EXIT_CODE
**Test:** `launch: completion hook passes REQ_ID, STATUS and EXIT_CODE`

**As** a maintainer wiring `completionHook` up to external notifications,
**When** `run_completion_hook` is called with a req id, status and exit code, and the configured hook command echoes `$REQ_ID`, `$STATUS` and `$EXIT_CODE` to a file,
**Then** the file contains the exact values passed in, so the hook's environment contract is proven, not just its existence.

### US-LAUNCH-04: Re-launch is permitted after the previous run completed
**Test:** `launch: re-launch is permitted after the previous run completed`

**As** an operator re-running a requirement after a prior run finished,
**When** `run.json` exists with `status: "completed"` (not `"running"`) and `reqdrive launch REQ-01` is invoked,
**Then** the duplicate-run guard is skipped and `launch` prints `Launched REQ-01` rather than an `already running` error, so only a genuinely in-flight run blocks a re-launch.

## Module 16: policy config

`policy` is an optional object inside `reqdrive.json` — one file, one loader,
one schema validator — rather than a separate `.reqdrive/policy.json`. It is
the config surface Tasks 33 (scope checking) and 34 (risk tiers) consume.
`reqdrive_load_config` does not schema-validate; it only reads `policy` with
safe defaults, so a malformed `policy` object is caught by `reqdrive validate`
(`validate_config_schema`), not by every command that loads config.

### US-POL-01: A well-formed policy object validates
**Test:** `policy: a well-formed policy object validates`

**As** a maintainer configuring evidence policy in `reqdrive.json`,
**When** `policy.riskTiers` maps tier names to arrays of path prefixes and `policy.scopeCheck` is `"warn"`,
**Then** `reqdrive validate` exits `0` — a well-formed `policy` object does not trip schema validation.

### US-POL-02: An invalid scopeCheck value is rejected
**Test:** `policy: rejects an invalid scopeCheck value`

**As** a maintainer relying on schema validation to catch config typos before a run,
**When** `policy.scopeCheck` is set to a value other than `"warn"` or `"block"` (e.g. `"maybe"`),
**Then** `reqdrive validate` exits `3` (`EXIT_CONFIG_ERROR`) and the output names `scopeCheck`, so the operator knows exactly which field is wrong.

### US-POL-03: A non-array risk tier is rejected
**Test:** `policy: rejects a non-array risk tier`

**As** a maintainer relying on schema validation to catch config typos before a run,
**When** `policy.riskTiers` maps a tier name to a bare string instead of an array of path prefixes,
**Then** `reqdrive validate` exits `3` (`EXIT_CONFIG_ERROR`) and the output names `riskTiers`, so the operator knows exactly which field is wrong.

### US-POL-04: scopeCheck defaults to warn when policy is absent
**Test:** `policy: scopeCheck defaults to warn when absent`

**As** a maintainer with no `policy` block in `reqdrive.json` yet,
**When** `reqdrive_load_config` runs against a manifest with no `policy` key,
**Then** `REQDRIVE_POLICY_SCOPE_CHECK` is exported as `"warn"` and `REQDRIVE_POLICY_JSON` is exported as `"{}"`, so downstream consumers (Tasks 33/34) never see an unset or malformed policy.

## Module 17: policy matcher (lib/policy.sh)

`lib/policy.sh` classifies a path against `REQDRIVE_POLICY_JSON.riskTiers`.
Patterns are bare path prefixes, not globs: inside `[[ ]]` bash does not honour
globstar, so `**` and `*` are indistinguishable and both cross `/`, while
`src/auth/**` fails to match `src/auth` itself. A path matches a pattern when
it equals the pattern or begins with `"<pattern>/"`. `policy_tier_for_path`
probes `high`, `medium`, then `low` in that order so the highest tier wins;
`policy_classify_paths` prints `TIER<TAB>PATH` per input path. This is the
matcher Task 34's scope check consumes.

### US-POL-05: Matcher classifies paths by tier
**Test:** `policy: matcher classifies paths by tier`

**As** the scope-check step classifying changed files by risk,
**When** `REQDRIVE_POLICY_JSON.riskTiers` maps `high` to `src/auth`, `medium` to `src/api`, and `low` to `docs`,
**Then** `policy_tier_for_path` returns `high` for a nested descendant (`src/auth/login.ts`) and for the tier directory itself (`src/auth`), `medium` for `src/api/v1/users.ts`, `low` for `docs/README.md`, and `none` for a path outside every tier (`src/util/math.ts`).

### US-POL-06: A prefix-sharing sibling does not match
**Test:** `policy: a prefix-sharing sibling does not match`

**As** the scope-check step trusting the matcher not to over-classify,
**When** `REQDRIVE_POLICY_JSON.riskTiers.high` is `["src/auth"]`,
**Then** `policy_tier_for_path` returns `none` for `src/auth.sh` and `src/authorization/x.ts` — both share the `src/auth` character prefix but neither sits at a `/` directory boundary, which is exactly the trap a glob (`src/auth*`) would have fallen into.

### US-POL-07: Highest tier wins when a path matches two
**Test:** `policy: highest tier wins when a path matches two`

**As** the scope-check step needing one definitive tier per path,
**When** `REQDRIVE_POLICY_JSON.riskTiers.high` is `["src/auth"]` and `riskTiers.low` is `["src/auth/keys"]`,
**Then** `policy_tier_for_path 'src/auth/keys/rsa.pem'` returns `high`, because tiers are probed in descending risk order and the first match wins.

### US-POL-08: No riskTiers means every path is untiered
**Test:** `policy: no riskTiers means every path is untiered`

**As** a maintainer who has not yet configured risk tiers,
**When** `REQDRIVE_POLICY_JSON` is `{}`,
**Then** `policy_tier_for_path` returns `none` for every path, so the absence of policy configuration is safe by default rather than an error.

## Module 18: scope check (lib/policy.sh + lib/run.sh)

`policy_scope_check <agent_dir> <iteration> <tests_passed>` runs after every
implementation iteration's commit-verification step. It diffs the commit the
agent just made (`git diff --name-only HEAD~1 HEAD`), classifies each changed
path with `policy_tier_for_path`, and treats a `high`-tier path changed in an
iteration whose `testCommand` run did not pass as a finding. `warn` (the
default, `REQDRIVE_POLICY_SCOPE_CHECK`) appends the finding to
`scope-findings.txt`, logs it, and returns 0 so the pipeline continues;
`block` does the same and returns 1, and `run_pipeline` treats that as a
policy pre-condition failure — it writes `run.json` status `failed` and exits
`EXIT_PREFLIGHT_FAILED` (8), the same code preflight checks use, rather than
inventing a new one. With no `policy` configured at all, `REQDRIVE_POLICY_JSON`
defaults to `{}`, every path classifies as `none`, and no finding is ever
produced — the feature is off by construction, not by a separate flag.

### US-SCOPE-01: Warn mode logs a finding and continues
**Test:** `scope: warn mode logs a finding and continues`

**As** a maintainer who wants visibility into high-risk changes without blocking unattended runs,
**When** `policy.riskTiers.high` matches a path the agent's commit touches, `policy.scopeCheck` is `"warn"`, and no `testCommand` is configured (so the iteration has no passing test run),
**Then** the pipeline still exits `0`, and the run log records a "high-risk" finding — the gate observes without enforcing.

### US-SCOPE-02: Block mode aborts with EXIT_PREFLIGHT_FAILED
**Test:** `scope: block mode aborts with EXIT_PREFLIGHT_FAILED`

**As** a maintainer who wants a hard stop on unverified high-risk changes,
**When** the same high-risk path is touched with no passing test run and `policy.scopeCheck` is `"block"`,
**Then** the pipeline aborts with exit code `8` (`EXIT_PREFLIGHT_FAILED`), reusing the existing pre-condition failure code instead of adding a new one.

### US-SCOPE-03: Absent policy produces no findings
**Test:** `scope: absent policy produces no findings`

**As** a maintainer who has not configured `policy` in `reqdrive.json`,
**When** the same agent run touches the same files with no risk tiers defined,
**Then** the pipeline exits `0` and the run log contains no "high-risk" finding — the scope check is inert without an explicit `policy.riskTiers` configuration, proving `warn` is the default without also being a silent no-op.
