import type { JsonValue } from "../types/tools";

export interface JsonToolInput {
  text: string;
  mode: "format" | "minify" | "validate";
}

export interface JsonStats {
  bytes: number;
  keys: number;
  arrays: number;
  objects: number;
  primitives: number;
  maxDepth: number;
}

export interface JsonToolResult {
  ok: boolean;
  output: string;
  error?: string;
  stats?: JsonStats;
}

export function runJsonTool(input: JsonToolInput): JsonToolResult {
  try {
    const parsed = JSON.parse(input.text) as JsonValue;
    const stats = collectJsonStats(parsed);
    if (input.mode === "minify") {
      return { ok: true, output: JSON.stringify(parsed), stats };
    }
    return { ok: true, output: JSON.stringify(parsed, null, input.mode === "validate" ? 2 : 2), stats };
  } catch (error) {
    return {
      ok: false,
      output: "",
      error: error instanceof Error ? error.message : "Invalid JSON"
    };
  }
}

export function collectJsonStats(value: JsonValue): JsonStats {
  const stats: JsonStats = {
    bytes: new TextEncoder().encode(JSON.stringify(value)).byteLength,
    keys: 0,
    arrays: 0,
    objects: 0,
    primitives: 0,
    maxDepth: 0
  };

  function visit(node: JsonValue, depth: number): void {
    stats.maxDepth = Math.max(stats.maxDepth, depth);
    if (Array.isArray(node)) {
      stats.arrays += 1;
      for (const child of node) visit(child, depth + 1);
      return;
    }
    if (node !== null && typeof node === "object") {
      stats.objects += 1;
      const entries = Object.entries(node);
      stats.keys += entries.length;
      for (const [, child] of entries) visit(child, depth + 1);
      return;
    }
    stats.primitives += 1;
  }

  visit(value, 1);
  return stats;
}
