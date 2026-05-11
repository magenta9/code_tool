import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import { beforeEach, describe, expect, it, vi } from "vitest";
import { toolCatalog, type KanbanBoard, type KanbanCard, type KanbanColumn } from "@codetool/shared";
import { App } from "./App";

describe("App smoke", () => {
  beforeEach(() => {
    const api = getMockApi();
    vi.clearAllMocks();
    window.location.hash = "#/";
    vi.mocked(api.kanban.listBoards).mockResolvedValue([]);
    vi.mocked(api.kanban.listColumns).mockResolvedValue([]);
    vi.mocked(api.kanban.listCards).mockResolvedValue([]);
    vi.mocked(api.kanban.listLabels).mockResolvedValue([]);
    vi.mocked(api.secrets.getMiniMaxStatus).mockResolvedValue({ provider: "minimax", configured: false });
    vi.stubGlobal("confirm", vi.fn(() => true));
  });

  it("renders the shell and all catalog tools in navigation", () => {
    render(<App />);
    expect(screen.getAllByText("CodeTool").length).toBeGreaterThan(0);
    expect(screen.queryByText("local-first")).not.toBeInTheDocument();
    expect(screen.queryByText("macOS")).not.toBeInTheDocument();
    for (const tool of toolCatalog) {
      expect(screen.getAllByText(tool.title).length).toBeGreaterThan(0);
    }
  });

  it("renders the word cloud preview shell instead of the old token list", () => {
    window.location.hash = "#/tools/word-cloud";
    render(<App />);
    expect(screen.getByText("Preview")).toBeInTheDocument();
    expect(screen.getByRole("button", { name: "Generate cloud" })).toBeInTheDocument();
    expect(screen.queryByText("Tokens")).not.toBeInTheDocument();
  });

  it("renders the Pi agent workspace with the prompt composer", () => {
    window.location.hash = "#/tools/pi-agent";
    render(<App />);
    expect(screen.getByRole("heading", { name: "Pi Agent" })).toBeInTheDocument();
    expect(screen.getByRole("button", { name: "Run prompt" })).toBeInTheDocument();
    expect(screen.getByPlaceholderText("/Users/you/code/project")).toBeInTheDocument();
  });

  it("renders usable Kanban task controls", async () => {
    const api = getMockApi();
    const board = createBoardFixture();
    const column = createColumnFixture(board.id);
    const card = createCardFixture(board.id, column.id);

    vi.mocked(api.kanban.listBoards).mockResolvedValue([board]);
    vi.mocked(api.kanban.listColumns).mockResolvedValue([column]);
    vi.mocked(api.kanban.listCards).mockResolvedValue([card]);
    vi.mocked(api.kanban.createCard).mockResolvedValue({ ...card, id: "card-2", title: "Draft task" });

    window.location.hash = "#/tools/kanban";
    render(<App />);

    expect(await screen.findByText("Fix task")).toBeInTheDocument();
    fireEvent.click(screen.getByRole("button", { name: "Add task to Todo" }));
    fireEvent.change(screen.getByPlaceholderText("Task title"), { target: { value: "Draft task" } });
    fireEvent.click(screen.getByRole("button", { name: "Add task to Todo" }));

    await waitFor(() => {
      expect(api.kanban.createCard).toHaveBeenCalledWith({ boardId: board.id, columnId: column.id, title: "Draft task" });
    });
    expect(screen.getByRole("button", { name: "Edit Fix task" })).toBeInTheDocument();
    expect(screen.getByRole("button", { name: "Archive Fix task" })).toBeInTheDocument();
    expect(screen.getByRole("button", { name: "Delete Fix task" })).toBeInTheDocument();
  });

  it("opens in-app Kanban board creation dialogs", async () => {
    window.location.hash = "#/tools/kanban";
    render(<App />);

    expect(await screen.findByRole("button", { name: "Create first board" })).toBeInTheDocument();
    fireEvent.click(screen.getByRole("button", { name: "New board" }));
    expect(screen.getByRole("dialog", { name: "New board" })).toBeInTheDocument();

    fireEvent.click(screen.getByRole("button", { name: "Close dialog" }));
    fireEvent.click(screen.getByRole("button", { name: "Create first board" }));
    expect(screen.getByRole("dialog", { name: "New board" })).toBeInTheDocument();
  });

  it("places Kanban import and export on settings", async () => {
    const api = getMockApi();
    const board = createBoardFixture();
    vi.mocked(api.kanban.listBoards).mockResolvedValue([board]);

    window.location.hash = "#/settings";
    render(<App />);

    expect(await screen.findByText("Kanban data")).toBeInTheDocument();
    expect(screen.getByRole("button", { name: "Export selected board" })).toBeInTheDocument();
    expect(screen.getByRole("button", { name: "Import board" })).toBeInTheDocument();
  });
});

function getMockApi(): NonNullable<typeof window.api> {
  if (!window.api) {
    throw new Error("window.api test mock is not installed");
  }
  return window.api;
}

function createBoardFixture(): KanbanBoard {
  return {
    id: "board-1",
    name: "Launch",
    createdAt: 1,
    updatedAt: 2
  };
}

function createColumnFixture(boardId: string): KanbanColumn {
  return {
    id: "column-1",
    boardId,
    name: "Todo",
    color: "#4f6f5f",
    sortOrder: 1000,
    createdAt: 1,
    updatedAt: 2
  };
}

function createCardFixture(boardId: string, columnId: string): KanbanCard {
  return {
    id: "card-1",
    boardId,
    columnId,
    title: "Fix task",
    priority: "medium",
    sortOrder: 1000,
    createdAt: 1,
    updatedAt: 2,
    labelIds: []
  };
}
