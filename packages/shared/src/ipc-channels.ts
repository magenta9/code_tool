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
  log: {
    write: "log:write",
    list: "log:list",
    openDirectory: "log:open-directory"
  }
} as const;

export type IpcChannel = typeof ipcChannels[keyof typeof ipcChannels][keyof typeof ipcChannels[keyof typeof ipcChannels]];
