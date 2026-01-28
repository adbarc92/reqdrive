#!/usr/bin/env bash
# init.sh — Interactive scaffolding for reqdrive.json + agent prompt
# Dispatched from bin/reqdrive as: reqdrive init

set -e

REQDRIVE_ROOT="${REQDRIVE_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
PROJECT_DIR="$(pwd)"

echo "═══════════════════════════════════════════════════════════"
echo "  reqdrive init"
echo "  Setting up in: $PROJECT_DIR"
echo "═══════════════════════════════════════════════════════════"
echo ""

# Check if manifest already exists
if [ -f "$PROJECT_DIR/reqdrive.json" ]; then
  echo "reqdrive.json already exists in this directory."
  read -rp "Overwrite? (y/N): " OVERWRITE
  if [ "$OVERWRITE" != "y" ] && [ "$OVERWRITE" != "Y" ]; then
    echo "Aborted."
    exit 0
  fi
fi

# ── Detect project type ──────────────────────────────────────────────
DETECTED_TYPE="unknown"
DETECTED_INSTALL=""
DETECTED_TEST=""
DETECTED_TYPECHECK=""
DETECTED_LINT=""

if [ -f "$PROJECT_DIR/package.json" ]; then
  DETECTED_TYPE="node"
  DETECTED_INSTALL="npm install"
  DETECTED_TEST="npm test"
  # Check for typescript
  if jq -e '.devDependencies.typescript // .dependencies.typescript' "$PROJECT_DIR/package.json" >/dev/null 2>&1; then
    DETECTED_TYPECHECK="npx tsc --noEmit"
  fi
  # Check for eslint
  if jq -e '.devDependencies.eslint // .dependencies.eslint' "$PROJECT_DIR/package.json" >/dev/null 2>&1; then
    DETECTED_LINT="npx eslint ."
  fi
  echo "Detected: Node.js project (package.json)"
elif [ -f "$PROJECT_DIR/pyproject.toml" ]; then
  DETECTED_TYPE="python"
  DETECTED_INSTALL="uv sync"
  DETECTED_TEST="uv run pytest"
  DETECTED_TYPECHECK="uv run mypy ."
  DETECTED_LINT="uv run ruff check ."
  echo "Detected: Python project (pyproject.toml)"
elif [ -f "$PROJECT_DIR/Cargo.toml" ]; then
  DETECTED_TYPE="rust"
  DETECTED_INSTALL="cargo build"
  DETECTED_TEST="cargo test"
  DETECTED_TYPECHECK=""
  DETECTED_LINT="cargo clippy"
  echo "Detected: Rust project (Cargo.toml)"
elif [ -f "$PROJECT_DIR/go.mod" ]; then
  DETECTED_TYPE="go"
  DETECTED_INSTALL="go mod download"
  DETECTED_TEST="go test ./..."
  DETECTED_TYPECHECK=""
  DETECTED_LINT="golangci-lint run"
  echo "Detected: Go project (go.mod)"
else
  echo "Could not auto-detect project type."
fi

echo ""

# ── Gather configuration ─────────────────────────────────────────────
read -rp "Project name (slug) [$(basename "$PROJECT_DIR")]: " PROJECT_NAME
PROJECT_NAME="${PROJECT_NAME:-$(basename "$PROJECT_DIR")}"

read -rp "Project title [${PROJECT_NAME}]: " PROJECT_TITLE
PROJECT_TITLE="${PROJECT_TITLE:-$PROJECT_NAME}"

read -rp "Requirements directory [docs/requirements]: " REQ_DIR
REQ_DIR="${REQ_DIR:-docs/requirements}"

read -rp "Agent directory [.reqdrive/agent]: " AGENT_DIR
AGENT_DIR="${AGENT_DIR:-.reqdrive/agent}"

read -rp "App directory (where commands run) [.]: " APP_DIR
APP_DIR="${APP_DIR:-.}"

read -rp "Context file [CLAUDE.md]: " CONTEXT_FILE
CONTEXT_FILE="${CONTEXT_FILE:-CLAUDE.md}"

echo ""
echo "Commands (press Enter to accept default, type 'null' to disable):"
read -rp "  Install [$DETECTED_INSTALL]: " CMD_INSTALL
CMD_INSTALL="${CMD_INSTALL:-$DETECTED_INSTALL}"

read -rp "  Test [$DETECTED_TEST]: " CMD_TEST
CMD_TEST="${CMD_TEST:-$DETECTED_TEST}"

read -rp "  Typecheck [$DETECTED_TYPECHECK]: " CMD_TYPECHECK
CMD_TYPECHECK="${CMD_TYPECHECK:-$DETECTED_TYPECHECK}"

read -rp "  Lint [$DETECTED_LINT]: " CMD_LINT
CMD_LINT="${CMD_LINT:-$DETECTED_LINT}"

read -rp "Branch prefix [reqdrive]: " BRANCH_PREFIX
BRANCH_PREFIX="${BRANCH_PREFIX:-reqdrive}"

read -rp "Base branch [main]: " BASE_BRANCH
BASE_BRANCH="${BASE_BRANCH:-main}"

# ── Helper: format value as JSON (string or null) ────────────────────
json_val() {
  if [ -z "$1" ] || [ "$1" = "null" ]; then
    echo "null"
  else
    echo "\"$1\""
  fi
}

# ── Write reqdrive.json ──────────────────────────────────────────────
cat > "$PROJECT_DIR/reqdrive.json" <<MANIFEST
{
  "project": {
    "name": "$PROJECT_NAME",
    "title": "$PROJECT_TITLE"
  },
  "paths": {
    "requirementsDir": "$REQ_DIR",
    "agentDir": "$AGENT_DIR",
    "appDir": "$APP_DIR",
    "contextFile": "$CONTEXT_FILE"
  },
  "requirements": {
    "pattern": "REQ-*-*.md",
    "idRegex": "REQ-[0-9]+",
    "dependencies": {}
  },
  "commands": {
    "install": $(json_val "$CMD_INSTALL"),
    "test": $(json_val "$CMD_TEST"),
    "typecheck": $(json_val "$CMD_TYPECHECK"),
    "lint": $(json_val "$CMD_LINT")
  },
  "agent": {
    "model": "claude-opus-4-5-20251101",
    "maxIterations": 10,
    "branchPrefix": "$BRANCH_PREFIX",
    "worktreePrefix": "$BRANCH_PREFIX",
    "completionSignal": "<promise>COMPLETE</promise>"
  },
  "verification": {
    "maxRetries": 3,
    "checks": [],
    "generateTests": true
  },
  "pr": {
    "labels": ["agent-generated", "needs-validation"],
    "reqLabel": true,
    "setupSteps": [
      "Pull branch: \`git checkout {branch}\`",
      "Install deps: \`$([ -n "$CMD_INSTALL" ] && [ "$CMD_INSTALL" != "null" ] && echo "$CMD_INSTALL" || echo "npm install")\`"
    ],
    "regressionChecks": [
      "Existing features still work",
      "No console errors",
      "Tests pass locally"
    ],
    "footer": "Generated by reqdrive."
  },
  "orchestration": {
    "maxParallel": 3,
    "worktreeRoot": "../worktrees",
    "baseBranch": "$BASE_BRANCH",
    "stateDir": ".reqdrive/state"
  }
}
MANIFEST

echo ""
echo "Created: reqdrive.json"

# ── Create agent directory and prompt ─────────────────────────────────
mkdir -p "$PROJECT_DIR/$AGENT_DIR"

if [ -f "$REQDRIVE_ROOT/templates/prompt.md.tpl" ]; then
  cp "$REQDRIVE_ROOT/templates/prompt.md.tpl" "$PROJECT_DIR/$AGENT_DIR/prompt.md"
  echo "Created: $AGENT_DIR/prompt.md"
else
  echo "Warning: prompt.md template not found at $REQDRIVE_ROOT/templates/prompt.md.tpl"
fi

# ── Create requirements directory ─────────────────────────────────────
mkdir -p "$PROJECT_DIR/$REQ_DIR"
echo "Created: $REQ_DIR/"

# ── Suggest .gitignore additions ──────────────────────────────────────
echo ""
echo "Suggested .gitignore additions:"
echo "  .reqdrive/state/"
echo "  worktrees/"
echo ""

# Check if .gitignore exists and suggest
if [ -f "$PROJECT_DIR/.gitignore" ]; then
  MISSING=""
  if ! grep -q '.reqdrive/state/' "$PROJECT_DIR/.gitignore" 2>/dev/null; then
    MISSING+=".reqdrive/state/"$'\n'
  fi
  if ! grep -q 'worktrees/' "$PROJECT_DIR/.gitignore" 2>/dev/null; then
    MISSING+="worktrees/"$'\n'
  fi
  if [ -n "$MISSING" ]; then
    read -rp "Add missing entries to .gitignore? (Y/n): " ADD_GITIGNORE
    if [ "$ADD_GITIGNORE" != "n" ] && [ "$ADD_GITIGNORE" != "N" ]; then
      echo "" >> "$PROJECT_DIR/.gitignore"
      echo "# reqdrive" >> "$PROJECT_DIR/.gitignore"
      echo "$MISSING" >> "$PROJECT_DIR/.gitignore"
      echo "Updated .gitignore"
    fi
  fi
fi

echo ""
echo "Done! Next steps:"
echo "  1. Add requirements files to $REQ_DIR/"
echo "  2. Edit reqdrive.json to configure dependencies"
echo "  3. Customize $AGENT_DIR/prompt.md for your project"
echo "  4. Run: reqdrive validate"
echo "  5. Run: reqdrive run REQ-01"
