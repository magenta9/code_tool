import type { AiTaskRequest } from "@codetool/shared";
import type { MiniMaxTaskRunner } from "../providers/minimax/minimax-task-runner";

export class AiHandlers {
  constructor(private readonly tasks: MiniMaxTaskRunner) {}

  createTask(input: AiTaskRequest) {
    return this.tasks.createTask(input);
  }

  cancelTask(input: { taskId: string }) {
    return { cancelled: this.tasks.cancelTask(input.taskId) };
  }
}
