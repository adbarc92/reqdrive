#!/usr/bin/env bash
# sanitize.sh - Input sanitization functions for reqdrive

# ── Dangerous Pattern Detection ──────────────────────────────────────────────

# Patterns that could indicate shell injection attempts
DANGEROUS_PATTERNS=(
  # Command substitution
  '\$\('
  '`'
  # Variable expansion
  '\${'
  # Redirections
  '>[[:space:]]*/'
  '<[[:space:]]*/'
  # Command chaining
  ';[[:space:]]*rm'
  ';[[:space:]]*sudo'
  '&&[[:space:]]*rm'
  '&&[[:space:]]*sudo'
  '\|[[:space:]]*rm'
  '\|[[:space:]]*sudo'
  # Dangerous commands
  'rm[[:space:]]+-rf[[:space:]]+/'
  'chmod[[:space:]]+777'
  'curl.*\|.*sh'
  'wget.*\|.*sh'
  'eval[[:space:]]'
)

# ── Sanitization Functions ───────────────────────────────────────────────────

# Sanitize content before including in prompts
# This escapes shell metacharacters that could be dangerous
sanitize_for_prompt() {
  local content="$1"

  # Replace backticks with single quotes (prevents command substitution)
  content="${content//\`/\'}"

  # Escape dollar signs (prevents variable expansion)
  content="${content//\$/\\\$}"

  echo "$content"
}

# Sanitize a label for use with gh CLI
# GitHub labels can contain most characters, but we need to properly quote them
sanitize_label() {
  local label="$1"

  # Remove leading/trailing whitespace
  label="$(echo "$label" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"

  # Replace any shell-dangerous characters with safe equivalents
  # These characters could break the gh CLI argument parsing
  label="${label//\"/\'}"      # Replace double quotes with single
  label="${label//\`/\'}"      # Replace backticks with single quotes
  label="${label//\$/}"        # Remove dollar signs
  label="${label//\\/}"        # Remove backslashes
  label="${label//;/}"         # Remove semicolons
  label="${label//|/}"         # Remove pipes
  label="${label//&/}"         # Remove ampersands
  label="${label//>/}"         # Remove redirects
  label="${label//</}"         # Remove redirects

  # Truncate to reasonable length (GitHub limit is 50 chars)
  label="${label:0:50}"

  echo "$label"
}

# ── Validation Functions ─────────────────────────────────────────────────────

# Validate requirement content for suspicious patterns
# Returns 0 if safe, 1 if suspicious patterns found
# Outputs warnings to stderr
validate_requirement_content() {
  local content="$1"
  local strict="${2:-false}"  # If true, fail instead of warn
  local found_issues=0

  for pattern in "${DANGEROUS_PATTERNS[@]}"; do
    if echo "$content" | grep -qE "$pattern"; then
      found_issues=1
      local match
      match=$(echo "$content" | grep -oE ".{0,20}$pattern.{0,20}" | head -1)
      echo "[WARN] Suspicious pattern detected: $pattern" >&2
      echo "       Context: ...${match}..." >&2
    fi
  done

  if [ "$found_issues" -eq 1 ]; then
    echo "" >&2
    echo "[WARN] The requirement file contains patterns that could be dangerous." >&2
    echo "       This may be intentional (e.g., documenting shell commands)." >&2
    echo "       Please review the content before proceeding." >&2

    if [ "$strict" = "true" ]; then
      echo "" >&2
      echo "[ERROR] Strict mode enabled. Aborting due to suspicious content." >&2
      echo "        Use --force to bypass this check." >&2
      return 1
    fi
  fi

  return 0
}

# Validate a file path to prevent path traversal
validate_file_path() {
  local path="$1"
  local base_dir="$2"

  # Check for path traversal attempts
  if [[ "$path" == *".."* ]]; then
    echo "[ERROR] Path traversal detected in: $path" >&2
    return 1
  fi

  # Resolve to absolute path and verify it's under base_dir
  local resolved
  resolved=$(cd "$base_dir" && realpath -m "$path" 2>/dev/null) || {
    echo "[ERROR] Could not resolve path: $path" >&2
    return 1
  }

  local resolved_base
  resolved_base=$(realpath "$base_dir")

  if [[ "$resolved" != "$resolved_base"* ]]; then
    echo "[ERROR] Path escapes base directory: $path" >&2
    return 1
  fi

  return 0
}
