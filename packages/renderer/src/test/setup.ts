import "@testing-library/jest-dom/vitest";
import { vi } from "vitest";
import type { IpcContract } from "@codetool/shared";

const noopUnsubscribe = () => { };

Object.defineProperty(window, "api", {
  configurable: true,
  value: {
    system: {
      getStatus: vi.fn()
    },
    tools: {
      runJsonTool: vi.fn(),
      runJsonDiff: vi.fn(),
      convertTimestamp: vi.fn(),
      decodeJwt: vi.fn(),
      encodeJwt: vi.fn(),
      analyzeWordCloud: vi.fn(),
      inspectImageBase64: vi.fn(),
      saveImageBase64: vi.fn()
    },
    history: {
      list: vi.fn(),
      load: vi.fn(),
      create: vi.fn(),
      delete: vi.fn()
    },
    settings: {
      get: vi.fn(),
      save: vi.fn()
    },
    secrets: {
      getMiniMaxStatus: vi.fn(async () => ({ provider: "minimax" as const, configured: false })),
      saveMiniMaxKey: vi.fn(),
      clearMiniMaxKey: vi.fn()
    },
    ai: {
      createTask: vi.fn(),
      cancelTask: vi.fn(),
      onTaskEvent: vi.fn(() => noopUnsubscribe)
    },
    kanban: {
      listBoards: vi.fn(async () => []),
      createBoard: vi.fn(),
      renameBoard: vi.fn(),
      deleteBoard: vi.fn(),
      listColumns: vi.fn(async () => []),
      createColumn: vi.fn(),
      updateColumn: vi.fn(),
      reorderColumn: vi.fn(),
      archiveColumn: vi.fn(),
      restoreColumn: vi.fn(),
      listCards: vi.fn(async () => []),
      createCard: vi.fn(),
      updateCard: vi.fn(),
      deleteCard: vi.fn(),
      archiveCard: vi.fn(),
      restoreCard: vi.fn(),
      reorderCard: vi.fn(),
      listLabels: vi.fn(async () => []),
      createLabel: vi.fn(),
      deleteLabel: vi.fn(),
      setCardLabels: vi.fn(),
      exportBoard: vi.fn(),
      importBoard: vi.fn()
    },
    log: {
      write: vi.fn(),
      list: vi.fn(async () => []),
      openDirectory: vi.fn()
    }
  } satisfies IpcContract
});
