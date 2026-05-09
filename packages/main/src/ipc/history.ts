import type { CreateHistoryInput, ToolId } from "@codetool/shared";
import type { HistoryRepository } from "../db/repositories/history-repository";

export class HistoryHandlers {
  constructor(private readonly history: HistoryRepository) {}

  list(input?: { toolId?: ToolId; limit?: number }) {
    return this.history.list(input);
  }

  load(input: { id: string }) {
    return this.history.load(input.id);
  }

  create(input: CreateHistoryInput) {
    return this.history.create(input);
  }

  delete(input: { id: string }) {
    return { deleted: this.history.delete(input.id) };
  }
}
