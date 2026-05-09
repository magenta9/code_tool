import { describe, expect, it } from "vitest";
import config from "./vite.config";

describe("renderer Vite config", () => {
  it("uses Electron-safe asset paths and a fixed dev port", () => {
    expect(config).toMatchObject({
      base: "./",
      server: {
        host: "127.0.0.1",
        port: 5173,
        strictPort: true
      }
    });
  });
});