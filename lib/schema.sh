#!/usr/bin/env bash
# schema.sh - Schema versioning and validation for reqdrive JSON formats

REQDRIVE_SCHEMA_VERSION="0.3.0"

# Check the schema version of a JSON file
# Args: $1 = JSON file path
# Returns: 0 if version is compatible, 1 if unrecognized
# Warns on stderr if version is missing (backward compat with 0.2.0)
check_schema_version() {
  local file="$1"

  if [ ! -f "$file" ]; then
    return 0
  fi

  local version
  version=$(jq -r '.version // empty' "$file" 2>/dev/null)

  if [ -z "$version" ]; then
    echo "[SCHEMA] Warning: No version field in $file (pre-0.3.0 format). Run 'reqdrive migrate' to update." >&2
    return 0
  fi

  local major minor
  major=$(echo "$version" | cut -d. -f1)
  minor=$(echo "$version" | cut -d. -f2)

  local expected_major expected_minor
  expected_major=$(echo "$REQDRIVE_SCHEMA_VERSION" | cut -d. -f1)
  expected_minor=$(echo "$REQDRIVE_SCHEMA_VERSION" | cut -d. -f2)

  if [ "$major" != "$expected_major" ]; then
    echo "[SCHEMA] Error: Incompatible schema version $version (expected $expected_major.x.x)" >&2
    return 1
  fi

  if [ "$minor" -gt "$expected_minor" ] 2>/dev/null; then
    echo "[SCHEMA] Warning: Schema version $version is newer than supported $REQDRIVE_SCHEMA_VERSION" >&2
  fi

  return 0
}

# ── Config Schema Validation ─────────────────────────────────────────────────

# Validate reqdrive.json structure
# Args: $1 = path to reqdrive.json
# Returns: 0 if valid, 1 if invalid
validate_config_schema() {
  local file="$1"
  local errors=0

  # Must be valid JSON
  if ! jq empty "$file" 2>/dev/null; then
    echo "[SCHEMA] Error: Invalid JSON in $file" >&2
    return 1
  fi

  # Type checks for known fields
  local check
  check=$(jq -r '
    def check_type(field; expected):
      if has(field) then
        if expected == "string" then (.[field] | type) == "string"
        elif expected == "number" then (.[field] | type) == "number"
        elif expected == "array" then (.[field] | type) == "array"
        else true end
      else true end;
    [
      if has("requirementsDir") and (.requirementsDir | type) != "string" then "requirementsDir must be a string" else empty end,
      if has("model") and (.model | type) != "string" then "model must be a string" else empty end,
      if has("baseBranch") and (.baseBranch | type) != "string" then "baseBranch must be a string" else empty end,
      if has("testCommand") and (.testCommand | type) != "string" then "testCommand must be a string" else empty end,
      if has("projectName") and (.projectName | type) != "string" then "projectName must be a string" else empty end,
      if has("maxIterations") and (.maxIterations | type) != "number" then "maxIterations must be a number" else empty end,
      if has("prLabels") and (.prLabels | type) != "array" then "prLabels must be an array" else empty end,
      if has("completionHook") and (.completionHook | type) != "string" then "completionHook must be a string" else empty end
    ] | .[]
  ' "$file" 2>/dev/null)

  if [ -n "$check" ]; then
    while IFS= read -r err; do
      echo "[SCHEMA] Error: $err" >&2
      errors=$((errors + 1))
    done <<< "$check"
  fi

  [ "$errors" -eq 0 ]
}

# ── PRD Schema Validation ────────────────────────────────────────────────────

# Validate prd.json structure
# Args: $1 = path to prd.json
# Returns: 0 if valid, 1 if invalid
validate_prd_schema() {
  local file="$1"
  local errors=0

  # Must be valid JSON
  if ! jq empty "$file" 2>/dev/null; then
    echo "[SCHEMA] Error: Invalid JSON in $file" >&2
    return 1
  fi

  # Check required top-level fields
  local check
  check=$(jq -r '
    [
      if has("project") | not then "missing required field: project" else empty end,
      if has("sourceReq") | not then "missing required field: sourceReq" else empty end,
      if has("userStories") | not then "missing required field: userStories" else empty end,
      if has("userStories") and (.userStories | type) != "array" then "userStories must be an array" else empty end
    ] | .[]
  ' "$file" 2>/dev/null)

  if [ -n "$check" ]; then
    while IFS= read -r err; do
      echo "[SCHEMA] Error: $err" >&2
      errors=$((errors + 1))
    done <<< "$check"
  fi

  # Validate individual stories if userStories exists and is an array
  if [ "$errors" -eq 0 ]; then
    local story_check
    story_check=$(jq -r '
      if (.userStories | type) == "array" then
        [.userStories | to_entries[] | .value as $s | .key as $i |
          (if ($s | has("id")) | not then "story[\($i)]: missing id" else empty end),
          (if ($s | has("title")) | not then "story[\($i)]: missing title" else empty end),
          (if ($s | has("acceptanceCriteria")) | not then "story[\($i)]: missing acceptanceCriteria" else empty end),
          (if $s | has("acceptanceCriteria") then
            if ($s.acceptanceCriteria | type) != "array" then "story[\($i)]: acceptanceCriteria must be an array" else empty end
          else empty end),
          (if $s | has("passes") then
            if ($s.passes | type) != "boolean" then "story[\($i)]: passes must be a boolean" else empty end
          else empty end)
        ] | .[]
      else empty end
    ' "$file" 2>/dev/null)

    if [ -n "$story_check" ]; then
      while IFS= read -r err; do
        echo "[SCHEMA] Error: $err" >&2
        errors=$((errors + 1))
      done <<< "$story_check"
    fi
  fi

  [ "$errors" -eq 0 ]
}

# ── Checkpoint Schema Validation ─────────────────────────────────────────────

# Validate checkpoint.json structure
# Args: $1 = path to checkpoint.json
# Returns: 0 if valid, 1 if invalid
validate_checkpoint_schema() {
  local file="$1"
  local errors=0

  # Must be valid JSON
  if ! jq empty "$file" 2>/dev/null; then
    echo "[SCHEMA] Error: Invalid JSON in $file" >&2
    return 1
  fi

  # Check required fields
  local check
  check=$(jq -r '
    [
      if has("req_id") | not then "missing required field: req_id" else empty end,
      if has("branch") | not then "missing required field: branch" else empty end,
      if has("iteration") | not then "missing required field: iteration" else empty end,
      if has("iteration") and (.iteration | type) != "number" then "iteration must be a number" else empty end
    ] | .[]
  ' "$file" 2>/dev/null)

  if [ -n "$check" ]; then
    while IFS= read -r err; do
      echo "[SCHEMA] Error: $err" >&2
      errors=$((errors + 1))
    done <<< "$check"
  fi

  [ "$errors" -eq 0 ]
}
