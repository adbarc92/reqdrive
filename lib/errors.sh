#!/usr/bin/env bash
# errors.sh — Error handling utilities for reqdrive
# Provides structured error handling, logging, and retry logic.

# ── Configuration ─────────────────────────────────────────────────────
REQDRIVE_LOG_LEVEL="${REQDRIVE_LOG_LEVEL:-info}"  # debug, info, warn, error
REQDRIVE_MAX_RETRIES="${REQDRIVE_MAX_RETRIES:-3}"
REQDRIVE_RETRY_DELAY="${REQDRIVE_RETRY_DELAY:-5}"  # seconds

# ── Logging ───────────────────────────────────────────────────────────

_log_level_num() {
  case "$1" in
    debug) echo 0 ;;
    info)  echo 1 ;;
    warn)  echo 2 ;;
    error) echo 3 ;;
    *)     echo 1 ;;
  esac
}

_should_log() {
  local msg_level="$1"
  local current_level="${REQDRIVE_LOG_LEVEL:-info}"
  [ "$(_log_level_num "$msg_level")" -ge "$(_log_level_num "$current_level")" ]
}

log_debug() {
  _should_log debug && echo "[DEBUG] $(date +%H:%M:%S) $*" >&2
}

log_info() {
  _should_log info && echo "[INFO]  $(date +%H:%M:%S) $*" >&2
}

log_warn() {
  _should_log warn && echo "[WARN]  $(date +%H:%M:%S) $*" >&2
}

log_error() {
  _should_log error && echo "[ERROR] $(date +%H:%M:%S) $*" >&2
}

# ── Error Codes ───────────────────────────────────────────────────────
# Standardized exit codes for different failure types

ERR_CONFIG=10        # Configuration error
ERR_PREREQ=11        # Missing prerequisite
ERR_GIT=20           # Git operation failed
ERR_WORKTREE=21      # Worktree operation failed
ERR_PRD=30           # PRD generation failed
ERR_PRD_INVALID=31   # PRD validation failed
ERR_AGENT=40         # Agent execution failed
ERR_AGENT_TIMEOUT=41 # Agent timed out
ERR_VERIFY=50        # Verification failed
ERR_PR=60            # PR creation failed
ERR_CLAUDE=70        # Claude CLI error
ERR_CLAUDE_TIMEOUT=71# Claude timed out
ERR_UNKNOWN=99       # Unknown error

error_name() {
  case "$1" in
    10) echo "CONFIG_ERROR" ;;
    11) echo "PREREQ_ERROR" ;;
    20) echo "GIT_ERROR" ;;
    21) echo "WORKTREE_ERROR" ;;
    30) echo "PRD_ERROR" ;;
    31) echo "PRD_INVALID" ;;
    40) echo "AGENT_ERROR" ;;
    41) echo "AGENT_TIMEOUT" ;;
    50) echo "VERIFY_ERROR" ;;
    60) echo "PR_ERROR" ;;
    70) echo "CLAUDE_ERROR" ;;
    71) echo "CLAUDE_TIMEOUT" ;;
    *)  echo "UNKNOWN_ERROR" ;;
  esac
}

# ── State Management ──────────────────────────────────────────────────

# Save checkpoint state for resume capability
save_checkpoint() {
  local run_dir="$1"
  local req_id="$2"
  local stage="$3"
  local status="$4"
  local extra_json="${5:-{}}"

  local checkpoint_file="$run_dir/${req_id}-checkpoint.json"

  cat > "$checkpoint_file" <<EOF
{
  "req": "$req_id",
  "stage": "$stage",
  "status": "$status",
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "extra": $extra_json
}
EOF
  log_debug "Checkpoint saved: $stage -> $status"
}

# Load checkpoint state
load_checkpoint() {
  local run_dir="$1"
  local req_id="$2"

  local checkpoint_file="$run_dir/${req_id}-checkpoint.json"
  if [ -f "$checkpoint_file" ]; then
    cat "$checkpoint_file"
  else
    echo "{}"
  fi
}

# Get last completed stage from checkpoint
get_last_stage() {
  local run_dir="$1"
  local req_id="$2"

  local checkpoint
  checkpoint=$(load_checkpoint "$run_dir" "$req_id")
  echo "$checkpoint" | jq -r '.stage // "none"'
}

# ── Retry Logic ───────────────────────────────────────────────────────

# Retry a command with exponential backoff
# Usage: retry_command <max_retries> <delay> <command...>
retry_command() {
  local max_retries="$1"
  local delay="$2"
  shift 2

  local attempt=1
  local status=0

  while [ "$attempt" -le "$max_retries" ]; do
    log_debug "Attempt $attempt/$max_retries: $*"

    if "$@"; then
      return 0
    fi
    status=$?

    if [ "$attempt" -lt "$max_retries" ]; then
      log_warn "Command failed (attempt $attempt/$max_retries), retrying in ${delay}s..."
      sleep "$delay"
      delay=$((delay * 2))  # Exponential backoff
    fi

    attempt=$((attempt + 1))
  done

  log_error "Command failed after $max_retries attempts: $*"
  return "$status"
}

# ── Timeout Handling ──────────────────────────────────────────────────

# Run command with timeout (cross-platform)
# Usage: run_with_timeout <seconds> <command...>
run_with_timeout() {
  local timeout_secs="$1"
  shift

  # Check if timeout command is available
  if command -v timeout &>/dev/null; then
    timeout "$timeout_secs" "$@"
    return $?
  fi

  # Fallback: use background process with kill
  "$@" &
  local pid=$!

  (
    sleep "$timeout_secs"
    if kill -0 "$pid" 2>/dev/null; then
      log_warn "Command timed out after ${timeout_secs}s, killing PID $pid"
      kill -TERM "$pid" 2>/dev/null
      sleep 2
      kill -KILL "$pid" 2>/dev/null
    fi
  ) &
  local watchdog=$!

  wait "$pid"
  local status=$?

  # Kill watchdog if still running
  kill "$watchdog" 2>/dev/null
  wait "$watchdog" 2>/dev/null

  return "$status"
}

# ── Claude CLI Wrapper ────────────────────────────────────────────────

# Run claude with timeout and error handling
# Usage: run_claude <timeout_secs> <security_args> <model> <prompt>
# Returns: 0 on success, ERR_CLAUDE on failure, ERR_CLAUDE_TIMEOUT on timeout
run_claude() {
  local timeout_secs="$1"
  local security_args="$2"
  local model="$3"
  local prompt="$4"
  local output_var="${5:-CLAUDE_OUTPUT}"

  log_debug "Running claude (timeout: ${timeout_secs}s, model: $model)"

  local output
  local status

  # Note: </dev/null prevents stdin from being passed through
  # shellcheck disable=SC2086
  output=$(run_with_timeout "$timeout_secs" claude $security_args --model "$model" -p "$prompt" </dev/null 2>&1)
  status=$?

  # Export output to specified variable
  eval "$output_var=\"\$output\""

  if [ "$status" -eq 124 ] || [ "$status" -eq 137 ]; then
    log_error "Claude timed out after ${timeout_secs}s"
    return $ERR_CLAUDE_TIMEOUT
  elif [ "$status" -ne 0 ]; then
    log_error "Claude failed with status $status"
    return $ERR_CLAUDE
  fi

  return 0
}

# ── Cleanup Handlers ──────────────────────────────────────────────────

# Stack of cleanup functions
_CLEANUP_STACK=()

# Push a cleanup function onto the stack
push_cleanup() {
  _CLEANUP_STACK+=("$1")
}

# Pop and execute cleanup functions
run_cleanup() {
  local i
  for ((i=${#_CLEANUP_STACK[@]}-1; i>=0; i--)); do
    log_debug "Running cleanup: ${_CLEANUP_STACK[i]}"
    eval "${_CLEANUP_STACK[i]}" || log_warn "Cleanup failed: ${_CLEANUP_STACK[i]}"
  done
  _CLEANUP_STACK=()
}

# Set up trap for cleanup on exit/interrupt
setup_cleanup_trap() {
  trap 'run_cleanup' EXIT
  trap 'log_warn "Interrupted"; run_cleanup; exit 130' INT TERM
}

# ── Validation Helpers ────────────────────────────────────────────────

# Validate JSON file against basic schema requirements
# Usage: validate_prd_json <file>
validate_prd_json() {
  local file="$1"

  if [ ! -f "$file" ]; then
    log_error "PRD file not found: $file"
    return $ERR_PRD
  fi

  # Check valid JSON
  if ! jq empty "$file" 2>/dev/null; then
    log_error "PRD is not valid JSON: $file"
    return $ERR_PRD_INVALID
  fi

  # Check required fields
  local project source_req stories_count
  project=$(jq -r '.project // empty' "$file")
  source_req=$(jq -r '.sourceReq // empty' "$file")
  stories_count=$(jq '.userStories | length' "$file" 2>/dev/null || echo 0)

  if [ -z "$project" ]; then
    log_error "PRD missing required field: project"
    return $ERR_PRD_INVALID
  fi

  if [ -z "$source_req" ]; then
    log_error "PRD missing required field: sourceReq"
    return $ERR_PRD_INVALID
  fi

  if [ "$stories_count" -eq 0 ]; then
    log_error "PRD has no user stories"
    return $ERR_PRD_INVALID
  fi

  # Validate each story has required fields
  local invalid_stories
  invalid_stories=$(jq '[.userStories[] | select(.id == null or .title == null or .acceptanceCriteria == null)] | length' "$file")
  if [ "$invalid_stories" -gt 0 ]; then
    log_error "PRD has $invalid_stories stories with missing required fields"
    return $ERR_PRD_INVALID
  fi

  log_debug "PRD validation passed: $stories_count stories"
  return 0
}

# ── Status Reporting ──────────────────────────────────────────────────

# Update status file with structured data
update_status() {
  local status_file="$1"
  local req="$2"
  local status="$3"
  shift 3

  # Build extra fields from remaining args (key=value pairs)
  local extra_json="{"
  local first=true
  while [ $# -gt 0 ]; do
    local key="${1%%=*}"
    local value="${1#*=}"
    if [ "$first" = true ]; then
      first=false
    else
      extra_json+=","
    fi
    # Quote string values, leave numbers/booleans as-is
    if [[ "$value" =~ ^[0-9]+$ ]] || [ "$value" = "true" ] || [ "$value" = "false" ]; then
      extra_json+="\"$key\":$value"
    else
      extra_json+="\"$key\":\"$value\""
    fi
    shift
  done
  extra_json+="}"

  # Merge with base status
  jq -n \
    --arg req "$req" \
    --arg status "$status" \
    --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --argjson extra "$extra_json" \
    '{req: $req, status: $status, timestamp: $ts} + $extra' \
    > "$status_file"
}

# ── Assertions ────────────────────────────────────────────────────────

# Assert a condition or exit with error
# Usage: assert <condition> <error_message> [exit_code]
assert() {
  local condition="$1"
  local message="$2"
  local code="${3:-$ERR_UNKNOWN}"

  if ! eval "$condition"; then
    log_error "Assertion failed: $message"
    exit "$code"
  fi
}

# Assert file exists
assert_file_exists() {
  local file="$1"
  local message="${2:-File not found: $file}"
  assert "[ -f '$file' ]" "$message" $ERR_PREREQ
}

# Assert directory exists
assert_dir_exists() {
  local dir="$1"
  local message="${2:-Directory not found: $dir}"
  assert "[ -d '$dir' ]" "$message" $ERR_PREREQ
}

# Assert command exists
assert_command_exists() {
  local cmd="$1"
  local message="${2:-Required command not found: $cmd}"
  assert "command -v '$cmd' &>/dev/null" "$message" $ERR_PREREQ
}
