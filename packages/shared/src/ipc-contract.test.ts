import { describe, expect, it } from "vitest";
import { ipcContractHandlers } from "./ipc-contract";

describe("ipc contract", () => {
  it("declares every first-version handler once", () => {
    expect(ipcContractHandlers).toHaveLength(55);
    expect(new Set(ipcContractHandlers).size).toBe(ipcContractHandlers.length);
    expect(ipcContractHandlers).toContain("markdown.openFile");
    expect(ipcContractHandlers).toContain("markdown.exportPdf");
    expect(ipcContractHandlers).toContain("ai.createTask");
    expect(ipcContractHandlers).toContain("secrets.saveMiniMaxKey");
  });
});
