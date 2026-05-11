import type { AiTaskEvent, AiTaskRequest, CreateAiTaskResult } from "./types/ai";
import type { DiagnosticEvent, LogInput } from "./types/diagnostics";
import type { AppSettings, MiniMaxProviderStatus, SaveMiniMaxKeyInput } from "./types/settings";
import type { ToolId } from "./types/tools";
import type { AssetRecord, CreateHistoryInput, HistoryEntry, HistoryRecord } from "./types/history";
import type {
  CreateKanbanBoardInput,
  CreateKanbanCardInput,
  CreateKanbanColumnInput,
  CreateKanbanLabelInput,
  KanbanBoard,
  KanbanBoardExport,
  KanbanCard,
  KanbanCardPatch,
  KanbanColumn,
  KanbanColumnPatch,
  KanbanLabel
} from "./types/kanban";
import type {
  DecodeJwtResult,
  EncodeJwtInput,
  EncodeJwtResult,
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
    encodeJwt(input: EncodeJwtInput): Promise<EncodeJwtResult>;
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
  kanban: {
    listBoards(): Promise<KanbanBoard[]>;
    createBoard(input: CreateKanbanBoardInput): Promise<KanbanBoard>;
    renameBoard(input: { id: string; name: string }): Promise<KanbanBoard>;
    deleteBoard(input: { id: string }): Promise<void>;
    listColumns(input: { boardId: string; includeArchived?: boolean }): Promise<KanbanColumn[]>;
    createColumn(input: CreateKanbanColumnInput): Promise<KanbanColumn>;
    updateColumn(input: { id: string; patch: Partial<KanbanColumnPatch> }): Promise<KanbanColumn>;
    reorderColumn(input: { id: string; beforeId?: string; afterId?: string }): Promise<KanbanColumn>;
    archiveColumn(input: { id: string }): Promise<KanbanColumn>;
    restoreColumn(input: { id: string }): Promise<KanbanColumn>;
    listCards(input: { boardId: string; includeArchived?: boolean }): Promise<KanbanCard[]>;
    createCard(input: CreateKanbanCardInput): Promise<KanbanCard>;
    updateCard(input: { id: string; patch: Partial<KanbanCardPatch> }): Promise<KanbanCard>;
    deleteCard(input: { id: string }): Promise<void>;
    archiveCard(input: { id: string }): Promise<KanbanCard>;
    restoreCard(input: { id: string }): Promise<KanbanCard>;
    reorderCard(input: { id: string; toColumnId: string; beforeId?: string; afterId?: string }): Promise<KanbanCard>;
    listLabels(input: { boardId: string }): Promise<KanbanLabel[]>;
    createLabel(input: CreateKanbanLabelInput): Promise<KanbanLabel>;
    deleteLabel(input: { id: string }): Promise<void>;
    setCardLabels(input: { cardId: string; labelIds: string[] }): Promise<void>;
    exportBoard(input: { boardId: string }): Promise<KanbanBoardExport>;
    importBoard(input: { payload: KanbanBoardExport }): Promise<KanbanBoard>;
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
  "tools.encodeJwt",
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
  "kanban.listBoards",
  "kanban.createBoard",
  "kanban.renameBoard",
  "kanban.deleteBoard",
  "kanban.listColumns",
  "kanban.createColumn",
  "kanban.updateColumn",
  "kanban.reorderColumn",
  "kanban.archiveColumn",
  "kanban.restoreColumn",
  "kanban.listCards",
  "kanban.createCard",
  "kanban.updateCard",
  "kanban.deleteCard",
  "kanban.archiveCard",
  "kanban.restoreCard",
  "kanban.reorderCard",
  "kanban.listLabels",
  "kanban.createLabel",
  "kanban.deleteLabel",
  "kanban.setCardLabels",
  "kanban.exportBoard",
  "kanban.importBoard",
  "log.write",
  "log.list",
  "log.openDirectory"
] as const;

export type IpcContractHandlerName = (typeof ipcContractHandlers)[number];
