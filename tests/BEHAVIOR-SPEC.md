1# reqdrive Behavior Specification (Modules 1-4)

Behavioral contract for the core library modules, expressed as user stories.
Each story maps to one or more tests in `tests/simple-test.sh`.

---

## Module 1: errors.sh

### US-ERR-01: Exit code constants
**As** a library consumer,
**When** I source `errors.sh`,
**Then** I get named exit codes: `EXIT_SUCCESS=0`, `EXIT_GENERAL_ERROR=1`, `EXIT_MISSING_DEPENDENCY=2`, `EXIT_CONFIG_ERROR=3`, `EXIT_GIT_ERROR=4`, `EXIT_AGENT_ERROR=5`, `EXIT_PR_ERROR=6`, `EXIT_USER_ABORT=7`, `EXIT_PREFLIGHT_FAILED=8`.

### US-ERR-02: Human-readable error messages
**As** a library consumer,
**When** I source `errors.sh`,
**Then** every exit code (0-8) has a corresponding entry in `EXIT_MESSAGES`.

### US-ERR-03: Get exit message for known code
**As** a library consumer,
**When** I call `get_exit_message` with a known code (e.g. 0, 3, 8),
**Then** I get the matching human-readable message (e.g. "Success", "Configuration error", "Pre-flight checks failed").

### US-ERR-04: Get exit message for unknown code
**As** a library consumer,
**When** I call `get_exit_message` with an unrecognized code (e.g. 99),
**Then** I get `"Unknown error"`.

### US-ERR-05: die with code and custom message
**As** a library consumer,
**When** I call `die 3 "bad config"`,
**Then** the process exits with code 3 and prints `[ERROR] bad config` to stderr.

### US-ERR-06: die with code, no custom message
**As** a library consumer,
**When** I call `die 5` (no second argument),
**Then** the process exits with code 5 and prints `[ERROR] Agent execution failed` (from EXIT_MESSAGES) to stderr.

### US-ERR-07: die with no arguments
**As** a library consumer,
**When** I call `die` with no arguments,
**Then** the process exits with code 1.

### US-ERR-08: die_on_error after success
**As** a library consumer,
**When** the previous command succeeded (`$?` is 0) and I call `die_on_error`,
**Then** nothing happens and execution continues.

### US-ERR-09: die_on_error after failure
**As** a library consumer,
**When** the previous command failed (`$?` is non-zero) and I call `die_on_error "it broke"`,
**Then** the process exits with code 1 and prints the message including "it broke" to stderr.

---

## Module 2: schema.sh

### US-SCH-01: Schema version — exact match passes
**As** a config loader,
**When** I call `check_schema_version` on a file with `"version": "0.3.0"`,
**Then** it returns 0 with no output.

### US-SCH-02: Schema version — missing version warns
**As** a config loader,
**When** I call `check_schema_version` on a file with no `version` field,
**Then** it returns 0 (backward compatible) but prints a warning mentioning "No version field" to stderr.

### US-SCH-03: Schema version — incompatible major rejects
**As** a config loader,
**When** I call `check_schema_version` on a file with `"version": "9.0.0"`,
**Then** it returns 1 and prints an error mentioning "Incompatible" to stderr.

### US-SCH-04: Schema version — nonexistent file passes
**As** a config loader,
**When** I call `check_schema_version` on a path that doesn't exist,
**Then** it returns 0 (no-op).

### US-SCH-05: Schema version — older minor accepted
**As** a config loader,
**When** I call `check_schema_version` on a file with `"version": "0.2.0"`,
**Then** it returns 0 (same major = compatible).

### US-SCH-06: Schema version — newer minor warns
**As** a config loader,
**When** I call `check_schema_version` on a file with `"version": "0.9.0"`,
**Then** it returns 0 but prints a warning mentioning "newer than supported" to stderr.

### US-SCH-07: Schema version — patch difference accepted
**As** a config loader,
**When** I call `check_schema_version` on a file with `"version": "0.3.1"`,
**Then** it returns 0 with no error.

### US-SCH-08: Config schema — valid config passes
**As** a validator,
**When** I call `validate_config_schema` on a well-formed manifest with correct types,
**Then** it returns 0.

### US-SCH-09: Config schema — empty object passes
**As** a validator,
**When** I call `validate_config_schema` on `{}`,
**Then** it returns 0 (all fields are optional).

### US-SCH-10: Config schema — invalid JSON rejects
**As** a validator,
**When** I call `validate_config_schema` on a file containing non-JSON text,
**Then** it returns 1 and prints an error mentioning "Invalid JSON".

### US-SCH-11: Config schema — type violations rejected
**As** a validator,
**When** I call `validate_config_schema` on a file where `requirementsDir` is a number, `maxIterations` is a string, or `prLabels` is a string,
**Then** it returns 1 and prints the specific type error (e.g. "requirementsDir must be a string").

### US-SCH-12: Config schema — multiple errors reported
**As** a validator,
**When** a config has multiple type violations,
**Then** `validate_config_schema` reports all of them (not just the first).

### US-SCH-13: PRD schema — valid PRD passes
**As** a validator,
**When** I call `validate_prd_schema` on a file with `project`, `sourceReq`, and a valid `userStories` array,
**Then** it returns 0.

### US-SCH-14: PRD schema — invalid JSON rejects
**As** a validator,
**When** I call `validate_prd_schema` on non-JSON text,
**Then** it returns 1.

### US-SCH-15: PRD schema — missing required fields rejected
**As** a validator,
**When** a PRD file is missing `project`, `sourceReq`, or `userStories`,
**Then** `validate_prd_schema` returns 1 and names the missing field.

### US-SCH-16: PRD schema — non-array userStories rejected
**As** a validator,
**When** `userStories` is a string instead of an array,
**Then** `validate_prd_schema` returns 1 and prints "userStories must be an array".

### US-SCH-17: PRD schema — empty stories array passes
**As** a validator,
**When** `userStories` is `[]`,
**Then** `validate_prd_schema` returns 0.

### US-SCH-18: PRD schema — story-level required fields
**As** a validator,
**When** a story is missing `id`, `title`, or `acceptanceCriteria`,
**Then** `validate_prd_schema` returns 1 and identifies which field is missing with the story index.

### US-SCH-19: PRD schema — story type checks
**As** a validator,
**When** a story has `acceptanceCriteria` as a string (not array) or `passes` as a string (not boolean),
**Then** `validate_prd_schema` returns 1 with a specific type error.

### US-SCH-20: Checkpoint schema — valid checkpoint passes
**As** a validator,
**When** I call `validate_checkpoint_schema` on a file with `req_id`, `branch`, and numeric `iteration`,
**Then** it returns 0.

### US-SCH-21: Checkpoint schema — invalid JSON rejects
**As** a validator,
**When** I call `validate_checkpoint_schema` on non-JSON text,
**Then** it returns 1.

### US-SCH-22: Checkpoint schema — missing required fields rejected
**As** a validator,
**When** a checkpoint is missing `req_id`, `branch`, or `iteration`,
**Then** `validate_checkpoint_schema` returns 1 and names the missing field.

### US-SCH-23: Checkpoint schema — non-number iteration rejected
**As** a validator,
**When** `iteration` is a string like `"three"`,
**Then** `validate_checkpoint_schema` returns 1 and prints "iteration must be a number".

---

## Module 3: sanitize.sh

### US-SAN-01: sanitize_for_prompt — escapes backticks and dollar signs
**As** a prompt builder,
**When** I call `sanitize_for_prompt` on text containing `` `cmd` `` and `$(cmd)`,
**Then** backticks are replaced with single quotes and `$` is escaped to `\$`.

### US-SAN-02: sanitize_for_prompt — clean content passes through
**As** a prompt builder,
**When** I call `sanitize_for_prompt` on plain text with no shell metacharacters,
**Then** the output is identical to the input.

### US-SAN-03: sanitize_for_prompt — empty input
**As** a prompt builder,
**When** I call `sanitize_for_prompt ""`,
**Then** the result is empty.

### US-SAN-04: sanitize_for_prompt — escapes variable expansion
**As** a prompt builder,
**When** I call `sanitize_for_prompt` on text containing `${HOME}`,
**Then** the `$` is escaped to `\$`, producing `\${HOME}`.

### US-SAN-05: sanitize_label — clean label passes through
**As** a PR creator,
**When** I call `sanitize_label "agent-generated"`,
**Then** the output is `"agent-generated"` unchanged.

### US-SAN-06: sanitize_label — strips whitespace
**As** a PR creator,
**When** I call `sanitize_label "  my-label  "`,
**Then** the output is `"my-label"`.

### US-SAN-07: sanitize_label — removes dangerous characters
**As** a PR creator,
**When** I call `sanitize_label` on text containing `;`, `|`, `&`, `>`, `<`, `$`, or `\`,
**Then** those characters are removed from the output.

### US-SAN-08: sanitize_label — replaces quotes and backticks
**As** a PR creator,
**When** I call `sanitize_label` on text containing `"` or `` ` ``,
**Then** they are replaced with single quotes `'`.

### US-SAN-09: sanitize_label — truncates to 50 characters
**As** a PR creator,
**When** I call `sanitize_label` on a 70-character string,
**Then** the output is exactly 50 characters.

### US-SAN-10: sanitize_label — empty input
**As** a PR creator,
**When** I call `sanitize_label ""`,
**Then** the result is empty.

### US-SAN-11: validate_requirement_content — clean content passes
**As** a pipeline runner,
**When** I call `validate_requirement_content` on normal text with no suspicious patterns,
**Then** it returns 0 with no warnings.

### US-SAN-12: validate_requirement_content — warns in non-strict mode
**As** a pipeline runner,
**When** I call `validate_requirement_content` on text containing `$(rm -rf /)` without strict mode,
**Then** it prints "Suspicious pattern" warnings to stderr but still returns 0.

### US-SAN-13: validate_requirement_content — rejects in strict mode
**As** a pipeline runner,
**When** I call `validate_requirement_content` with `strict=true` on suspicious content,
**Then** it returns 1 and prints "Strict mode enabled" to stderr.

### US-SAN-14: validate_requirement_content — detects all dangerous patterns
**As** a pipeline runner,
**When** I call `validate_requirement_content` on text containing any of:
- `` `cmd` `` (backtick substitution)
- `${VAR}` (variable expansion)
- `> /path` (redirect to absolute path)
- `rm -rf /` (destructive command)
- `curl ... | sh` (remote code execution)
- `eval ` (eval injection)
- `chmod 777` (permission escalation)
- `; rm` (semicolon-chained rm)
- `&& sudo` (chained privilege escalation)
- `| sudo` (pipe to sudo)

**Then** it prints a "Suspicious pattern" warning for each match.

### US-SAN-15: validate_file_path — normal path passes
**As** a path validator,
**When** I call `validate_file_path "src/main.sh" "/project"`,
**Then** it returns 0.

### US-SAN-16: validate_file_path — rejects path traversal
**As** a path validator,
**When** I call `validate_file_path` with a path containing `..` (e.g. `../../etc/passwd` or `src/../../../etc/passwd`),
**Then** it returns 1 and prints "Path traversal detected".

---

## Module 4: config.sh

### US-CFG-01: find_manifest — finds in current directory
**As** a CLI user,
**When** I run from a directory containing `reqdrive.json`,
**Then** `reqdrive_find_manifest` returns the full path to that file.

### US-CFG-02: find_manifest — walks up to parent
**As** a CLI user,
**When** I run from a nested subdirectory and `reqdrive.json` exists in a parent,
**Then** `reqdrive_find_manifest` finds and returns the parent's manifest path.

### US-CFG-03: find_manifest — returns 1 when not found
**As** a CLI user,
**When** no `reqdrive.json` exists anywhere up the directory tree,
**Then** `reqdrive_find_manifest` returns 1.

### US-CFG-04: load_config — loads all settings from manifest
**As** a pipeline runner,
**When** I call `reqdrive_load_config` with a fully-populated manifest,
**Then** `REQDRIVE_REQUIREMENTS_DIR`, `REQDRIVE_TEST_COMMAND`, `REQDRIVE_MODEL`, `REQDRIVE_MAX_ITERATIONS`, `REQDRIVE_BASE_BRANCH`, and `REQDRIVE_PROJECT_NAME` are all set to the manifest values.

### US-CFG-05: load_config — applies sensible defaults
**As** a pipeline runner,
**When** I call `reqdrive_load_config` on an empty `{}` manifest,
**Then** defaults are: `requirementsDir=docs/requirements`, `model=claude-sonnet-4-20250514`, `maxIterations=10`, `baseBranch=main`, `testCommand=""`, `projectName=""`, `prLabels=agent-generated`.

### US-CFG-06: load_config — sets REQDRIVE_MANIFEST and REQDRIVE_PROJECT_ROOT
**As** a pipeline runner,
**When** I call `reqdrive_load_config`,
**Then** `REQDRIVE_MANIFEST` is the full path to the found manifest and `REQDRIVE_PROJECT_ROOT` is its parent directory (even when called from a subdirectory).

### US-CFG-07: load_config — joins prLabels array into comma-separated string
**As** a pipeline runner,
**When** the manifest has `"prLabels": ["a", "b", "c"]`,
**Then** `REQDRIVE_PR_LABELS` is set to `"a,b,c"`.

### US-CFG-08: load_config — exits on missing manifest
**As** a CLI user,
**When** I call `reqdrive_load_config` and no manifest exists,
**Then** the process exits non-zero and prints "No reqdrive.json found" to stderr.

### US-CFG-09: load_config — exits on incompatible schema version
**As** a CLI user,
**When** I call `reqdrive_load_config` and the manifest has `"version": "9.0.0"`,
**Then** the process exits non-zero and prints "Incompatible config version" to stderr.

### US-CFG-10: get_req_file — finds matching requirement
**As** a pipeline runner,
**When** I call `reqdrive_get_req_file "REQ-01"` and `docs/requirements/REQ-01-test-feature.md` exists,
**Then** it returns the full path to that file.

### US-CFG-11: get_req_file — returns 1 when no match
**As** a pipeline runner,
**When** I call `reqdrive_get_req_file "REQ-99"` and no matching file exists,
**Then** it returns 1.

### US-CFG-12: get_req_file — respects custom requirementsDir
**As** a pipeline runner,
**When** the manifest sets `"requirementsDir": "specs"` and `specs/REQ-05-custom.md` exists,
**Then** `reqdrive_get_req_file "REQ-05"` finds it.
