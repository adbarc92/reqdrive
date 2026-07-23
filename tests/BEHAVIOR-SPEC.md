1# reqdrive Behavior Specification (Modules 1-4)

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

### US-CFG-12: get_req_file — respects custom requirementsDir
**Test:** `get_req_file: respects custom requirementsDir`

**As** a pipeline runner,
**When** the manifest sets `"requirementsDir": "specs"` and `specs/REQ-05-custom.md` exists,
**Then** `reqdrive_get_req_file "REQ-05"` finds it.
