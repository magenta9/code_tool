import type { IpcContract } from "@codetool/shared";

export function getApi(): IpcContract {
  if (!window.api) {
    throw new Error("CodeTool preload API is unavailable.");
  }
  return window.api;
}
