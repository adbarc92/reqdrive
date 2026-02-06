# reqdrive Tests

This directory contains unit, E2E, and simple tests for reqdrive v0.3.0.

## Running Tests

```bash
# Simple tests (no bats dependency)
bash tests/simple-test.sh

# All bats tests
./tests/run-tests.sh

# Specific test suite
bats tests/unit/schema.bats
bats tests/unit/config.bats
bats tests/e2e/pipeline.bats

# Verbose / TAP output
bats --verbose-run tests/unit/
bats --formatter tap tests/
```

## Prerequisites

For bats tests, install bats-core:

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

## Test Structure

```
tests/
├── simple-test.sh         # Dependency-free test suite (bash only)
├── run-tests.sh           # Bats test runner
├── test_helper/
│   └── common.bash        # Shared test utilities and helpers
├── unit/                  # Unit tests for lib/*.sh
│   ├── cli.bats           # CLI dispatch tests
│   ├── config.bats        # Config loading tests
│   ├── schema.bats        # Schema validation tests
│   └── validate.bats      # Validate command tests
├── e2e/                   # End-to-end tests
│   └── pipeline.bats      # Full pipeline flow tests
└── fixtures/              # Test data (v0.3.0 format)
    ├── valid-manifest.json
    ├── invalid-manifest-missing-fields.json
    ├── valid-prd.json
    ├── invalid-prd-missing-stories.json
    └── valid-checkpoint.json
```

## Writing Tests

Tests use bats syntax:

```bash
@test "description of test" {
  run some_command
  [ "$status" -eq 0 ]
  [[ "$output" == *"expected text"* ]]
}
```

See https://bats-core.readthedocs.io/ for documentation.
