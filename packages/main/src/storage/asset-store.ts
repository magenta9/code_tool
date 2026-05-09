import type { AssetRecord } from "@codetool/shared";
import { mkdirSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { randomUUID } from "node:crypto";
import type Database from "better-sqlite3";

export class AssetStore {
  constructor(
    private readonly database: Database.Database,
    private readonly rootPath: string
  ) {}

  writeAsset(input: {
    kind: AssetRecord["kind"];
    bytes: Uint8Array;
    mimeType: string;
    extension: string;
    filename?: string;
    metadata?: Record<string, unknown>;
  }): AssetRecord {
    const id = randomUUID();
    const createdAt = new Date().toISOString();
    const safeName = sanitizeFilename(input.filename || `${id}.${input.extension}`);
    const relativePath = `${input.kind}/${id}-${safeName}`;
    const absolutePath = join(this.rootPath, relativePath);
    mkdirSync(join(this.rootPath, input.kind), { recursive: true });
    writeFileSync(absolutePath, input.bytes);

    const record: AssetRecord = {
      id,
      kind: input.kind,
      filename: safeName,
      mimeType: input.mimeType,
      byteLength: input.bytes.byteLength,
      relativePath,
      createdAt,
      metadata: input.metadata
    };

    this.database
      .prepare(
        `INSERT INTO assets (id, kind, filename, mime_type, byte_length, relative_path, metadata_json, created_at)
         VALUES (@id, @kind, @filename, @mimeType, @byteLength, @relativePath, @metadataJson, @createdAt)`
      )
      .run({
        ...record,
        metadataJson: record.metadata ? JSON.stringify(record.metadata) : null
      });

    return record;
  }
}

function sanitizeFilename(filename: string): string {
  return filename.replace(/[^a-zA-Z0-9._-]/g, "-").slice(0, 120) || "asset";
}
