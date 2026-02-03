#!/usr/bin/env bash
# errors.sh - Standard exit codes and error handling for reqdrive

# ── Exit Codes ───────────────────────────────────────────────────────────────
# These codes follow common Unix conventions and provide specific error context

EXIT_SUCCESS=0
EXIT_GENERAL_ERROR=1
EXIT_MISSING_DEPENDENCY=2
EXIT_CONFIG_ERROR=3
EXIT_GIT_ERROR=4
EXIT_AGENT_ERROR=5
EXIT_PR_ERROR=6
EXIT_USER_ABORT=7
EXIT_PREFLIGHT_FAILED=8

# ── Error Messages ───────────────────────────────────────────────────────────

declare -A EXIT_MESSAGES=(
  [0]="Success"
  [1]="General error"
  [2]="Missing required dependency"
  [3]="Configuration error"
  [4]="Git operation failed"
  [5]="Agent execution failed"
  [6]="PR creation failed"
  [7]="User aborted operation"
  [8]="Pre-flight checks failed"
)

# ── Helper Functions ─────────────────────────────────────────────────────────

# Get human-readable message for exit code
get_exit_message() {
  local code="$1"
  echo "${EXIT_MESSAGES[$code]:-Unknown error}"
}

# Exit with code and optional message
die() {
  local code="${1:-1}"
  local msg="${2:-}"

  if [ -n "$msg" ]; then
    echo "[ERROR] $msg" >&2
  else
    echo "[ERROR] $(get_exit_message "$code")" >&2
  fi

  exit "$code"
}

# Exit if last command failed
die_on_error() {
  local code=$?
  local msg="${1:-Command failed}"

  if [ $code -ne 0 ]; then
    die "$EXIT_GENERAL_ERROR" "$msg (exit code: $code)"
  fi
}
