import type { ToolId } from "./tools";

export interface HistoryEntry {
  id: string;
  toolId: ToolId;
  title: string;
  summary: string;
  createdAt: string;
  updatedAt: string;
  referenceId?: string;
  assetIds: string[];
}

export interface HistoryRecord<TPayload = unknown> extends HistoryEntry {
  payload: TPayload;
}

export interface CreateHistoryInput<TPayload = unknown> {
  toolId: ToolId;
  title: string;
  summary: string;
  payload: TPayload;
  referenceId?: string;
  assetIds?: string[];
}

export interface AssetRecord {
  id: string;
  kind: "image" | "speech" | "music" | "generic";
  filename: string;
  mimeType: string;
  byteLength: number;
  relativePath: string;
  createdAt: string;
  metadata?: Record<string, unknown>;
}
