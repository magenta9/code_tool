import type { LogInput } from "@codetool/shared";
import { shell } from "electron";
import type { AppLogger } from "../logger/app-logger";

export class DiagnosticsHandlers {
  constructor(
    private readonly logger: AppLogger,
    private readonly logRoot: string
  ) {}

  write(input: LogInput) {
    return this.logger.write({ ...input, source: "renderer" });
  }

  list(input?: { referenceId?: string; limit?: number }) {
    return this.logger.list(input);
  }

  async openDirectory() {
    await shell.openPath(this.logRoot);
    return { opened: true, path: this.logRoot };
  }
}
