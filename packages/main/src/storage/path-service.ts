import { app } from "electron";
import { join } from "node:path";

export interface CodeToolPaths {
  root: string;
  databasePath: string;
  assetRoot: string;
  logRoot: string;
}

export function resolveCodeToolPaths(): CodeToolPaths {
  const root = join(app.getPath("userData"), "electron");
  return {
    root,
    databasePath: join(root, "codetool.sqlite"),
    assetRoot: join(root, "assets"),
    logRoot: join(root, "logs")
  };
}
