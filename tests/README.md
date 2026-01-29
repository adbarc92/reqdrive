# reqdrive Tests

This directory contains unit and E2E tests for reqdrive.

## Prerequisites

Install bats-core and helper libraries:

```bash
# macOS
brew install bats-core

# Ubuntu/Debian
apt-get install bats

# Or clone directly
git clone https://github.com/bats-core/bats-core.git tests/bats
git clone https://github.com/bats-core/bats-support.git tests/test_helper/bats-support
git clone https://github.com/bats-core/bats-assert.git tests/test_helper/bats-assert
```

## Running Tests

```bash
# Run all tests
./tests/run-tests.sh

# Run specific test file
bats tests/unit/config.bats

# Run with verbose output
bats --verbose-run tests/unit/

# Run with TAP output (CI-friendly)
bats --formatter tap tests/
```

## Test Structure

```
tests/
├── run-tests.sh           # Test runner script
├── test_helper/
│   └── common.bash        # Shared test utilities
├── unit/                  # Unit tests for lib/*.sh
│   ├── config.bats
│   ├── validate.bats
│   └── worktree.bats
├── e2e/                   # End-to-end tests
│   └── pipeline.bats
└── fixtures/              # Test data
    ├── valid-manifest.json
    └── invalid-manifest.json
```

## Writing Tests

Tests use bats syntax:

```bash
@test "description of test" {
  run some_command
  assert_success
  assert_output --partial "expected text"
}
```

See https://bats-core.readthedocs.io/ for documentation.
