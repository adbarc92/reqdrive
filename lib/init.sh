#!/usr/bin/env bash
# init.sh - Create minimal reqdrive.json config

set -e

PROJECT_DIR="$(pwd)"

echo "═══════════════════════════════════════════════════════════"
echo "  reqdrive init"
echo "  Directory: $PROJECT_DIR"
echo "═══════════════════════════════════════════════════════════"
echo ""

# Check if manifest already exists
if [ -f "$PROJECT_DIR/reqdrive.json" ]; then
  echo "reqdrive.json already exists."
  read -rp "Overwrite? (y/N): " OVERWRITE
  if [ "$OVERWRITE" != "y" ] && [ "$OVERWRITE" != "Y" ]; then
    echo "Aborted."
    exit 0
  fi
fi

# ── Detect project type ──────────────────────────────────────────────
DETECTED_TEST=""

if [ -f "$PROJECT_DIR/package.json" ]; then
  DETECTED_TEST="npm test"
  echo "Detected: Node.js (package.json)"
elif [ -f "$PROJECT_DIR/pyproject.toml" ]; then
  DETECTED_TEST="uv run pytest"
  echo "Detected: Python (pyproject.toml)"
elif [ -f "$PROJECT_DIR/Cargo.toml" ]; then
  DETECTED_TEST="cargo test"
  echo "Detected: Rust (Cargo.toml)"
elif [ -f "$PROJECT_DIR/go.mod" ]; then
  DETECTED_TEST="go test ./..."
  echo "Detected: Go (go.mod)"
fi

echo ""

# ── Gather configuration ─────────────────────────────────────────────
read -rp "Requirements directory [docs/requirements]: " REQ_DIR
REQ_DIR="${REQ_DIR:-docs/requirements}"

read -rp "Test command [$DETECTED_TEST]: " TEST_CMD
TEST_CMD="${TEST_CMD:-$DETECTED_TEST}"

read -rp "Base branch [main]: " BASE_BRANCH
BASE_BRANCH="${BASE_BRANCH:-main}"

read -rp "Project name [$(basename "$PROJECT_DIR")]: " PROJECT_NAME
PROJECT_NAME="${PROJECT_NAME:-$(basename "$PROJECT_DIR")}"

# ── Write minimal reqdrive.json ──────────────────────────────────────
cat > "$PROJECT_DIR/reqdrive.json" <<JSON
{
  "version": "0.3.0",
  "requirementsDir": "$REQ_DIR",
  "testCommand": "$TEST_CMD",
  "model": "claude-sonnet-4-20250514",
  "maxIterations": 10,
  "baseBranch": "$BASE_BRANCH",
  "prLabels": ["agent-generated"],
  "projectName": "$PROJECT_NAME"
}
JSON

echo ""
echo "Created: reqdrive.json"

# ── Create directories ───────────────────────────────────────────────
mkdir -p "$PROJECT_DIR/$REQ_DIR"
mkdir -p "$PROJECT_DIR/.reqdrive/runs"

echo "Created: $REQ_DIR/"
echo "Created: .reqdrive/runs/"

# ── Suggest .gitignore additions ─────────────────────────────────────
if [ -f "$PROJECT_DIR/.gitignore" ]; then
  if ! grep -q '.reqdrive/runs' "$PROJECT_DIR/.gitignore" 2>/dev/null; then
    read -rp "Add .reqdrive/runs to .gitignore? (Y/n): " ADD_GITIGNORE
    if [ "$ADD_GITIGNORE" != "n" ] && [ "$ADD_GITIGNORE" != "N" ]; then
      echo "" >> "$PROJECT_DIR/.gitignore"
      echo "# reqdrive run state" >> "$PROJECT_DIR/.gitignore"
      echo ".reqdrive/runs/" >> "$PROJECT_DIR/.gitignore"
      echo "Updated .gitignore"
    fi
  fi
fi

echo ""
echo "Done! Next steps:"
echo "  1. Add requirement files to $REQ_DIR/ (e.g., REQ-01-feature.md)"
echo "  2. Run: reqdrive run REQ-01"
