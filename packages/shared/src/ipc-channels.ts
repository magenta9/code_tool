export const ipcChannels = {
  system: {
    getStatus: "system:get-status"
  },
  tools: {
    runJsonTool: "tools:run-json-tool",
    runJsonDiff: "tools:run-json-diff",
    convertTimestamp: "tools:convert-timestamp",
    decodeJwt: "tools:decode-jwt",
    analyzeWordCloud: "tools:analyze-word-cloud",
    inspectImageBase64: "tools:inspect-image-base64",
    saveImageBase64: "tools:save-image-base64"
  },
  history: {
    list: "history:list",
    load: "history:load",
    create: "history:create",
    delete: "history:delete"
  },
  settings: {
    get: "settings:get",
    save: "settings:save"
  },
  secrets: {
    getMiniMaxStatus: "secrets:get-minimax-status",
    saveMiniMaxKey: "secrets:save-minimax-key",
    clearMiniMaxKey: "secrets:clear-minimax-key"
  },
  ai: {
    createTask: "ai:create-task",
    cancelTask: "ai:cancel-task",
    taskEvent: "ai:task-event"
  },
  kanban: {
    listBoards: "kanban:list-boards",
    createBoard: "kanban:create-board",
    renameBoard: "kanban:rename-board",
    deleteBoard: "kanban:delete-board",
    listColumns: "kanban:list-columns",
    createColumn: "kanban:create-column",
    updateColumn: "kanban:update-column",
    reorderColumn: "kanban:reorder-column",
    archiveColumn: "kanban:archive-column",
    restoreColumn: "kanban:restore-column",
    listCards: "kanban:list-cards",
    createCard: "kanban:create-card",
    updateCard: "kanban:update-card",
    deleteCard: "kanban:delete-card",
    archiveCard: "kanban:archive-card",
    restoreCard: "kanban:restore-card",
    reorderCard: "kanban:reorder-card",
    listLabels: "kanban:list-labels",
    createLabel: "kanban:create-label",
    deleteLabel: "kanban:delete-label",
    setCardLabels: "kanban:set-card-labels",
    exportBoard: "kanban:export-board",
    importBoard: "kanban:import-board"
  },
  log: {
    write: "log:write",
    list: "log:list",
    openDirectory: "log:open-directory"
  }
} as const;

export type IpcChannel = typeof ipcChannels[keyof typeof ipcChannels][keyof typeof ipcChannels[keyof typeof ipcChannels]];
