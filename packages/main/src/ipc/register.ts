import { app, BrowserWindow, ipcMain } from "electron";
import { ipcChannels } from "@codetool/shared";
import type { AssetStore } from "../storage/asset-store";
import type { HistoryRepository } from "../db/repositories/history-repository";
import type { SettingsRepository } from "../db/repositories/settings-repository";
import type { AppLogger } from "../logger/app-logger";
import { MiniMaxSecretStore } from "../providers/minimax/minimax-settings";
import { MiniMaxClient } from "../providers/minimax/minimax-client";
import { MiniMaxTaskRunner } from "../providers/minimax/minimax-task-runner";
import { ToolHandlers } from "./tools";
import { HistoryHandlers } from "./history";
import { SettingsHandlers } from "./settings";
import { AiHandlers } from "./ai";
import { DiagnosticsHandlers } from "./diagnostics";
import { bindInvoke } from "./contract-binder";

export interface IpcServiceContext {
  history: HistoryRepository;
  settings: SettingsRepository;
  assets: AssetStore;
  logger: AppLogger;
  logRoot: string;
}

export function registerIpc(context: IpcServiceContext): void {
  const tools = new ToolHandlers(context.history, context.assets);
  const history = new HistoryHandlers(context.history);
  const settings = new SettingsHandlers(context.settings);
  const diagnostics = new DiagnosticsHandlers(context.logger, context.logRoot);
  const secrets = new MiniMaxSecretStore();
  const minimaxClient = new MiniMaxClient(() => secrets.getApiKey());
  const taskRunner = new MiniMaxTaskRunner(minimaxClient, context.history, context.assets, context.logger);
  const ai = new AiHandlers(taskRunner);

  taskRunner.onTaskEvent((event) => {
    for (const window of BrowserWindow.getAllWindows()) {
      window.webContents.send(ipcChannels.ai.taskEvent, event);
    }
  });

  bindInvoke(ipcMain, ipcChannels.system.getStatus, () => ({
    appName: "CodeTool" as const,
    platform: process.platform,
    version: app.getVersion(),
    userDataPath: app.getPath("userData")
  }));

  bindInvoke(ipcMain, ipcChannels.tools.runJsonTool, (input) => tools.runJsonTool(input));
  bindInvoke(ipcMain, ipcChannels.tools.runJsonDiff, (input) => tools.runJsonDiff(input));
  bindInvoke(ipcMain, ipcChannels.tools.convertTimestamp, (input) => tools.convertTimestamp(input));
  bindInvoke(ipcMain, ipcChannels.tools.decodeJwt, (input) => tools.decodeJwt(input));
  bindInvoke(ipcMain, ipcChannels.tools.analyzeWordCloud, (input) => tools.analyzeWordCloud(input));
  bindInvoke(ipcMain, ipcChannels.tools.inspectImageBase64, (input) => tools.inspectImageBase64(input));
  bindInvoke(ipcMain, ipcChannels.tools.saveImageBase64, (input) => tools.saveImageBase64(input));

  bindInvoke(ipcMain, ipcChannels.history.list, (input) => history.list(input));
  bindInvoke(ipcMain, ipcChannels.history.load, (input) => history.load(input));
  bindInvoke(ipcMain, ipcChannels.history.create, (input) => history.create(input));
  bindInvoke(ipcMain, ipcChannels.history.delete, (input) => history.delete(input));

  bindInvoke(ipcMain, ipcChannels.settings.get, () => settings.get());
  bindInvoke(ipcMain, ipcChannels.settings.save, (input) => settings.save(input));

  bindInvoke(ipcMain, ipcChannels.secrets.getMiniMaxStatus, () => secrets.status());
  bindInvoke(ipcMain, ipcChannels.secrets.saveMiniMaxKey, (input) => secrets.save(input));
  bindInvoke(ipcMain, ipcChannels.secrets.clearMiniMaxKey, () => secrets.clear());

  bindInvoke(ipcMain, ipcChannels.ai.createTask, (input) => ai.createTask(input));
  bindInvoke(ipcMain, ipcChannels.ai.cancelTask, (input) => ai.cancelTask(input));

  bindInvoke(ipcMain, ipcChannels.log.write, (input) => diagnostics.write(input));
  bindInvoke(ipcMain, ipcChannels.log.list, (input) => diagnostics.list(input));
  bindInvoke(ipcMain, ipcChannels.log.openDirectory, () => diagnostics.openDirectory());
}
