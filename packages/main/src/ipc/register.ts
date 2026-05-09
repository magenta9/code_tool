import { app, BrowserWindow, ipcMain } from "electron";
import { ipcChannels } from "@codetool/shared";
import type { AssetStore } from "../storage/asset-store";
import type { HistoryRepository } from "../db/repositories/history-repository";
import type { KanbanRepository } from "../db/repositories/kanban-repository";
import type { SettingsRepository } from "../db/repositories/settings-repository";
import type { AppLogger } from "../logger/app-logger";
import { MiniMaxSecretStore } from "../providers/minimax/minimax-settings";
import { MiniMaxClient } from "../providers/minimax/minimax-client";
import { MiniMaxTaskRunner } from "../providers/minimax/minimax-task-runner";
import { PiTaskRunner } from "../providers/pi/pi-task-runner";
import { ToolHandlers } from "./tools";
import { HistoryHandlers } from "./history";
import { SettingsHandlers } from "./settings";
import { AiHandlers } from "./ai";
import { DiagnosticsHandlers } from "./diagnostics";
import { KanbanHandlers } from "./kanban";
import { bindInvoke } from "./contract-binder";

export interface IpcServiceContext {
  history: HistoryRepository;
  kanban: KanbanRepository;
  settings: SettingsRepository;
  assets: AssetStore;
  logger: AppLogger;
  logRoot: string;
}

export function registerIpc(context: IpcServiceContext): void {
  const tools = new ToolHandlers(context.history, context.assets);
  const history = new HistoryHandlers(context.history);
  const kanban = new KanbanHandlers(context.kanban);
  const settings = new SettingsHandlers(context.settings);
  const diagnostics = new DiagnosticsHandlers(context.logger, context.logRoot);
  const secrets = new MiniMaxSecretStore();
  const minimaxClient = new MiniMaxClient(() => secrets.getApiKey());
  const taskRunner = new MiniMaxTaskRunner(minimaxClient, context.history, context.assets, context.logger);
  const piTaskRunner = new PiTaskRunner(context.history, context.logger);
  const ai = new AiHandlers(taskRunner, piTaskRunner);

  taskRunner.onTaskEvent((event) => {
    for (const window of BrowserWindow.getAllWindows()) {
      window.webContents.send(ipcChannels.ai.taskEvent, event);
    }
  });

  piTaskRunner.onTaskEvent((event) => {
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

  bindInvoke(ipcMain, ipcChannels.kanban.listBoards, () => kanban.listBoards());
  bindInvoke(ipcMain, ipcChannels.kanban.createBoard, (input) => kanban.createBoard(input));
  bindInvoke(ipcMain, ipcChannels.kanban.renameBoard, (input) => kanban.renameBoard(input));
  bindInvoke(ipcMain, ipcChannels.kanban.deleteBoard, (input) => kanban.deleteBoard(input));
  bindInvoke(ipcMain, ipcChannels.kanban.listColumns, (input) => kanban.listColumns(input));
  bindInvoke(ipcMain, ipcChannels.kanban.createColumn, (input) => kanban.createColumn(input));
  bindInvoke(ipcMain, ipcChannels.kanban.updateColumn, (input) => kanban.updateColumn(input));
  bindInvoke(ipcMain, ipcChannels.kanban.reorderColumn, (input) => kanban.reorderColumn(input));
  bindInvoke(ipcMain, ipcChannels.kanban.archiveColumn, (input) => kanban.archiveColumn(input));
  bindInvoke(ipcMain, ipcChannels.kanban.restoreColumn, (input) => kanban.restoreColumn(input));
  bindInvoke(ipcMain, ipcChannels.kanban.listCards, (input) => kanban.listCards(input));
  bindInvoke(ipcMain, ipcChannels.kanban.createCard, (input) => kanban.createCard(input));
  bindInvoke(ipcMain, ipcChannels.kanban.updateCard, (input) => kanban.updateCard(input));
  bindInvoke(ipcMain, ipcChannels.kanban.deleteCard, (input) => kanban.deleteCard(input));
  bindInvoke(ipcMain, ipcChannels.kanban.archiveCard, (input) => kanban.archiveCard(input));
  bindInvoke(ipcMain, ipcChannels.kanban.restoreCard, (input) => kanban.restoreCard(input));
  bindInvoke(ipcMain, ipcChannels.kanban.reorderCard, (input) => kanban.reorderCard(input));
  bindInvoke(ipcMain, ipcChannels.kanban.listLabels, (input) => kanban.listLabels(input));
  bindInvoke(ipcMain, ipcChannels.kanban.createLabel, (input) => kanban.createLabel(input));
  bindInvoke(ipcMain, ipcChannels.kanban.deleteLabel, (input) => kanban.deleteLabel(input));
  bindInvoke(ipcMain, ipcChannels.kanban.setCardLabels, (input) => kanban.setCardLabels(input));
  bindInvoke(ipcMain, ipcChannels.kanban.exportBoard, (input) => kanban.exportBoard(input));
  bindInvoke(ipcMain, ipcChannels.kanban.importBoard, (input) => kanban.importBoard(input));

  bindInvoke(ipcMain, ipcChannels.log.write, (input) => diagnostics.write(input));
  bindInvoke(ipcMain, ipcChannels.log.list, (input) => diagnostics.list(input));
  bindInvoke(ipcMain, ipcChannels.log.openDirectory, () => diagnostics.openDirectory());
}
