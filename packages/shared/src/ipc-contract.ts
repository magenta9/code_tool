import type { AiTaskEvent, AiTaskRequest, CreateAiTaskResult } from "./types/ai";
import type { DiagnosticEvent, LogInput } from "./types/diagnostics";
import type { AppSettings, MiniMaxProviderStatus, SaveMiniMaxKeyInput } from "./types/settings";
import type { ToolId } from "./types/tools";
import type { AssetRecord, CreateHistoryInput, HistoryEntry, HistoryRecord } from "./types/history";
import type {
  DecodeJwtResult,
  ImageBase64Inspection,
  JsonDiffResult,
  JsonToolInput,
  JsonToolResult,
  TimestampConversionInput,
  TimestampConversionResult,
  WordCloudResult
} from "./tools";

export interface SystemStatus {
  appName: "CodeTool";
  platform: string;
  version: string;
  userDataPath: string;
}

export interface SaveImageBase64Input {
  base64: string;
  filename?: string;
}

export interface IpcContract {
  system: {
    getStatus(): Promise<SystemStatus>;
  };
  tools: {
    runJsonTool(input: JsonToolInput): Promise<JsonToolResult>;
    runJsonDiff(input: { left: string; right: string }): Promise<JsonDiffResult>;
    convertTimestamp(input: TimestampConversionInput): Promise<TimestampConversionResult>;
    decodeJwt(input: { token: string }): Promise<DecodeJwtResult>;
    analyzeWordCloud(input: { text: string }): Promise<WordCloudResult>;
    inspectImageBase64(input: { base64: string }): Promise<ImageBase64Inspection>;
    saveImageBase64(input: SaveImageBase64Input): Promise<AssetRecord>;
  };
  history: {
    list(input?: { toolId?: ToolId; limit?: number }): Promise<HistoryEntry[]>;
    load(input: { id: string }): Promise<HistoryRecord | null>;
    create(input: CreateHistoryInput): Promise<HistoryRecord>;
    delete(input: { id: string }): Promise<{ deleted: boolean }>;
  };
  settings: {
    get(): Promise<AppSettings>;
    save(input: Partial<AppSettings>): Promise<AppSettings>;
  };
  secrets: {
    getMiniMaxStatus(): Promise<MiniMaxProviderStatus>;
    saveMiniMaxKey(input: SaveMiniMaxKeyInput): Promise<MiniMaxProviderStatus>;
    clearMiniMaxKey(): Promise<MiniMaxProviderStatus>;
  };
  ai: {
    createTask(input: AiTaskRequest): Promise<CreateAiTaskResult>;
    cancelTask(input: { taskId: string }): Promise<{ cancelled: boolean }>;
    onTaskEvent(callback: (event: AiTaskEvent) => void): () => void;
  };
  log: {
    write(input: LogInput): Promise<DiagnosticEvent>;
    list(input?: { referenceId?: string; limit?: number }): Promise<DiagnosticEvent[]>;
    openDirectory(): Promise<{ opened: boolean; path: string }>;
  };
}

export const ipcContractHandlers = [
  "system.getStatus",
  "tools.runJsonTool",
  "tools.runJsonDiff",
  "tools.convertTimestamp",
  "tools.decodeJwt",
  "tools.analyzeWordCloud",
  "tools.inspectImageBase64",
  "tools.saveImageBase64",
  "history.list",
  "history.load",
  "history.create",
  "history.delete",
  "settings.get",
  "settings.save",
  "secrets.getMiniMaxStatus",
  "secrets.saveMiniMaxKey",
  "secrets.clearMiniMaxKey",
  "ai.createTask",
  "ai.cancelTask",
  "log.write",
  "log.list",
  "log.openDirectory"
] as const;

export type IpcContractHandlerName = (typeof ipcContractHandlers)[number];
