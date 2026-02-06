#!/usr/bin/env bash
# validate.sh - Validate reqdrive.json config

set -e

M="$REQDRIVE_MANIFEST"
ROOT="$REQDRIVE_PROJECT_ROOT"
ERRORS=0

echo "Validating: $M"
echo "─────────────────────────────────────"

# ── JSON syntax and schema ────────────────────────────────────────────
if ! jq empty "$M" 2>/dev/null; then
  echo "FAIL: Invalid JSON syntax"
  exit 1
fi
echo "  ✓ Valid JSON"

# Run schema validation
if ! validate_config_schema "$M" 2>/dev/null; then
  echo "  FAIL: Schema validation errors detected"
  # Re-run to show errors
  validate_config_schema "$M" 2>&1 | while IFS= read -r line; do
    echo "  $line"
  done
  ERRORS=$((ERRORS + 1))
else
  echo "  ✓ Schema valid"
fi

# ── Check fields ─────────────────────────────────────────────────────
check_field() {
  local path="$1"
  local label="$2"
  local val
  val=$(jq -r "$path // empty" "$M")
  if [ -z "$val" ]; then
    echo "  WARN: $label not set"
    return 0
  fi
  echo "  ✓ $label = $val"
  return 0
}

check_field '.requirementsDir' 'requirementsDir'
check_field '.testCommand' 'testCommand'
check_field '.model' 'model'
check_field '.baseBranch' 'baseBranch'

# ── Check requirements directory exists ──────────────────────────────
REQ_DIR=$(jq -r '.requirementsDir // "docs/requirements"' "$M")
REQ_PATH="$ROOT/$REQ_DIR"

if [ -d "$REQ_PATH" ]; then
  REQ_COUNT=$(find "$REQ_PATH" -maxdepth 1 -name "REQ-*.md" 2>/dev/null | wc -l)
  echo "  ✓ $REQ_DIR exists ($REQ_COUNT requirement files)"
else
  echo "  WARN: $REQ_DIR does not exist"
fi

# ── Summary ──────────────────────────────────────────────────────────
echo ""
echo "─────────────────────────────────────"
if [ "$ERRORS" -eq 0 ]; then
  echo "Validation PASSED"
  exit 0
else
  echo "Validation FAILED ($ERRORS errors)"
  exit 1
fi
