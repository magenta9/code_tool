import type { ToolId } from "./tools";
import type { AssetRecord } from "./history";

export type AiToolId = Extract<ToolId, "aiChat" | "piAgent" | "aiSpeech" | "aiImage" | "aiMusic">;
export type ThinkingLevel = "off" | "minimal" | "low" | "medium" | "high" | "xhigh";
export type PiToolPolicy = "readOnly" | "workspaceWrite";

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
  | { type: "failed"; taskId: string; referenceId: string; message: string }
  | { type: "agent_start"; taskId: string; sessionId: string; provider: "pi"; workspaceRoot: string }
  | { type: "agent_end"; taskId: string; sessionId: string; provider: "pi"; messageCount: number }
  | { type: "message_start"; taskId: string; sessionId: string; messageId: string; role: "assistant" | "user" }
  | {
    type: "message_delta";
    taskId: string;
    sessionId: string;
    messageId: string;
    deltaType: "text" | "thinking";
    text: string;
  }
  | {
    type: "message_end";
    taskId: string;
    sessionId: string;
    messageId: string;
    role: "assistant" | "user";
    stopReason?: string;
  }
  | {
    type: "toolcall_start";
    phase: "call" | "execution";
    taskId: string;
    sessionId: string;
    messageId: string;
    toolCallId: string;
    toolName: string;
    args: Record<string, unknown>;
  }
  | {
    type: "toolcall_delta";
    phase: "call" | "execution";
    taskId: string;
    sessionId: string;
    toolCallId: string;
    toolName: string;
    partialText: string;
    partialResult?: Record<string, unknown>;
  }
  | {
    type: "toolcall_end";
    phase: "call" | "execution";
    taskId: string;
    sessionId: string;
    toolCallId: string;
    toolName: string;
    resultText: string;
    result?: Record<string, unknown>;
    isError: boolean;
  }
  | {
    type: "queue_update";
    taskId: string;
    sessionId: string;
    steering: string[];
    followUp: string[];
  }
  | {
    type: "compaction_start";
    taskId: string;
    sessionId: string;
    reason: "manual" | "threshold" | "overflow";
  }
  | {
    type: "compaction_end";
    taskId: string;
    sessionId: string;
    reason: "manual" | "threshold" | "overflow";
    summary?: string;
    errorMessage?: string;
    aborted: boolean;
    willRetry: boolean;
  }
  | {
    type: "auto_retry_start";
    taskId: string;
    sessionId: string;
    attempt: number;
    maxAttempts: number;
    delayMs: number;
    errorMessage: string;
  }
  | {
    type: "auto_retry_end";
    taskId: string;
    sessionId: string;
    attempt: number;
    success: boolean;
    finalError?: string;
  };

export type AiTaskRequest =
  | {
    provider: "minimax";
    toolId: "aiChat";
    prompt: string;
    history?: Array<{ role: "user" | "assistant" | "system"; content: string }>;
    model?: string;
  }
  | {
    provider: "pi";
    toolId: "piAgent";
    prompt: string;
    workspaceRoot: string;
    sessionId?: string;
    providerName?: string;
    modelId?: string;
    thinkingLevel?: ThinkingLevel;
    toolPolicy?: PiToolPolicy;
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
  sessionId?: string;
}
