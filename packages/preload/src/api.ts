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
  log: {
    write: (input) => ipcRenderer.invoke(ipcChannels.log.write, input),
    list: (input) => ipcRenderer.invoke(ipcChannels.log.list, input),
    openDirectory: () => ipcRenderer.invoke(ipcChannels.log.openDirectory)
  }
};
