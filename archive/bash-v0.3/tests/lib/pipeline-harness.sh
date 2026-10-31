#!/usr/bin/env bash
# Drive lib/run.sh's run_pipeline against fake claude/gh binaries in a
# scratch git repo. Sourced by tests/simple-test.sh.
# shellcheck disable=SC1091,SC2317
# SC1091: dynamic source paths ($REQDRIVE_ROOT/lib/*.sh)
# SC2317: fake-binary heredoc bodies look unreachable to shellcheck

ph_setup() {
  PH_ROOT="$1"
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

  # run_pipeline's create_pr pushes to "origin" unconditionally; give it a
  # real (bare, local) remote so the push — and therefore the gh pr create
  # call the test asserts on — is actually reached. The remote path is
  # namespaced by the full PH_ROOT (not a shared sibling), so multiple
  # ph_setup calls in one suite run each get their own remote and the
  # hard-coded REQ-01 branch never collides across cases.
  local remote_dir="${PH_ROOT}-origin.git"
  git init -q --bare "$remote_dir"
  git -C "$PH_ROOT" remote add origin "$remote_dir"

  export PH_ROOT PH_BIN
}

# ph_fake_claude full|noprd|nopasses
ph_fake_claude() {
  local mode="$1"
  cat > "$PH_BIN/claude" <<PHEOF
#!/usr/bin/env bash
# Fake agent. Reads a prompt on stdin, writes artifacts, prints a summary.
set -u
cat > /dev/null   # consume the prompt
mode="$mode"
run_dir="\$(ls -d "$PH_ROOT"/.reqdrive/runs/* 2>/dev/null | head -1)"
[ -n "\$run_dir" ] || { echo "no run dir"; exit 0; }
prd="\$run_dir/prd.json"

if [ ! -f "\$prd" ] && [ "\$mode" != "noprd" ]; then
  if [ "\$mode" = "nopasses" ]; then
    cat > "\$prd" <<'JEOF'
{"version":"0.3.0","project":"demo","sourceReq":"REQ-01",
 "userStories":[
   {"id":"US-001","title":"First","description":"d","acceptanceCriteria":["a"],"priority":1},
   {"id":"US-002","title":"Second","description":"d","acceptanceCriteria":["a"],"priority":2}]}
JEOF
  else
    cat > "\$prd" <<'JEOF'
{"version":"0.3.0","project":"demo","sourceReq":"REQ-01",
 "userStories":[
   {"id":"US-001","title":"First","description":"d","acceptanceCriteria":["a"],"priority":1,"passes":false},
   {"id":"US-002","title":"Second","description":"d","acceptanceCriteria":["a"],"priority":2,"passes":false}]}
JEOF
  fi
  echo "Planning complete."
  exit 0
fi

# Implementation turn: mark the highest-priority incomplete story done.
if [ -f "\$prd" ] && [ "\$mode" = "full" ]; then
  next=\$(jq -r '[.userStories[] | select(.passes == false)] | sort_by(.priority) | .[0].id // empty' "\$prd")
  if [ -n "\$next" ]; then
    jq --arg id "\$next" '(.userStories[] | select(.id == \$id)).passes = true' "\$prd" > "\$prd.t" && mv "\$prd.t" "\$prd"
    echo "impl \$next" >> "$PH_ROOT/MARKER.txt"
    git -C "$PH_ROOT" add -A
    git -C "$PH_ROOT" commit -q -m "feat: [\$next] - work"
    echo '\`\`\`json:iteration-summary'
    echo "{\"storyId\":\"\$next\",\"action\":\"implemented\",\"filesChanged\":[\"MARKER.txt\"],\"testsRun\":true,\"testsPassed\":true,\"committed\":true,\"notes\":\"ok\"}"
    echo '\`\`\`'
    remaining=\$(jq '[.userStories[] | select(.passes == false)] | length' "\$prd")
    [ "\$remaining" -eq 0 ] && echo "<promise>COMPLETE</promise>"
    exit 0
  fi
fi
echo "nothing to do"
exit 0
PHEOF
  chmod +x "$PH_BIN/claude"
}

ph_fake_gh() {
  cat > "$PH_BIN/gh" <<PHEOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$PH_ROOT/gh-args.log"
case "\$1 \$2" in
  "pr create") echo "https://github.com/test/repo/pull/1" ;;
  *) : ;;
esac
exit 0
PHEOF
  chmod +x "$PH_BIN/gh"
}

# ph_run <req-id> — returns run_pipeline's exit code
ph_run() {
  local req="$1"
  (
    set -euo pipefail
    export PATH="$PH_BIN:$PATH"
    export REQDRIVE_ROOT="$REQDRIVE_ROOT"
    export REQDRIVE_INTERACTIVE=false
    export REQDRIVE_UNSAFE=true
    cd "$PH_ROOT"
    source "$REQDRIVE_ROOT/lib/errors.sh"
    source "$REQDRIVE_ROOT/lib/schema.sh"
    source "$REQDRIVE_ROOT/lib/sanitize.sh"
    source "$REQDRIVE_ROOT/lib/config.sh"
    source "$REQDRIVE_ROOT/lib/preflight.sh"
    source "$REQDRIVE_ROOT/lib/run.sh"
    reqdrive_load_config
    run_pipeline "$req"
  ) >"$PH_ROOT/run.log" 2>&1
  echo $?
}

ph_gh_args() { cat "$PH_ROOT/gh-args.log" 2>/dev/null || true; }
