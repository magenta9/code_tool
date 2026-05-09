import type { DiagnosticEvent, LogInput } from "@codetool/shared";
import type Database from "better-sqlite3";
import { mkdirSync, appendFileSync } from "node:fs";
import { join } from "node:path";
import { randomUUID } from "node:crypto";

export class AppLogger {
  constructor(
    private readonly database: Database.Database,
    private readonly logRoot: string
  ) {
    mkdirSync(logRoot, { recursive: true });
  }

  write(input: LogInput & { source?: DiagnosticEvent["source"] }): DiagnosticEvent {
    const event: DiagnosticEvent = {
      id: randomUUID(),
      timestamp: new Date().toISOString(),
      level: input.level,
      message: input.message,
      source: input.source ?? "main",
      referenceId: input.referenceId,
      toolId: input.toolId,
      metadata: input.metadata
    };
    this.database
      .prepare(
        `INSERT INTO diagnostic_events
         (id, timestamp, level, message, source, reference_id, tool_id, metadata_json)
         VALUES (@id, @timestamp, @level, @message, @source, @referenceId, @toolId, @metadataJson)`
      )
      .run({ ...event, metadataJson: event.metadata ? JSON.stringify(event.metadata) : null });
    appendFileSync(join(this.logRoot, "codetool.jsonl"), `${JSON.stringify(event)}\n`);
    return event;
  }

  list(input: { referenceId?: string; limit?: number } = {}): DiagnosticEvent[] {
    const limit = Math.min(Math.max(input.limit ?? 200, 1), 1000);
    const rows = input.referenceId
      ? this.database
          .prepare("SELECT * FROM diagnostic_events WHERE reference_id = ? ORDER BY timestamp DESC LIMIT ?")
          .all(input.referenceId, limit)
      : this.database.prepare("SELECT * FROM diagnostic_events ORDER BY timestamp DESC LIMIT ?").all(limit);
    return (rows as DiagnosticRow[]).map((row) => ({
      id: row.id,
      timestamp: row.timestamp,
      level: row.level,
      message: row.message,
      source: row.source,
      referenceId: row.reference_id ?? undefined,
      toolId: row.tool_id ?? undefined,
      metadata: row.metadata_json ? (JSON.parse(row.metadata_json) as Record<string, unknown>) : undefined
    }));
  }
}

interface DiagnosticRow {
  id: string;
  timestamp: string;
  level: DiagnosticEvent["level"];
  message: string;
  source: DiagnosticEvent["source"];
  reference_id: string | null;
  tool_id: DiagnosticEvent["toolId"] | null;
  metadata_json: string | null;
}
