#!/usr/bin/env bash
# verification.sh - Phase 3 verification logic, shared by `run` and `verify`.
#
# Named verification.sh (not verify.sh) to stay distinct from the archived
# archive/v1-complex/lib/verify.sh.
#
# Bash functions return a single integer, so the multi-value results below
# are communicated via named globals rather than a return value. Callers
# must read the relevant VERIFY_* globals immediately after calling the
# corresponding function, before calling it again.
#
#   verify_collect <prd_file> <max_retries>
#     Sets (always overwritten, even when prd_file is absent):
#       VERIFY_STORIES_TOTAL      - story count in the PRD (0 if no PRD)
#       VERIFY_STORIES_COMPLETED  - stories with passes == true
#       VERIFY_STORIES_FAILED     - stories with passes != true that have
#                                    exhausted max_retries attempts
#       VERIFY_STORIES_REMAINING  - stories with passes != true; always an
#                                    integer (0 when no PRD), never null.
#                                    Callers that need "no PRD" to mean
#                                    "unknown" should branch on
#                                    VERIFY_PRD_PRESENT, not this value.
#       VERIFY_PRD_PRESENT        - 1 if prd_file exists, else 0
#
#   verify_run_tests <agent_dir>
#     Runs $REQDRIVE_TEST_COMMAND (if configured) and writes
#     $agent_dir/verification.test.log. Tri-state return — do not collapse
#     to a boolean:
#       0 - tests ran and passed
#       1 - tests ran and failed
#       2 - no testCommand configured (not run at all)
#     Because a plain function call's non-zero return trips `set -e`,
#     callers in this codebase capture it via `cmd || rc=$?`, never a bare
#     call followed by `case $?`.
#
#   verify_write_summary <agent_dir> <req_id> <max_iterations> <mode>
#     Writes $agent_dir/verification-summary.json via a temp file + mv
#     (atomic). Reads the VERIFY_* globals above plus the RUN_SUMMARY_*
#     globals (RUN_SUMMARY_ITERATIONS, RUN_SUMMARY_TESTS_*,
#     RUN_SUMMARY_COMMITS_*, RUN_SUMMARY_VERIFICATION_PASSED) set by the
#     implementation loop in run_pipeline. max_iterations is an explicit
#     parameter because it is a run_pipeline local, not a global.
#       mode=full  - write stories/prd_present/iterations/tests/commits/
#                    verification_passed entirely from the current globals.
#                    This is what run_pipeline uses.
#       mode=merge - recompute stories/prd_present/verification_passed from
#                    the current globals, but preserve iterations/tests/
#                    commits from the EXISTING verification-summary.json
#                    (a standalone `verify` has no implementation loop, so
#                    RUN_SUMMARY_* would otherwise zero out the evidence
#                    trail pr-create.sh renders into the PR table). Returns
#                    3 if there is no existing file to merge into.

set -e

verify_collect() {
  local prd_file="$1"
  local max_retries="$2"

  VERIFY_STORIES_TOTAL=0
  VERIFY_STORIES_COMPLETED=0
  VERIFY_STORIES_FAILED=0
  VERIFY_STORIES_REMAINING=0
  VERIFY_PRD_PRESENT=0

  if [ -f "$prd_file" ]; then
    VERIFY_PRD_PRESENT=1
    VERIFY_STORIES_TOTAL=$(jq '.userStories | length' "$prd_file" 2>/dev/null || echo "0")
    VERIFY_STORIES_COMPLETED=$(jq '[.userStories[] | select(.passes == true)] | length' "$prd_file" 2>/dev/null || echo "0")
    VERIFY_STORIES_REMAINING=$(jq '[.userStories[] | select(.passes != true)] | length' "$prd_file" 2>/dev/null || echo "0")

    # Stories that exhausted their retry limit
    VERIFY_STORIES_FAILED=$(jq --argjson max "$max_retries" \
      '[.userStories[] | select(.passes != true and ((.attempts // 0) >= $max))] | length' \
      "$prd_file" 2>/dev/null || echo "0")
  fi
}

verify_run_tests() {
  local agent_dir="$1"
  local verification_log="$agent_dir/verification.test.log"

  if [ -n "${REQDRIVE_TEST_COMMAND:-}" ]; then
    log_info "Running final verification: $REQDRIVE_TEST_COMMAND"
    if eval "$REQDRIVE_TEST_COMMAND" > "$verification_log" 2>&1; then
      log_info "Final verification PASSED"
      return 0
    else
      log_warn "Final verification FAILED (see verification.test.log)"
      return 1
    fi
  else
    log_info "No testCommand configured, skipping final verification"
    return 2
  fi
}

verify_write_summary() {
  local agent_dir="$1"
  local req_id="$2"
  local max_iterations="$3"
  local mode="$4"

  local summary_file="$agent_dir/verification-summary.json"
  local tmp_file="$summary_file.tmp"

  local stories_remaining_json="null"
  local prd_present_json="false"
  if [ "$VERIFY_PRD_PRESENT" -eq 1 ]; then
    stories_remaining_json="$VERIFY_STORIES_REMAINING"
    prd_present_json="true"
  fi

  local iterations_run tests_passed tests_failed tests_skipped commits_verified commits_missing

  if [ "$mode" = "merge" ]; then
    if [ ! -f "$summary_file" ]; then
      return 3
    fi
    iterations_run=$(jq -r '.iterations.run' "$summary_file")
    tests_passed=$(jq -r '.tests.passed' "$summary_file")
    tests_failed=$(jq -r '.tests.failed' "$summary_file")
    tests_skipped=$(jq -r '.tests.skipped' "$summary_file")
    commits_verified=$(jq -r '.commits.verified' "$summary_file")
    commits_missing=$(jq -r '.commits.missing' "$summary_file")
  else
    iterations_run="${RUN_SUMMARY_ITERATIONS:-0}"
    tests_passed="${RUN_SUMMARY_TESTS_PASSED:-0}"
    tests_failed="${RUN_SUMMARY_TESTS_FAILED:-0}"
    tests_skipped="${RUN_SUMMARY_TESTS_SKIPPED:-0}"
    commits_verified="${RUN_SUMMARY_COMMITS_VERIFIED:-0}"
    commits_missing="${RUN_SUMMARY_COMMITS_MISSING:-0}"
  fi

  cat > "$tmp_file" <<VEOF
{
  "version": "0.3.0",
  "req_id": "$req_id",
  "timestamp": "$(date -Iseconds)",
  "stories": {
    "total": $VERIFY_STORIES_TOTAL,
    "completed": $VERIFY_STORIES_COMPLETED,
    "failed": $VERIFY_STORIES_FAILED,
    "remaining": $stories_remaining_json
  },
  "prd_present": $prd_present_json,
  "iterations": {
    "run": $iterations_run,
    "max": $max_iterations
  },
  "tests": {
    "passed": $tests_passed,
    "failed": $tests_failed,
    "skipped": $tests_skipped
  },
  "commits": {
    "verified": $commits_verified,
    "missing": $commits_missing
  },
  "verification_passed": ${RUN_SUMMARY_VERIFICATION_PASSED:-null}
}
VEOF

  mv "$tmp_file" "$summary_file"
}
