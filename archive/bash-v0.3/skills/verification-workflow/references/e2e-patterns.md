# E2E Patterns with Playwright

## Setup

```bash
npm install -D @playwright/test
npx playwright install chromium
```

```typescript
// playwright.config.ts
import { defineConfig } from '@playwright/test';

export default defineConfig({
  testDir: './tests/e2e',
  testMatch: '**/*.spec.ts',
  fullyParallel: true,
  retries: process.env.CI ? 2 : 0,
  use: {
    baseURL: 'http://localhost:3000', // Adjust port as detected
    trace: 'on-first-retry',
    screenshot: 'only-on-failure',
  },
});
```

## Common Patterns

### Page Navigation

```typescript
import { test, expect } from '@playwright/test';

test('navigates to dashboard after login', async ({ page }) => {
  await page.goto('/login');
  await page.fill('[name="email"]', 'user@example.com');
  await page.fill('[name="password"]', 'password123');
  await page.click('button[type="submit"]');

  await expect(page).toHaveURL('/dashboard');
  await expect(page.locator('h1')).toHaveText('Welcome');
});
```

### Form Interaction

```typescript
test('submits contact form', async ({ page }) => {
  await page.goto('/contact');

  await page.fill('#name', 'John Doe');
  await page.fill('#email', 'john@example.com');
  await page.fill('#message', 'Hello there');
  await page.click('button:has-text("Send")');

  await expect(page.locator('.success-message')).toBeVisible();
});
```

### Waiting for Network

```typescript
test('loads data from API', async ({ page }) => {
  await page.goto('/users');

  // Wait for API response
  await page.waitForResponse(resp =>
    resp.url().includes('/api/users') && resp.status() === 200
  );

  await expect(page.locator('.user-card')).toHaveCount(10);
});
```

### Interactive Elements

```typescript
test('dropdown selection works', async ({ page }) => {
  await page.goto('/settings');

  await page.click('[data-testid="theme-select"]');
  await page.click('text=Dark Mode');

  await expect(page.locator('body')).toHaveClass(/dark/);
});

test('modal opens and closes', async ({ page }) => {
  await page.goto('/');

  await page.click('button:has-text("Open Modal")');
  await expect(page.locator('[role="dialog"]')).toBeVisible();

  await page.click('[aria-label="Close"]');
  await expect(page.locator('[role="dialog"]')).not.toBeVisible();
});
```

### Table/List Interactions

```typescript
test('sorts table by column', async ({ page }) => {
  await page.goto('/users');

  await page.click('th:has-text("Name")');

  const firstRow = page.locator('tbody tr').first();
  await expect(firstRow.locator('td').first()).toHaveText('Aaron');
});

test('filters list items', async ({ page }) => {
  await page.goto('/products');

  await page.fill('[placeholder="Search..."]', 'laptop');

  const items = page.locator('.product-item');
  await expect(items).toHaveCount(3);
  await expect(items.first()).toContainText('laptop');
});
```

## Discovery Pattern (When No Requirements)

When exploring unknown functionality, use this pattern to document behavior:

```typescript
import { test, expect } from '@playwright/test';

test.describe('Feature Discovery: [Feature Name]', () => {
  test.beforeEach(async ({ page }) => {
    await page.goto('/feature-path');
  });

  test('documents initial state', async ({ page }) => {
    // Screenshot for reference
    await page.screenshot({ path: 'tests/e2e/screenshots/initial-state.png' });

    // Document what's visible
    const heading = await page.locator('h1').textContent();
    console.log('Heading:', heading);

    const buttons = await page.locator('button').allTextContents();
    console.log('Available buttons:', buttons);

    // Add assertions based on what you observe
    await expect(page.locator('h1')).toBeVisible();
  });

  test('documents interaction behavior', async ({ page }) => {
    // Try primary action
    await page.click('button:first-of-type');

    // Document result
    await page.screenshot({ path: 'tests/e2e/screenshots/after-click.png' });

    // What changed?
    const result = await page.locator('.result, .output, [data-testid]').textContent();
    console.log('Result after click:', result);
  });
});
```

## Converting E2E Observations to Unit Tests

After E2E confirms behavior, extract unit tests:

**E2E Finding**: Clicking "Add to Cart" increments cart count from 0 to 1

**Generated Unit Test**:
```typescript
// tests/components/AddToCartButton.spec.tsx
describe('AddToCartButton', () => {
  it('increments cart count when clicked', () => {
    const { result } = renderHook(() => useCart());
    expect(result.current.count).toBe(0);

    act(() => result.current.addItem({ id: '1', name: 'Product' }));

    expect(result.current.count).toBe(1);
  });
});
```

**E2E Finding**: Form shows "Invalid email" when submitting "bad-email"

**Generated Unit Test**:
```typescript
// tests/utils/validation.spec.ts
describe('validateEmail', () => {
  it('returns error for invalid email format', () => {
    expect(validateEmail('bad-email')).toEqual({
      valid: false,
      error: 'Invalid email'
    });
  });
});
```

## Running E2E Tests

```bash
# Run all E2E tests
npx playwright test

# Run specific file
npx playwright test tests/e2e/login.spec.ts

# Run with UI mode (interactive)
npx playwright test --ui

# Run headed (see browser)
npx playwright test --headed

# Generate report
npx playwright show-report
```
