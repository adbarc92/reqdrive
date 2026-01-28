#!/usr/bin/env bash
# validate.sh — Validate the reqdrive.json manifest
# Dispatched from bin/reqdrive as: reqdrive validate

set -e

source "${REQDRIVE_ROOT}/lib/config.sh"
reqdrive_load_config_path

M="$REQDRIVE_MANIFEST"
ROOT="$REQDRIVE_PROJECT_ROOT"
ERRORS=0

echo "Validating: $M"
echo "─────────────────────────────────────"

# ── JSON syntax ───────────────────────────────────────────────────────
if ! jq empty "$M" 2>/dev/null; then
  echo "FAIL: Invalid JSON syntax"
  exit 1
fi
echo "  ✓ Valid JSON"

# ── Required fields ───────────────────────────────────────────────────
check_field() {
  local path="$1"
  local label="$2"
  local val
  val=$(jq -r "$path // empty" "$M")
  if [ -z "$val" ]; then
    echo "  FAIL: Missing required field: $label ($path)"
    ERRORS=$((ERRORS + 1))
    return 1
  fi
  echo "  ✓ $label = $val"
  return 0
}

check_field '.project.name' 'project.name'
check_field '.project.title' 'project.title'
check_field '.paths.requirementsDir' 'paths.requirementsDir'
check_field '.paths.agentDir' 'paths.agentDir'

# ── Paths exist on disk ──────────────────────────────────────────────
check_path() {
  local rel="$1"
  local label="$2"
  local abs="$ROOT/$rel"
  if [ ! -e "$abs" ]; then
    echo "  WARN: Path does not exist: $label → $abs"
    return 0  # warning, not error
  fi
  echo "  ✓ $label exists: $rel"
  return 0
}

REQ_DIR=$(jq -r '.paths.requirementsDir // ""' "$M")
AGENT_DIR=$(jq -r '.paths.agentDir // ""' "$M")
CONTEXT_FILE=$(jq -r '.paths.contextFile // ""' "$M")

[ -n "$REQ_DIR" ] && check_path "$REQ_DIR" "requirementsDir"
[ -n "$AGENT_DIR" ] && check_path "$AGENT_DIR" "agentDir"
[ -n "$CONTEXT_FILE" ] && check_path "$CONTEXT_FILE" "contextFile"

# ── Commands validation ──────────────────────────────────────────────
echo ""
echo "Commands:"
for cmd_key in install test typecheck lint; do
  val=$(jq -r ".commands.$cmd_key // \"(not set)\"" "$M")
  if [ "$val" = "null" ]; then
    echo "  · $cmd_key: disabled (null)"
  elif [ "$val" = "(not set)" ]; then
    echo "  · $cmd_key: not configured"
  else
    echo "  ✓ $cmd_key: $val"
  fi
done

# ── Dependencies validation ──────────────────────────────────────────
echo ""
echo "Dependencies:"
DEP_KEYS=$(jq -r '.requirements.dependencies // {} | keys[]' "$M" 2>/dev/null || true)

if [ -z "$DEP_KEYS" ]; then
  echo "  · No dependencies defined"
else
  # Check all referenced deps exist as keys
  ALL_KEYS=$(jq -r '.requirements.dependencies | keys[]' "$M")
  for KEY in $ALL_KEYS; do
    DEPS=$(jq -r --arg k "$KEY" '.requirements.dependencies[$k] // [] | .[]' "$M")
    for DEP in $DEPS; do
      if ! echo "$ALL_KEYS" | grep -qw "$DEP"; then
        echo "  FAIL: $KEY depends on $DEP, but $DEP is not defined in dependencies"
        ERRORS=$((ERRORS + 1))
      fi
    done
  done

  # Check for circular dependencies (simple DFS)
  VISITED=""
  STACK=""
  HAS_CYCLE=false

  check_cycle() {
    local node="$1"
    local path="$2"

    if echo "$path" | grep -qw "$node"; then
      echo "  FAIL: Circular dependency detected: $path → $node"
      HAS_CYCLE=true
      ERRORS=$((ERRORS + 1))
      return
    fi

    if echo "$VISITED" | grep -qw "$node"; then
      return
    fi

    VISITED+="$node "
    local deps
    deps=$(jq -r --arg k "$node" '.requirements.dependencies[$k] // [] | .[]' "$M")
    for dep in $deps; do
      check_cycle "$dep" "$path $node"
    done
  }

  for KEY in $ALL_KEYS; do
    VISITED=""
    check_cycle "$KEY" ""
  done

  if [ "$HAS_CYCLE" = false ]; then
    KEY_COUNT=$(echo "$ALL_KEYS" | wc -w)
    echo "  ✓ $KEY_COUNT requirements defined, no circular dependencies"
  fi
fi

# ── Verification checks ─────────────────────────────────────────────
echo ""
echo "Verification:"
CHECK_COUNT=$(jq '.verification.checks // [] | length' "$M")
if [ "$CHECK_COUNT" -eq 0 ]; then
  echo "  · No verification checks defined (will use commands config)"
else
  echo "  ✓ $CHECK_COUNT verification checks defined"
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
