# Unit Test Patterns

## Vitest (Preferred for Vite projects)

### Setup

```bash
npm install -D vitest @testing-library/react @testing-library/jest-dom jsdom
```

```typescript
// vitest.config.ts
import { defineConfig } from 'vitest/config';
import react from '@vitejs/plugin-react';

export default defineConfig({
  plugins: [react()],
  test: {
    environment: 'jsdom',
    setupFiles: ['./tests/setup.ts'],
    include: ['tests/**/*.spec.{ts,tsx}'],
  },
});
```

```typescript
// tests/setup.ts
import '@testing-library/jest-dom';
```

### Component Test Pattern

```typescript
// tests/components/Button.spec.tsx
import { describe, it, expect, vi } from 'vitest';
import { render, screen, fireEvent } from '@testing-library/react';
import { Button } from '@/components/Button';

describe('Button', () => {
  it('renders with label', () => {
    render(<Button>Click me</Button>);
    expect(screen.getByRole('button')).toHaveTextContent('Click me');
  });

  it('calls onClick when clicked', () => {
    const handleClick = vi.fn();
    render(<Button onClick={handleClick}>Click</Button>);
    fireEvent.click(screen.getByRole('button'));
    expect(handleClick).toHaveBeenCalledOnce();
  });

  it('is disabled when disabled prop is true', () => {
    render(<Button disabled>Click</Button>);
    expect(screen.getByRole('button')).toBeDisabled();
  });
});
```

### Hook Test Pattern

```typescript
// tests/hooks/useCounter.spec.ts
import { describe, it, expect } from 'vitest';
import { renderHook, act } from '@testing-library/react';
import { useCounter } from '@/hooks/useCounter';

describe('useCounter', () => {
  it('initializes with default value', () => {
    const { result } = renderHook(() => useCounter());
    expect(result.current.count).toBe(0);
  });

  it('increments count', () => {
    const { result } = renderHook(() => useCounter());
    act(() => result.current.increment());
    expect(result.current.count).toBe(1);
  });
});
```

### API/Service Test Pattern

```typescript
// tests/services/api.spec.ts
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { fetchUsers } from '@/services/api';

describe('fetchUsers', () => {
  beforeEach(() => {
    vi.resetAllMocks();
  });

  it('returns users on success', async () => {
    const mockUsers = [{ id: 1, name: 'John' }];
    global.fetch = vi.fn().mockResolvedValue({
      ok: true,
      json: () => Promise.resolve(mockUsers),
    });

    const result = await fetchUsers();
    expect(result).toEqual(mockUsers);
  });

  it('throws on network error', async () => {
    global.fetch = vi.fn().mockRejectedValue(new Error('Network error'));
    await expect(fetchUsers()).rejects.toThrow('Network error');
  });
});
```

## Jest (Alternative)

### Setup

```bash
npm install -D jest @types/jest ts-jest @testing-library/react @testing-library/jest-dom
```

```javascript
// jest.config.js
module.exports = {
  preset: 'ts-jest',
  testEnvironment: 'jsdom',
  setupFilesAfterEnv: ['<rootDir>/tests/setup.ts'],
  testMatch: ['**/tests/**/*.spec.{ts,tsx}'],
  moduleNameMapper: {
    '^@/(.*)$': '<rootDir>/src/$1',
  },
};
```

### Patterns are identical to Vitest

Replace `vi` with `jest`:
- `vi.fn()` → `jest.fn()`
- `vi.mock()` → `jest.mock()`
- `vi.resetAllMocks()` → `jest.resetAllMocks()`

## React Native / Expo

### Setup

```bash
npm install -D jest @testing-library/react-native @types/jest
```

```javascript
// jest.config.js
module.exports = {
  preset: 'jest-expo',
  setupFilesAfterEnv: ['@testing-library/jest-native/extend-expect'],
  testMatch: ['**/tests/**/*.spec.{ts,tsx}'],
};
```

### Component Pattern

```typescript
// tests/components/Button.spec.tsx
import { render, fireEvent } from '@testing-library/react-native';
import { Button } from '@/components/Button';

describe('Button', () => {
  it('renders correctly', () => {
    const { getByText } = render(<Button title="Press me" onPress={() => {}} />);
    expect(getByText('Press me')).toBeTruthy();
  });

  it('calls onPress when pressed', () => {
    const onPress = jest.fn();
    const { getByText } = render(<Button title="Press" onPress={onPress} />);
    fireEvent.press(getByText('Press'));
    expect(onPress).toHaveBeenCalled();
  });
});
```

## Generating Tests from Requirements

When requirements specify behavior, map each requirement to a test:

**Requirement**: "User can submit form with valid email"

```typescript
it('submits form when email is valid', async () => {
  render(<LoginForm />);
  await userEvent.type(screen.getByLabelText('Email'), 'user@example.com');
  await userEvent.click(screen.getByRole('button', { name: 'Submit' }));
  expect(mockSubmit).toHaveBeenCalledWith({ email: 'user@example.com' });
});
```

**Requirement**: "Form shows error for invalid email"

```typescript
it('shows error for invalid email', async () => {
  render(<LoginForm />);
  await userEvent.type(screen.getByLabelText('Email'), 'invalid');
  await userEvent.click(screen.getByRole('button', { name: 'Submit' }));
  expect(screen.getByText('Please enter a valid email')).toBeInTheDocument();
});
```
