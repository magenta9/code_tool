import { describe, expect, it } from "vitest";
import { toolCatalog, toolIds } from "./tool-catalog";

describe("toolCatalog", () => {
  it("contains the bundled tools with stable routes", () => {
    expect(toolCatalog).toHaveLength(13);
    expect(new Set(toolIds).size).toBe(13);
    for (const tool of toolCatalog) {
      expect(tool.routePath).toMatch(/^\/tools\//);
      expect(tool.title.length).toBeGreaterThan(2);
    }
  });
});
