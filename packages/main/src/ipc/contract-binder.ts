import type { IpcMain } from "electron";
import { ipcChannels } from "@codetool/shared";

export type IpcHandler<TResult = unknown> = (input: any) => Promise<TResult> | TResult;

export function bindInvoke<TResult>(
  ipcMain: IpcMain,
  channel: string,
  handler: IpcHandler<TResult>
): void {
  ipcMain.handle(channel, async (_event, input: unknown) => handler(input));
}

export function allDeclaredInvokeChannels(): string[] {
  return [
    ipcChannels.system.getStatus,
    ...Object.values(ipcChannels.tools),
    ...Object.values(ipcChannels.markdown),
    ...Object.values(ipcChannels.history),
    ...Object.values(ipcChannels.settings),
    ...Object.values(ipcChannels.secrets),
    ipcChannels.ai.createTask,
    ipcChannels.ai.cancelTask,
    ...Object.values(ipcChannels.kanban),
    ...Object.values(ipcChannels.log)
  ];
}
