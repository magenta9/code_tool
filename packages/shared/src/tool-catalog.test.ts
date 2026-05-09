import { describe, expect, it } from "vitest";
import { toolCatalog, toolIds } from "./tool-catalog";

describe("toolCatalog", () => {
  it("contains the ten bundled tools with stable routes", () => {
    expect(toolCatalog).toHaveLength(10);
    expect(new Set(toolIds).size).toBe(10);
    for (const tool of toolCatalog) {
      expect(tool.routePath).toMatch(/^\/tools\//);
      expect(tool.title.length).toBeGreaterThan(2);
    }
  });
});
