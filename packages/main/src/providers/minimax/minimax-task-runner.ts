import type { AiTaskEvent, AiTaskRequest, AiToolId, GeneratedArtifact } from "@codetool/shared";
import { EventEmitter } from "node:events";
import { randomUUID } from "node:crypto";
import { AssetStore } from "../../storage/asset-store";
import { HistoryRepository } from "../../db/repositories/history-repository";
import { AppLogger } from "../../logger/app-logger";
import { MiniMaxClient, buildMiniMaxRequest } from "./minimax-client";

export class MiniMaxTaskRunner {
  private readonly emitter = new EventEmitter();
  private readonly activeTasks = new Map<string, AbortController>();

  constructor(
    private readonly client: MiniMaxClient,
    private readonly history: HistoryRepository,
    private readonly assets: AssetStore,
    private readonly logger: AppLogger
  ) { }

  onTaskEvent(callback: (event: AiTaskEvent) => void): () => void {
    this.emitter.on("event", callback);
    return () => this.emitter.off("event", callback);
  }

  createTask(input: AiTaskRequest): { taskId: string } {
    const taskId = randomUUID();
    const referenceId = `MM-${taskId.slice(0, 8).toUpperCase()}`;
    const controller = new AbortController();
    this.activeTasks.set(taskId, controller);
    queueMicrotask(() => {
      void this.runTask(taskId, referenceId, input, controller);
    });
    return { taskId };
  }

  cancelTask(taskId: string): boolean {
    const controller = this.activeTasks.get(taskId);
    if (!controller) return false;
    controller.abort();
    this.activeTasks.delete(taskId);
    this.emit({ type: "cancelled", taskId });
    return true;
  }

  private async runTask(
    taskId: string,
    referenceId: string,
    input: AiTaskRequest,
    controller: AbortController
  ): Promise<void> {
    const startedAt = Date.now();
    this.emit({ type: "started", taskId, referenceId, toolId: input.toolId as AiToolId });
    this.logger.write({
      level: "info",
      message: "MiniMax task started.",
      source: "provider",
      referenceId,
      toolId: input.toolId,
      metadata: diagnosticMetadata(input, { taskId, stage: "started" })
    });
    try {
      this.emit({ type: "progress", taskId, stage: "provider", message: "Preparing MiniMax request" });
      buildMiniMaxRequest(input);
      await this.client.assertConfigured();
      assertNotCancelled(controller);

      const artifact = await this.generateArtifact(input, taskId, controller);
      assertNotCancelled(controller);
      if (artifact.text) {
        for (const chunk of chunkText(artifact.text, 24)) {
          assertNotCancelled(controller);
          this.emit({ type: "delta", taskId, text: chunk });
          await delay(16);
        }
      }

      this.emit({ type: "artifact", taskId, artifact });
      const history = this.history.create({
        toolId: input.toolId,
        title: titleForRequest(input),
        summary: summaryForRequest(input),
        payload: { request: input, artifact, referenceId },
        referenceId,
        assetIds: artifact.asset ? [artifact.asset.id] : []
      });
      const durationMs = Date.now() - startedAt;
      this.logger.write({
        level: "info",
        message: "MiniMax task completed.",
        source: "provider",
        referenceId,
        toolId: input.toolId,
        metadata: diagnosticMetadata(input, {
          taskId,
          stage: "completed",
          historyId: history.id,
          durationMs,
          artifactKind: artifact.kind,
          hasAsset: Boolean(artifact.asset)
        })
      });
      this.emit({ type: "completed", taskId, historyId: history.id, durationMs });
    } catch (error) {
      if (controller.signal.aborted) {
        this.logger.write({
          level: "info",
          message: "MiniMax task cancelled.",
          source: "provider",
          referenceId,
          toolId: input.toolId,
          metadata: diagnosticMetadata(input, {
            taskId,
            stage: "cancelled",
            durationMs: Date.now() - startedAt
          })
        });
        this.emit({ type: "cancelled", taskId });
        return;
      }
      const message = error instanceof Error ? error.message : "MiniMax task failed.";
      this.logger.write({
        level: "error",
        message,
        source: "provider",
        referenceId,
        toolId: input.toolId,
        metadata: diagnosticMetadata(input, {
          taskId,
          stage: "failed",
          durationMs: Date.now() - startedAt
        })
      });
      this.emit({ type: "failed", taskId, referenceId, message });
    } finally {
      this.activeTasks.delete(taskId);
    }
  }

  private async generateArtifact(input: AiTaskRequest, taskId: string, controller: AbortController): Promise<GeneratedArtifact> {
    this.emit({ type: "progress", taskId, stage: "request", message: "Calling MiniMax" });
    const result = await this.client.run(input, controller.signal);
    if (result.text) {
      return {
        id: randomUUID(),
        kind: "text",
        mimeType: "text/plain",
        text: result.text
      };
    }
    if (!result.artifact) {
      throw new Error("MiniMax completed without text or media output.");
    }
    const asset = this.assets.writeAsset(result.artifact);
    return {
      id: randomUUID(),
      kind: result.artifact.kind,
      mimeType: result.artifact.mimeType,
      asset
    };
  }

  private emit(event: AiTaskEvent): void {
    this.emitter.emit("event", event);
  }
}

function assertNotCancelled(controller: AbortController): void {
  if (controller.signal.aborted) {
    throw new Error("Task cancelled.");
  }
}

function chunkText(text: string, length: number): string[] {
  const chunks: string[] = [];
  for (let index = 0; index < text.length; index += length) {
    chunks.push(text.slice(index, index + length));
  }
  return chunks;
}

function delay(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function titleForRequest(input: AiTaskRequest): string {
  switch (input.toolId) {
    case "aiChat":
    case "aiImage":
    case "aiMusic":
      return input.prompt.slice(0, 64) || input.toolId;
    case "aiSpeech":
      return input.text.slice(0, 64) || "Speech generation";
  }
}

function summaryForRequest(input: AiTaskRequest): string {
  switch (input.toolId) {
    case "aiChat":
      return "MiniMax chat stream";
    case "aiSpeech":
      return `MiniMax speech · ${input.voiceId || "default voice"}`;
    case "aiImage":
      return `MiniMax image · ${input.aspectRatio || "1:1"} · ${input.count || 1} output`;
    case "aiMusic":
      return `MiniMax music · ${input.style || "default style"}`;
  }
}

function diagnosticMetadata(input: AiTaskRequest, extra: Record<string, unknown>): Record<string, unknown> {
  return {
    category: diagnosticCategory(input.toolId),
    ...extra
  };
}

function diagnosticCategory(toolId: AiToolId): string {
  switch (toolId) {
    case "aiChat":
      return "aichat";
    case "aiSpeech":
      return "aispeech";
    case "aiImage":
      return "aiimage";
    case "aiMusic":
      return "aimusic";
  }
}
