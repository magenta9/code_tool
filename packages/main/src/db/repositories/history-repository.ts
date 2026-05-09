import type { CreateHistoryInput, HistoryEntry, HistoryRecord, ToolId } from "@codetool/shared";
import type Database from "better-sqlite3";
import { randomUUID } from "node:crypto";

interface HistoryRow {
  id: string;
  tool_id: ToolId;
  title: string;
  summary: string;
  payload_json: string;
  reference_id: string | null;
  asset_ids_json: string;
  created_at: string;
  updated_at: string;
}

export class HistoryRepository {
  constructor(private readonly database: Database.Database) {}

  list(input: { toolId?: ToolId; limit?: number } = {}): HistoryEntry[] {
    const limit = Math.min(Math.max(input.limit ?? 80, 1), 500);
    const rows = input.toolId
      ? this.database
          .prepare("SELECT * FROM history_entries WHERE tool_id = ? ORDER BY created_at DESC LIMIT ?")
          .all(input.toolId, limit)
      : this.database.prepare("SELECT * FROM history_entries ORDER BY created_at DESC LIMIT ?").all(limit);
    return (rows as HistoryRow[]).map(rowToEntry);
  }

  load(id: string): HistoryRecord | null {
    const row = this.database.prepare("SELECT * FROM history_entries WHERE id = ?").get(id) as HistoryRow | undefined;
    if (!row) return null;
    return {
      ...rowToEntry(row),
      payload: JSON.parse(row.payload_json) as unknown
    };
  }

  create(input: CreateHistoryInput): HistoryRecord {
    const now = new Date().toISOString();
    const record: HistoryRecord = {
      id: randomUUID(),
      toolId: input.toolId,
      title: input.title,
      summary: input.summary,
      payload: input.payload,
      referenceId: input.referenceId,
      assetIds: input.assetIds ?? [],
      createdAt: now,
      updatedAt: now
    };
    this.database
      .prepare(
        `INSERT INTO history_entries
         (id, tool_id, title, summary, payload_json, reference_id, asset_ids_json, created_at, updated_at)
         VALUES (@id, @toolId, @title, @summary, @payloadJson, @referenceId, @assetIdsJson, @createdAt, @updatedAt)`
      )
      .run({
        ...record,
        payloadJson: JSON.stringify(record.payload),
        assetIdsJson: JSON.stringify(record.assetIds)
      });
    return record;
  }

  delete(id: string): boolean {
    const result = this.database.prepare("DELETE FROM history_entries WHERE id = ?").run(id);
    return result.changes > 0;
  }
}

function rowToEntry(row: HistoryRow): HistoryEntry {
  return {
    id: row.id,
    toolId: row.tool_id,
    title: row.title,
    summary: row.summary,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
    referenceId: row.reference_id ?? undefined,
    assetIds: JSON.parse(row.asset_ids_json) as string[]
  };
}
