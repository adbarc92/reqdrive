#!/usr/bin/env bash
# schema.sh - Schema versioning for reqdrive JSON formats

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
