import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: {
    testTimeout: 600_000,
    hookTimeout: 600_000,
    teardownTimeout: 60_000,
    include: ['tests/**/*.test.ts'],
  },
});
