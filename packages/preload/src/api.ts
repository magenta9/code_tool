import { ipcRenderer } from "electron";
import { ipcChannels, type IpcContract, type AiTaskEvent } from "@codetool/shared";

export const api: IpcContract = {
  system: {
    getStatus: () => ipcRenderer.invoke(ipcChannels.system.getStatus)
  },
  tools: {
    runJsonTool: (input) => ipcRenderer.invoke(ipcChannels.tools.runJsonTool, input),
    runJsonDiff: (input) => ipcRenderer.invoke(ipcChannels.tools.runJsonDiff, input),
    convertTimestamp: (input) => ipcRenderer.invoke(ipcChannels.tools.convertTimestamp, input),
    decodeJwt: (input) => ipcRenderer.invoke(ipcChannels.tools.decodeJwt, input),
    encodeJwt: (input) => ipcRenderer.invoke(ipcChannels.tools.encodeJwt, input),
    analyzeWordCloud: (input) => ipcRenderer.invoke(ipcChannels.tools.analyzeWordCloud, input),
    inspectImageBase64: (input) => ipcRenderer.invoke(ipcChannels.tools.inspectImageBase64, input),
    saveImageBase64: (input) => ipcRenderer.invoke(ipcChannels.tools.saveImageBase64, input)
  },
  history: {
    list: (input) => ipcRenderer.invoke(ipcChannels.history.list, input),
    load: (input) => ipcRenderer.invoke(ipcChannels.history.load, input),
    create: (input) => ipcRenderer.invoke(ipcChannels.history.create, input),
    delete: (input) => ipcRenderer.invoke(ipcChannels.history.delete, input)
  },
  settings: {
    get: () => ipcRenderer.invoke(ipcChannels.settings.get),
    save: (input) => ipcRenderer.invoke(ipcChannels.settings.save, input)
  },
  secrets: {
    getMiniMaxStatus: () => ipcRenderer.invoke(ipcChannels.secrets.getMiniMaxStatus),
    saveMiniMaxKey: (input) => ipcRenderer.invoke(ipcChannels.secrets.saveMiniMaxKey, input),
    clearMiniMaxKey: () => ipcRenderer.invoke(ipcChannels.secrets.clearMiniMaxKey)
  },
  ai: {
    createTask: (input) => ipcRenderer.invoke(ipcChannels.ai.createTask, input),
    cancelTask: (input) => ipcRenderer.invoke(ipcChannels.ai.cancelTask, input),
    onTaskEvent: (callback) => {
      const listener = (_event: Electron.IpcRendererEvent, payload: AiTaskEvent) => callback(payload);
      ipcRenderer.on(ipcChannels.ai.taskEvent, listener);
      return () => ipcRenderer.off(ipcChannels.ai.taskEvent, listener);
    }
  },
  kanban: {
    listBoards: () => ipcRenderer.invoke(ipcChannels.kanban.listBoards),
    createBoard: (input) => ipcRenderer.invoke(ipcChannels.kanban.createBoard, input),
    renameBoard: (input) => ipcRenderer.invoke(ipcChannels.kanban.renameBoard, input),
    deleteBoard: (input) => ipcRenderer.invoke(ipcChannels.kanban.deleteBoard, input),
    listColumns: (input) => ipcRenderer.invoke(ipcChannels.kanban.listColumns, input),
    createColumn: (input) => ipcRenderer.invoke(ipcChannels.kanban.createColumn, input),
    updateColumn: (input) => ipcRenderer.invoke(ipcChannels.kanban.updateColumn, input),
    reorderColumn: (input) => ipcRenderer.invoke(ipcChannels.kanban.reorderColumn, input),
    archiveColumn: (input) => ipcRenderer.invoke(ipcChannels.kanban.archiveColumn, input),
    restoreColumn: (input) => ipcRenderer.invoke(ipcChannels.kanban.restoreColumn, input),
    listCards: (input) => ipcRenderer.invoke(ipcChannels.kanban.listCards, input),
    createCard: (input) => ipcRenderer.invoke(ipcChannels.kanban.createCard, input),
    updateCard: (input) => ipcRenderer.invoke(ipcChannels.kanban.updateCard, input),
    deleteCard: (input) => ipcRenderer.invoke(ipcChannels.kanban.deleteCard, input),
    archiveCard: (input) => ipcRenderer.invoke(ipcChannels.kanban.archiveCard, input),
    restoreCard: (input) => ipcRenderer.invoke(ipcChannels.kanban.restoreCard, input),
    reorderCard: (input) => ipcRenderer.invoke(ipcChannels.kanban.reorderCard, input),
    listLabels: (input) => ipcRenderer.invoke(ipcChannels.kanban.listLabels, input),
    createLabel: (input) => ipcRenderer.invoke(ipcChannels.kanban.createLabel, input),
    deleteLabel: (input) => ipcRenderer.invoke(ipcChannels.kanban.deleteLabel, input),
    setCardLabels: (input) => ipcRenderer.invoke(ipcChannels.kanban.setCardLabels, input),
    exportBoard: (input) => ipcRenderer.invoke(ipcChannels.kanban.exportBoard, input),
    importBoard: (input) => ipcRenderer.invoke(ipcChannels.kanban.importBoard, input)
  },
  log: {
    write: (input) => ipcRenderer.invoke(ipcChannels.log.write, input),
    list: (input) => ipcRenderer.invoke(ipcChannels.log.list, input),
    openDirectory: () => ipcRenderer.invoke(ipcChannels.log.openDirectory)
  }
};
