import Database from "better-sqlite3";
import { describe, expect, it } from "vitest";
import { migrate } from "../schema";
import { KanbanRepository, orderBetween } from "./kanban-repository";

function createRepository(): KanbanRepository {
    const database = new Database(":memory:");
    migrate(database);
    return new KanbanRepository(database);
}

describe("KanbanRepository", () => {
    it("creates a board with the default columns", () => {
        const repository = createRepository();
        const board = repository.createBoard({ name: "Launch" });

        expect(repository.listBoards()).toHaveLength(1);
        expect(repository.listColumns({ boardId: board.id }).map((column) => column.name)).toEqual([
            "Backlog",
            "Todo",
            "In Progress",
            "Done"
        ]);
    });

    it("moves cards across columns with fractional ordering", () => {
        const repository = createRepository();
        const board = repository.createBoard({ name: "Launch" });
        const [backlog, todo] = repository.listColumns({ boardId: board.id });
        const first = repository.createCard({ boardId: board.id, columnId: backlog!.id, title: "First" });
        repository.createCard({ boardId: board.id, columnId: todo!.id, title: "Second" });

        const moved = repository.reorderCard({ id: first.id, toColumnId: todo!.id });

        expect(moved.columnId).toBe(todo!.id);
        expect(repository.listCards({ boardId: board.id }).filter((card) => card.columnId === todo!.id)).toHaveLength(2);
        expect(orderBetween(1000, 2000)).toBe(1500);
    });

    it("blocks archiving non-empty columns", () => {
        const repository = createRepository();
        const board = repository.createBoard({ name: "Launch" });
        const [backlog] = repository.listColumns({ boardId: board.id });
        repository.createCard({ boardId: board.id, columnId: backlog!.id, title: "Keep me visible" });

        expect(() => repository.archiveColumn({ id: backlog!.id })).toThrow(/Move or archive active cards/);
    });

    it("archives and restores cards", () => {
        const repository = createRepository();
        const board = repository.createBoard({ name: "Launch" });
        const [backlog] = repository.listColumns({ boardId: board.id });
        const card = repository.createCard({ boardId: board.id, columnId: backlog!.id, title: "Ship" });

        repository.archiveCard({ id: card.id });
        expect(repository.listCards({ boardId: board.id })).toHaveLength(0);
        expect(repository.listCards({ boardId: board.id, includeArchived: true })).toHaveLength(1);

        repository.restoreCard({ id: card.id });
        expect(repository.listCards({ boardId: board.id })).toHaveLength(1);
    });

    it("round-trips exported boards with labels", () => {
        const repository = createRepository();
        const board = repository.createBoard({ name: "Launch" });
        const [backlog] = repository.listColumns({ boardId: board.id });
        const card = repository.createCard({ boardId: board.id, columnId: backlog!.id, title: "Design" });
        const label = repository.createLabel({ boardId: board.id, name: "UI", color: "#2563eb" });
        repository.setCardLabels({ cardId: card.id, labelIds: [label.id] });

        const imported = repository.importBoard({ payload: repository.exportBoard({ boardId: board.id }) });

        expect(imported.name).toBe("Launch Copy");
        expect(repository.listColumns({ boardId: imported.id, includeArchived: true })).toHaveLength(4);
        expect(repository.listCards({ boardId: imported.id, includeArchived: true })[0]?.labelIds).toHaveLength(1);
        expect(repository.listLabels({ boardId: imported.id })[0]?.name).toBe("UI");
    });
});
