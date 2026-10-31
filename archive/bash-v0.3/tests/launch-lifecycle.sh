#!/usr/bin/env bash
# Launch lifecycle cases that need real background processes.
# Linux only — nohup, PID liveness and signal trapping are unreliable
# under MSYS2 (see CLAUDE.md, Known Pitfalls).
# shellcheck disable=SC2317
# SC2317: the fake-claude heredoc body looks unreachable to shellcheck
set -uo pipefail

case "$(uname -s)" in
  Linux) ;;
  *) echo "SKIP: launch lifecycle requires Linux (got $(uname -s))"; exit 0 ;;
esac

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
export REQDRIVE_ROOT="$PROJECT_ROOT"

PASS=0
FAIL=0
TOTAL=0

test_result() {
  local name="$1"
  local status="$2"
  TOTAL=$((TOTAL + 1))
  if [ "$status" -eq 0 ]; then
    PASS=$((PASS + 1))
    echo "PASS: $name"
  else
    FAIL=$((FAIL + 1))
    echo "FAIL: $name"
  fi
}

TEST_TEMP=$(mktemp -d) || { echo "FATAL: mktemp failed" >&2; exit 1; }
LAUNCH_PID=""

# Kill the full process tree rooted at $1, not just the top PID. `reqdrive
# launch` backgrounds with plain `nohup ... &` (no setsid), so the detached
# run shares this script's process group — a pgid-based `kill -- -PGID`
# would risk taking out the test script itself. Walk descendants by PPID
# instead: timeout/claude/tee (and anything claude forks, e.g. the fake
# claude's `cat`/`sleep`) are children/grandchildren of $LAUNCH_PID that a
# plain `kill -9 "$LAUNCH_PID"` leaves behind to reparent to PID 1.
kill_tree() {
  local pid="$1"
  local child
  for child in $(pgrep -P "$pid" 2>/dev/null || true); do
    kill_tree "$child"
  done
  kill -9 "$pid" 2>/dev/null || true
}

cleanup() {
  if [ -n "$LAUNCH_PID" ]; then
    kill_tree "$LAUNCH_PID"
  fi
  rm -rf "$TEST_TEMP"
}
trap cleanup EXIT

# ── Fixture: scratch project with a fake claude that blocks past every
# assertion window in this file. Task 14's ph_fake_claude (pipeline-harness.sh)
# returns synchronously, which is unusable here — these cases need the
# background run to still be alive while we probe it.
PH_ROOT="$TEST_TEMP/proj"
PH_BIN="$PH_ROOT/bin"
mkdir -p "$PH_ROOT/docs/requirements" "$PH_BIN"

git -C "$PH_ROOT" init -q
git -C "$PH_ROOT" config user.email "test@example.com"
git -C "$PH_ROOT" config user.name "Test"
git -C "$PH_ROOT" checkout -q -b main

cat > "$PH_ROOT/reqdrive.json" <<'EOF'
{
  "version": "0.3.0",
  "requirementsDir": "docs/requirements",
  "testCommand": "",
  "maxIterations": 3,
  "baseBranch": "main"
}
EOF

cat > "$PH_ROOT/docs/requirements/REQ-01-demo.md" <<'EOF'
# REQ-01: Demo requirement

Add a marker file.

## Acceptance Criteria
- A file named MARKER.txt exists
EOF

git -C "$PH_ROOT" add -A
git -C "$PH_ROOT" commit -q -m "chore: scaffold"

# Fake claude: consumes the prompt, then blocks well past every assertion
# window below. The pipeline never reaches planning output or PR creation —
# fine, because every case here checks process/PID state, not pipeline output.
cat > "$PH_BIN/claude" <<'CLAUDEEOF'
#!/usr/bin/env bash
cat > /dev/null
sleep 120
CLAUDEEOF
chmod +x "$PH_BIN/claude"

export PATH="$PH_BIN:$PATH"

run_json="$PH_ROOT/.reqdrive/runs/req-01/run.json"

# ── Case 1: launch starts a detached run ────────────────────────────────────
launch_out=$(cd "$PH_ROOT" && "$REQDRIVE_ROOT/bin/reqdrive" launch REQ-01 2>&1)
launch_rc=$?

(
  set -e
  [ "$launch_rc" -eq 0 ]
  echo "$launch_out" | grep -q "Launched REQ-01"
)
test_result "launch: prints 'Launched REQ-01' with a PID" $?

LAUNCH_PID=$(echo "$launch_out" | grep -oE 'PID [0-9]+' | head -1 | grep -oE '[0-9]+')

(
  set -e
  [ -n "$LAUNCH_PID" ]
  kill -0 "$LAUNCH_PID" 2>/dev/null
)
test_result "launch: reported PID is a live process" $?

# Poll for run.json to appear with status "running". pipeline_setup() and the
# initial write_run_status() call happen before the fake claude blocks, so
# this should land well under a second.
waited=0
while [ ! -f "$run_json" ] && [ "$waited" -lt 100 ]; do
  sleep 0.1
  waited=$((waited + 1))
done

(
  set -e
  [ -f "$run_json" ]
  [ "$(jq -r '.status' "$run_json")" = "running" ]
  [ -f "$PH_ROOT/.reqdrive/runs/req-01/output.log" ]
)
test_result "launch: run.json and output.log exist with status running" $?

# ── Case 4: duplicate launch while the first run is still alive is blocked ──
dup_out=$(cd "$PH_ROOT" && "$REQDRIVE_ROOT/bin/reqdrive" launch REQ-01 2>&1)
dup_rc=$?

(
  set -e
  [ "$dup_rc" -ne 0 ]
  echo "$dup_out" | grep -qi "already running"
)
test_result "launch: duplicate launch is refused while the run is alive" $?

# ── Case 6: kill -9 the process, status reports crashed ─────────────────────
kill_tree "$LAUNCH_PID"

waited=0
while kill -0 "$LAUNCH_PID" 2>/dev/null && [ "$waited" -lt 100 ]; do
  sleep 0.1
  waited=$((waited + 1))
done

status_out=$(cd "$PH_ROOT" && "$REQDRIVE_ROOT/bin/reqdrive" status REQ-01 2>&1)

(
  set -e
  if kill -0 "$LAUNCH_PID" 2>/dev/null; then
    echo "process still alive after kill -9" >&2
    exit 1
  fi
  echo "$status_out" | grep -qi "crashed"
)
test_result "launch: status reports crashed after kill -9" $?

LAUNCH_PID=""  # confirmed dead above; nothing left for cleanup to kill

echo ""
echo "========================================"
echo "  Launch lifecycle: $PASS passed, $FAIL failed, $TOTAL total"
echo "========================================"

[ "$FAIL" -eq 0 ]
