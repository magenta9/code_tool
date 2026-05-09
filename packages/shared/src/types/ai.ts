import type { ToolId } from "./tools";
import type { AssetRecord } from "./history";

export type AiToolId = Extract<ToolId, "aiChat" | "aiSpeech" | "aiImage" | "aiMusic">;

export interface GeneratedArtifact {
  id: string;
  kind: "text" | "image" | "speech" | "music";
  mimeType: string;
  url?: string;
  asset?: AssetRecord;
  text?: string;
  metadata?: Record<string, unknown>;
}

export type AiTaskEvent =
  | { type: "started"; taskId: string; referenceId: string; toolId: AiToolId }
  | { type: "progress"; taskId: string; stage: string; message?: string }
  | { type: "delta"; taskId: string; text: string }
  | { type: "artifact"; taskId: string; artifact: GeneratedArtifact }
  | { type: "completed"; taskId: string; historyId: string; durationMs: number }
  | { type: "cancelled"; taskId: string }
  | { type: "failed"; taskId: string; referenceId: string; message: string };

export type AiTaskRequest =
  | {
      provider: "minimax";
      toolId: "aiChat";
      prompt: string;
      history?: Array<{ role: "user" | "assistant" | "system"; content: string }>;
      model?: string;
    }
  | {
      provider: "minimax";
      toolId: "aiSpeech";
      text: string;
      voiceId?: string;
      model?: string;
    }
  | {
      provider: "minimax";
      toolId: "aiImage";
      prompt: string;
      aspectRatio?: "1:1" | "16:9" | "9:16" | "4:3" | "3:4";
      count?: number;
      referenceAssetIds?: string[];
      model?: string;
    }
  | {
      provider: "minimax";
      toolId: "aiMusic";
      prompt: string;
      lyrics?: string;
      style?: string;
      model?: string;
    };

export interface CreateAiTaskResult {
  taskId: string;
}
