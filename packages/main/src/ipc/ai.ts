import type { AiTaskRequest } from "@codetool/shared";
import type { MiniMaxTaskRunner } from "../providers/minimax/minimax-task-runner";
import type { PiTaskRunner } from "../providers/pi/pi-task-runner";

export class AiHandlers {
  constructor(
    private readonly minimaxTasks: MiniMaxTaskRunner,
    private readonly piTasks: PiTaskRunner
  ) { }

  createTask(input: AiTaskRequest) {
    if (input.provider === "pi") {
      return this.piTasks.createTask(input);
    }
    return this.minimaxTasks.createTask(input);
  }

  async cancelTask(input: { taskId: string }) {
    const minimaxCancelled = this.minimaxTasks.cancelTask(input.taskId);
    if (minimaxCancelled) {
      return { cancelled: true };
    }

    return { cancelled: await this.piTasks.cancelTask(input.taskId) };
  }
}
