import type { JsonValue } from "../types/tools";

export type JsonDiffKind = "added" | "removed" | "modified" | "typeChanged";

export interface JsonDiffChange {
  kind: JsonDiffKind;
  path: string;
  left?: JsonValue;
  right?: JsonValue;
}

export interface JsonDiffResult {
  ok: boolean;
  changes: JsonDiffChange[];
  summary: Record<JsonDiffKind, number>;
  error?: string;
}

export function diffJsonText(leftText: string, rightText: string): JsonDiffResult {
  try {
    const left = JSON.parse(leftText) as JsonValue;
    const right = JSON.parse(rightText) as JsonValue;
    const changes: JsonDiffChange[] = [];
    diffJsonValue(left, right, "$", changes);
    return {
      ok: true,
      changes,
      summary: summarize(changes)
    };
  } catch (error) {
    return {
      ok: false,
      changes: [],
      summary: summarize([]),
      error: error instanceof Error ? error.message : "Invalid JSON"
    };
  }
}

function diffJsonValue(left: JsonValue | undefined, right: JsonValue | undefined, path: string, out: JsonDiffChange[]): void {
  if (left === undefined && right !== undefined) {
    out.push({ kind: "added", path, right });
    return;
  }
  if (left !== undefined && right === undefined) {
    out.push({ kind: "removed", path, left });
    return;
  }
  if (left === undefined || right === undefined) return;

  if (Array.isArray(left) || Array.isArray(right)) {
    if (!Array.isArray(left) || !Array.isArray(right)) {
      out.push({ kind: "typeChanged", path, left, right });
      return;
    }
    const length = Math.max(left.length, right.length);
    for (let index = 0; index < length; index += 1) {
      diffJsonValue(left[index], right[index], `${path}[${index}]`, out);
    }
    return;
  }

  const leftType = left === null ? "null" : typeof left;
  const rightType = right === null ? "null" : typeof right;
  if (leftType !== rightType) {
    out.push({ kind: "typeChanged", path, left, right });
    return;
  }

  if (left !== null && right !== null && typeof left === "object" && typeof right === "object") {
    const keys = new Set([...Object.keys(left), ...Object.keys(right)]);
    for (const key of [...keys].sort()) {
      diffJsonValue(left[key], right[key], `${path}.${key}`, out);
    }
    return;
  }

  if (left !== right) {
    out.push({ kind: "modified", path, left, right });
  }
}

function summarize(changes: JsonDiffChange[]): Record<JsonDiffKind, number> {
  return changes.reduce<Record<JsonDiffKind, number>>(
    (summary, change) => {
      summary[change.kind] += 1;
      return summary;
    },
    { added: 0, removed: 0, modified: 0, typeChanged: 0 }
  );
}
