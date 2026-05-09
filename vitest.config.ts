import { defineConfig } from "vitest/config";

export default defineConfig({
  test: {
    environment: "jsdom",
    globals: true,
    include: ["packages/**/*.{test,spec}.{ts,tsx}"],
    setupFiles: ["packages/renderer/src/test/setup.ts"]
  },
  resolve: {
    alias: {
      "@codetool/shared": "/Users/zhang/code/ai/code_tool/packages/shared/src/index.ts"
    }
  }
});
