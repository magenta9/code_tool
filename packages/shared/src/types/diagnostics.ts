import type { ToolId } from "./tools";

export interface DiagnosticEvent {
  id: string;
  timestamp: string;
  level: "debug" | "info" | "warn" | "error";
  message: string;
  source: "renderer" | "main" | "provider";
  referenceId?: string;
  toolId?: ToolId;
  metadata?: Record<string, unknown>;
}

export interface LogInput {
  level: DiagnosticEvent["level"];
  message: string;
  toolId?: ToolId;
  referenceId?: string;
  metadata?: Record<string, unknown>;
}
