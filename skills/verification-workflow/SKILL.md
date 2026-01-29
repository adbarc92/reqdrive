---
name: verification-workflow
description: Automated feature verification combining E2E testing, unit test generation, and static analysis. Use when asked to "verify this feature works", "check if ready to ship", "test this implementation", or validate that code meets requirements. Supports React/Next.js, React Native/Expo, and Spring Boot projects. Generates tests in a `tests/` directory using `.spec` naming convention.
---

# Verification Workflow

Automated verification to determine if a feature is complete and ready to ship.

## Workflow Overview

```
1. Detect project type and locate dev server
2. Run static analysis (TypeScript, linting)
3. Check for requirements (requirements.md or requirements/)
4. If requirements exist → Generate unit tests from requirements
5. If no requirements → Run E2E to confirm behavior, then generate unit tests
6. Run all tests
7. Report: "Ready to ship" or "Issues found"
```

## Step 1: Environment Detection

Detect project type by checking for:
- `package.json` with `next` → Next.js project
- `package.json` with `expo` → Expo/React Native project
- `pom.xml` or `build.gradle` → Spring Boot project

Find running dev server by checking ports in order: 3000, 8080, 8081.

```bash
for port in 3000 8080 8081; do
  if curl -s -o /dev/null -w "%{http_code}" "http://localhost:$port" | grep -q "200\|302\|304"; then
    echo "Dev server found on port $port"
    break
  fi
done
```

## Step 2: Static Analysis

Run before any other verification:

```bash
# TypeScript projects
npx tsc --noEmit

# Linting
npm run lint 2>/dev/null || npx eslint . --ext .ts,.tsx,.js,.jsx
```

Fix any type errors or lint issues before proceeding.

## Step 3: Requirements Check

Look for requirements in this order:
1. `requirements.md` in project root
2. `requirements/` folder in project root
3. Context provided in conversation

If requirements found → Step 4a. Otherwise → Step 4b.

## Step 4a: Unit Tests from Requirements

When requirements exist, generate unit tests directly:

1. Parse requirements into testable assertions
2. Create test file in `tests/` directory with `.spec.ts` or `.spec.tsx` extension
3. Use Vitest (preferred) or Jest based on project config
4. See `references/unit-test-patterns.md` for framework-specific patterns

## Step 4b: E2E Verification First

When no requirements exist, use E2E to discover and confirm behavior:

1. Use Playwright to navigate the running application
2. Document observed behavior as test assertions
3. Generate unit tests that lock in confirmed behavior
4. See `references/e2e-patterns.md` for Playwright patterns

### Playwright Setup (if not installed)

```bash
npm install -D playwright @playwright/test
npx playwright install chromium
```

## Step 5: Run Tests

```bash
# Unit tests (Vitest)
npx vitest run

# Unit tests (Jest)
npx jest

# E2E tests (Playwright)
npx playwright test

# Spring Boot tests
./mvnw test  # or ./gradlew test
```

## Step 6: Report Results

Provide a clear summary:

```
## Verification Report

**Status**: ✅ Ready to ship | ❌ Issues found

### Static Analysis
- TypeScript: ✅ No errors | ❌ X errors
- Linting: ✅ Passed | ❌ X issues

### Tests
- Unit tests: X passed, Y failed
- E2E tests: X passed, Y failed

### Issues Found (if any)
1. [Description of issue]

### Generated Test Files
- tests/feature-name.spec.ts
- tests/e2e/feature-name.spec.ts
```

## Test Directory Structure

```
project/
├── src/
│   └── components/
│       └── Button.tsx
├── tests/
│   ├── components/
│   │   └── Button.spec.tsx      # Unit tests
│   └── e2e/
│       └── user-flow.spec.ts    # E2E tests
```

## Framework References

- **Unit test patterns**: See `references/unit-test-patterns.md`
- **E2E patterns**: See `references/e2e-patterns.md`
- **Spring Boot patterns**: See `references/spring-boot-patterns.md`
