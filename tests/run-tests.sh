#!/usr/bin/env bash
# Test runner for reqdrive
# Usage: ./tests/run-tests.sh [options] [test-files...]
#
# Options:
#   --unit       Run only unit tests
#   --e2e        Run only E2E tests
#   --verbose    Run with verbose output
#   --tap        Output in TAP format (CI-friendly)
#   --help       Show this help

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

# Default options
RUN_UNIT=true
RUN_E2E=true
BATS_OPTS=()

# Parse arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    --unit)
      RUN_UNIT=true
      RUN_E2E=false
      shift
      ;;
    --e2e)
      RUN_UNIT=false
      RUN_E2E=true
      shift
      ;;
    --verbose)
      BATS_OPTS+=("--verbose-run")
      shift
      ;;
    --tap)
      BATS_OPTS+=("--formatter" "tap")
      shift
      ;;
    --help)
      head -20 "$0" | tail -15 | sed 's/^# //'
      exit 0
      ;;
    *)
      # Assume it's a test file
      BATS_OPTS+=("$1")
      RUN_UNIT=false
      RUN_E2E=false
      shift
      ;;
  esac
done

# Check for bats
if ! command -v bats &>/dev/null; then
  echo -e "${RED}Error: bats-core is not installed${NC}"
  echo ""
  echo "Install it with:"
  echo "  macOS:  brew install bats-core"
  echo "  Ubuntu: apt-get install bats"
  echo ""
  echo "Or clone the repositories:"
  echo "  git clone https://github.com/bats-core/bats-core.git $SCRIPT_DIR/bats"
  echo "  Add $SCRIPT_DIR/bats/bin to your PATH"
  exit 1
fi

# Check for required tools
check_tool() {
  if ! command -v "$1" &>/dev/null; then
    echo -e "${YELLOW}Warning: $1 not found (some tests may be skipped)${NC}"
  fi
}

check_tool jq
check_tool git

echo "========================================"
echo "  reqdrive test suite"
echo "========================================"
echo ""

# Export project root for tests
export REQDRIVE_ROOT="$PROJECT_ROOT"

# Track results
TOTAL_TESTS=0
FAILED_TESTS=0

run_test_suite() {
  local suite_name="$1"
  local suite_dir="$2"

  if [ ! -d "$suite_dir" ]; then
    echo -e "${YELLOW}Skipping $suite_name (directory not found: $suite_dir)${NC}"
    return 0
  fi

  local test_files=("$suite_dir"/*.bats)
  if [ ! -f "${test_files[0]}" ]; then
    echo -e "${YELLOW}Skipping $suite_name (no test files found)${NC}"
    return 0
  fi

  echo -e "${GREEN}Running $suite_name tests...${NC}"
  echo "----------------------------------------"

  if bats "${BATS_OPTS[@]}" "$suite_dir"/*.bats; then
    echo -e "${GREEN}$suite_name: PASSED${NC}"
  else
    echo -e "${RED}$suite_name: FAILED${NC}"
    FAILED_TESTS=$((FAILED_TESTS + 1))
  fi
  echo ""
}

# Run requested test suites
if $RUN_UNIT; then
  run_test_suite "Unit" "$SCRIPT_DIR/unit"
fi

if $RUN_E2E; then
  run_test_suite "E2E" "$SCRIPT_DIR/e2e"
fi

# If specific files were provided, they're already in BATS_OPTS
if [ ${#BATS_OPTS[@]} -gt 0 ] && ! $RUN_UNIT && ! $RUN_E2E; then
  echo "Running specified tests..."
  bats "${BATS_OPTS[@]}"
fi

# Summary
echo "========================================"
if [ "$FAILED_TESTS" -eq 0 ]; then
  echo -e "${GREEN}All test suites passed!${NC}"
  exit 0
else
  echo -e "${RED}$FAILED_TESTS test suite(s) failed${NC}"
  exit 1
fi
