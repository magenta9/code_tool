import type { AgentSession, AgentSessionEvent, CreateAgentSessionOptions } from "@earendil-works/pi-coding-agent";
import type { AiTaskEvent, AiTaskRequest, CreateAiTaskResult, PiToolPolicy, ThinkingLevel } from "@codetool/shared";
import { EventEmitter } from "node:events";
import { randomUUID } from "node:crypto";
import { existsSync, statSync } from "node:fs";
import { homedir } from "node:os";
import { resolve } from "node:path";
import { HistoryRepository } from "../../db/repositories/history-repository";
import { AppLogger } from "../../logger/app-logger";

type PiTaskRequest = Extract<AiTaskRequest, { provider: "pi" }>;
type PiSdkModule = typeof import("@earendil-works/pi-coding-agent");

interface PiSessionState {
    sessionId: string;
    workspaceRoot: string;
    providerName?: string;
    modelId?: string;
    thinkingLevel?: ThinkingLevel;
    toolPolicy: PiToolPolicy;
    session: AgentSession;
    activeTaskId: string | null;
}

interface ActivePiTask {
    taskId: string;
    sessionId: string;
    referenceId: string;
    cancelRequested: boolean;
}

let piSdkPromise: Promise<PiSdkModule> | null = null;

export class PiTaskRunner {
    private readonly emitter = new EventEmitter();
    private readonly sessions = new Map<string, PiSessionState>();
    private readonly tasks = new Map<string, ActivePiTask>();

    constructor(
        private readonly history: HistoryRepository,
        private readonly logger: AppLogger
    ) { }

    onTaskEvent(callback: (event: AiTaskEvent) => void): () => void {
        this.emitter.on("event", callback);
        return () => this.emitter.off("event", callback);
    }

    async createTask(input: PiTaskRequest): Promise<CreateAiTaskResult> {
        const normalizedInput: PiTaskRequest = {
            ...input,
            workspaceRoot: normalizeWorkspaceRoot(input.workspaceRoot)
        };

        assertWorkspaceRoot(normalizedInput.workspaceRoot);
        const sessionState = await this.resolveSession(normalizedInput);
        if (sessionState.activeTaskId) {
            throw new Error("Pi agent session is already running. Wait for the current task to finish or cancel it first.");
        }

        const taskId = randomUUID();
        const referenceId = `PI-${taskId.slice(0, 8).toUpperCase()}`;
        const task: ActivePiTask = {
            taskId,
            sessionId: sessionState.sessionId,
            referenceId,
            cancelRequested: false
        };

        this.tasks.set(taskId, task);
        sessionState.activeTaskId = taskId;

        queueMicrotask(() => {
            void this.runTask(task, sessionState, normalizedInput);
        });

        return {
            taskId,
            sessionId: sessionState.sessionId
        };
    }

    async cancelTask(taskId: string): Promise<boolean> {
        const task = this.tasks.get(taskId);
        if (!task) return false;

        task.cancelRequested = true;
        const sessionState = this.sessions.get(task.sessionId);
        if (!sessionState) return false;

        await sessionState.session.abort();
        return true;
    }

    private async resolveSession(input: PiTaskRequest): Promise<PiSessionState> {
        const existing = input.sessionId ? this.sessions.get(input.sessionId) : null;
        if (
            existing &&
            existing.workspaceRoot === input.workspaceRoot &&
            existing.providerName === input.providerName &&
            existing.modelId === input.modelId &&
            existing.thinkingLevel === input.thinkingLevel &&
            existing.toolPolicy === (input.toolPolicy ?? "readOnly")
        ) {
            return existing;
        }

        return this.createSession(input);
    }

    private async createSession(input: PiTaskRequest): Promise<PiSessionState> {
        const sdk = await loadPiSdk();
        const authStorage = sdk.AuthStorage.create();
        const modelRegistry = sdk.ModelRegistry.create(authStorage);
        const sessionManager = sdk.SessionManager.inMemory(input.workspaceRoot);
        const tools = toolsForPolicy(input.toolPolicy ?? "readOnly");

        const options: CreateAgentSessionOptions = {
            cwd: input.workspaceRoot,
            authStorage,
            modelRegistry,
            sessionManager,
            tools,
            thinkingLevel: input.thinkingLevel
        };

        if (input.providerName && input.modelId) {
            const model = modelRegistry.find(input.providerName, input.modelId);
            if (!model) {
                throw new Error(`Pi model not found: ${input.providerName}/${input.modelId}`);
            }
            options.model = model;
        }

        const { session } = await sdk.createAgentSession(options);
        const sessionId = randomUUID();
        const state: PiSessionState = {
            sessionId,
            workspaceRoot: input.workspaceRoot,
            providerName: input.providerName,
            modelId: input.modelId,
            thinkingLevel: input.thinkingLevel,
            toolPolicy: input.toolPolicy ?? "readOnly",
            session,
            activeTaskId: null
        };

        this.sessions.set(sessionId, state);
        return state;
    }

    private async runTask(task: ActivePiTask, sessionState: PiSessionState, input: PiTaskRequest): Promise<void> {
        const startedAt = Date.now();
        const unsubscribe = sessionState.session.subscribe((event) => {
            this.forwardEvent(task, sessionState, event);
        });

        this.logger.write({
            level: "info",
            message: "Pi agent task started.",
            source: "provider",
            referenceId: task.referenceId,
            toolId: input.toolId,
            metadata: {
                provider: input.provider,
                workspaceRoot: input.workspaceRoot,
                sessionId: sessionState.sessionId,
                providerName: input.providerName,
                modelId: input.modelId,
                thinkingLevel: input.thinkingLevel,
                toolPolicy: input.toolPolicy ?? "readOnly"
            }
        });

        try {
            await sessionState.session.prompt(input.prompt);

            if (task.cancelRequested) {
                this.emit({ type: "cancelled", taskId: task.taskId });
                return;
            }

            const record = this.history.create({
                toolId: "piAgent",
                title: input.prompt.slice(0, 72) || "Pi Agent",
                summary: `Pi agent · ${sessionState.workspaceRoot}`,
                payload: {
                    sessionId: sessionState.sessionId,
                    workspaceRoot: sessionState.workspaceRoot,
                    providerName: sessionState.providerName,
                    modelId: sessionState.modelId,
                    thinkingLevel: sessionState.thinkingLevel,
                    messageCount: sessionState.session.messages.length,
                    prompt: input.prompt
                },
                referenceId: task.referenceId
            });

            this.emit({
                type: "completed",
                taskId: task.taskId,
                historyId: record.id,
                durationMs: Date.now() - startedAt
            });
        } catch (error) {
            if (task.cancelRequested || isAbortError(error)) {
                this.emit({ type: "cancelled", taskId: task.taskId });
            } else {
                const message = error instanceof Error ? error.message : "Pi agent task failed.";
                this.logger.write({
                    level: "error",
                    message,
                    source: "provider",
                    referenceId: task.referenceId,
                    toolId: input.toolId,
                    metadata: {
                        workspaceRoot: input.workspaceRoot,
                        sessionId: sessionState.sessionId,
                        durationMs: Date.now() - startedAt
                    }
                });
                this.emit({
                    type: "failed",
                    taskId: task.taskId,
                    referenceId: task.referenceId,
                    message
                });
            }
        } finally {
            unsubscribe();
            sessionState.activeTaskId = null;
            this.tasks.delete(task.taskId);
        }
    }

    private forwardEvent(task: ActivePiTask, sessionState: PiSessionState, event: AgentSessionEvent): void {
        switch (event.type) {
            case "agent_start":
                this.emit({
                    type: "agent_start",
                    taskId: task.taskId,
                    sessionId: sessionState.sessionId,
                    provider: "pi",
                    workspaceRoot: sessionState.workspaceRoot
                });
                return;
            case "agent_end":
                this.emit({
                    type: "agent_end",
                    taskId: task.taskId,
                    sessionId: sessionState.sessionId,
                    provider: "pi",
                    messageCount: event.messages.length
                });
                return;
            case "message_start": {
                const messageId = messageIdFor(event.message);
                if (!messageId || !isUserOrAssistant(event.message)) return;
                this.emit({
                    type: "message_start",
                    taskId: task.taskId,
                    sessionId: sessionState.sessionId,
                    messageId,
                    role: event.message.role
                });
                return;
            }
            case "message_update": {
                const messageId = messageIdFor(event.message);
                if (!messageId || event.message.role !== "assistant") return;
                const update = event.assistantMessageEvent;
                if (update.type === "text_delta") {
                    this.emit({
                        type: "message_delta",
                        taskId: task.taskId,
                        sessionId: sessionState.sessionId,
                        messageId,
                        deltaType: "text",
                        text: update.delta
                    });
                    return;
                }
                if (update.type === "thinking_delta") {
                    this.emit({
                        type: "message_delta",
                        taskId: task.taskId,
                        sessionId: sessionState.sessionId,
                        messageId,
                        deltaType: "thinking",
                        text: update.delta
                    });
                    return;
                }
                if (update.type === "toolcall_start") {
                    const toolCall = getToolCallFromPartial(update.partial, update.contentIndex);
                    if (!toolCall) return;
                    this.emit({
                        type: "toolcall_start",
                        phase: "call",
                        taskId: task.taskId,
                        sessionId: sessionState.sessionId,
                        messageId,
                        toolCallId: toolCall.id,
                        toolName: toolCall.name,
                        args: toolCall.arguments ?? {}
                    });
                    return;
                }
                if (update.type === "toolcall_delta") {
                    const toolCall = getToolCallFromPartial(update.partial, update.contentIndex);
                    if (!toolCall) return;
                    this.emit({
                        type: "toolcall_delta",
                        phase: "call",
                        taskId: task.taskId,
                        sessionId: sessionState.sessionId,
                        toolCallId: toolCall.id,
                        toolName: toolCall.name,
                        partialText: update.delta,
                        partialResult: { arguments: toolCall.arguments ?? {} }
                    });
                    return;
                }
                if (update.type === "toolcall_end") {
                    this.emit({
                        type: "toolcall_end",
                        phase: "call",
                        taskId: task.taskId,
                        sessionId: sessionState.sessionId,
                        toolCallId: update.toolCall.id,
                        toolName: update.toolCall.name,
                        resultText: JSON.stringify(update.toolCall.arguments ?? {}, null, 2),
                        result: { arguments: update.toolCall.arguments ?? {} },
                        isError: false
                    });
                }
                return;
            }
            case "message_end": {
                const messageId = messageIdFor(event.message);
                if (!messageId || !isUserOrAssistant(event.message)) return;
                this.emit({
                    type: "message_end",
                    taskId: task.taskId,
                    sessionId: sessionState.sessionId,
                    messageId,
                    role: event.message.role,
                    stopReason: event.message.role === "assistant" ? event.message.stopReason : undefined
                });
                return;
            }
            case "tool_execution_start":
                this.emit({
                    type: "toolcall_start",
                    phase: "execution",
                    taskId: task.taskId,
                    sessionId: sessionState.sessionId,
                    messageId: `tool-${event.toolCallId}`,
                    toolCallId: event.toolCallId,
                    toolName: event.toolName,
                    args: toRecord(event.args)
                });
                return;
            case "tool_execution_update":
                this.emit({
                    type: "toolcall_delta",
                    phase: "execution",
                    taskId: task.taskId,
                    sessionId: sessionState.sessionId,
                    toolCallId: event.toolCallId,
                    toolName: event.toolName,
                    partialText: renderToolPayload(event.partialResult),
                    partialResult: toRecord(event.partialResult)
                });
                return;
            case "tool_execution_end":
                this.emit({
                    type: "toolcall_end",
                    phase: "execution",
                    taskId: task.taskId,
                    sessionId: sessionState.sessionId,
                    toolCallId: event.toolCallId,
                    toolName: event.toolName,
                    resultText: renderToolPayload(event.result),
                    result: toRecord(event.result),
                    isError: event.isError
                });
                return;
            case "queue_update":
                this.emit({
                    type: "queue_update",
                    taskId: task.taskId,
                    sessionId: sessionState.sessionId,
                    steering: [...event.steering],
                    followUp: [...event.followUp]
                });
                return;
            case "compaction_start":
                this.emit({
                    type: "compaction_start",
                    taskId: task.taskId,
                    sessionId: sessionState.sessionId,
                    reason: event.reason
                });
                return;
            case "compaction_end":
                this.emit({
                    type: "compaction_end",
                    taskId: task.taskId,
                    sessionId: sessionState.sessionId,
                    reason: event.reason,
                    summary: event.result?.summary,
                    errorMessage: event.errorMessage,
                    aborted: event.aborted,
                    willRetry: event.willRetry
                });
                return;
            case "auto_retry_start":
                this.emit({
                    type: "auto_retry_start",
                    taskId: task.taskId,
                    sessionId: sessionState.sessionId,
                    attempt: event.attempt,
                    maxAttempts: event.maxAttempts,
                    delayMs: event.delayMs,
                    errorMessage: event.errorMessage
                });
                return;
            case "auto_retry_end":
                this.emit({
                    type: "auto_retry_end",
                    taskId: task.taskId,
                    sessionId: sessionState.sessionId,
                    attempt: event.attempt,
                    success: event.success,
                    finalError: event.finalError
                });
                return;
        }
    }

    private emit(event: AiTaskEvent): void {
        this.emitter.emit("event", event);
    }
}

function toolsForPolicy(policy: PiToolPolicy): string[] {
    if (policy === "workspaceWrite") {
        return ["read", "grep", "find", "ls", "edit", "write", "bash"];
    }
    return ["read", "grep", "find", "ls"];
}

export function normalizeWorkspaceRoot(workspaceRoot: string): string {
    const trimmed = workspaceRoot.trim();
    if (!trimmed) return "";
    if (trimmed === "~") return homedir();
    if (trimmed.startsWith("~/")) {
        return resolve(homedir(), trimmed.slice(2));
    }
    return trimmed;
}

async function loadPiSdk(): Promise<PiSdkModule> {
    piSdkPromise ??= import("@earendil-works/pi-coding-agent");
    return piSdkPromise;
}

function assertWorkspaceRoot(workspaceRoot: string): void {
    if (!workspaceRoot.trim()) {
        throw new Error("Workspace root is required for Pi Agent.");
    }
    if (!existsSync(workspaceRoot) || !statSync(workspaceRoot).isDirectory()) {
        throw new Error(`Workspace root does not exist: ${workspaceRoot}`);
    }
}

function isAbortError(error: unknown): boolean {
    return error instanceof Error && /abort/i.test(error.message);
}

function isUserOrAssistant(message: unknown): message is { role: "user" | "assistant"; timestamp: number; stopReason?: string } {
    if (!message || typeof message !== "object") return false;
    const role = Reflect.get(message, "role");
    const timestamp = Reflect.get(message, "timestamp");
    return (role === "user" || role === "assistant") && typeof timestamp === "number";
}

function messageIdFor(message: unknown): string | null {
    if (!message || typeof message !== "object") return null;
    const role = Reflect.get(message, "role");
    const timestamp = Reflect.get(message, "timestamp");
    if (typeof role !== "string" || typeof timestamp !== "number") return null;
    return `${role}-${timestamp}`;
}

function getToolCallFromPartial(message: unknown, contentIndex: number): { id: string; name: string; arguments: Record<string, unknown> } | null {
    if (!message || typeof message !== "object") return null;
    const content = Reflect.get(message, "content");
    if (!Array.isArray(content)) return null;
    const block = content[contentIndex];
    if (!block || typeof block !== "object") return null;
    if (Reflect.get(block, "type") !== "toolCall") return null;

    const id = Reflect.get(block, "id");
    const name = Reflect.get(block, "name");
    const args = Reflect.get(block, "arguments");
    if (typeof id !== "string" || typeof name !== "string") return null;

    return {
        id,
        name,
        arguments: toRecord(args)
    };
}

function toRecord(value: unknown): Record<string, unknown> {
    if (!value || typeof value !== "object" || Array.isArray(value)) {
        return {};
    }
    return value as Record<string, unknown>;
}

function renderToolPayload(payload: unknown): string {
    if (!payload || typeof payload !== "object") {
        return JSON.stringify(payload ?? {}, null, 2);
    }

    const content = Reflect.get(payload, "content");
    if (Array.isArray(content)) {
        const text = content
            .map((item) => {
                if (!item || typeof item !== "object") return "";
                if (Reflect.get(item, "type") === "text") {
                    const value = Reflect.get(item, "text");
                    return typeof value === "string" ? value : "";
                }
                return JSON.stringify(item, null, 2);
            })
            .filter(Boolean)
            .join("\n\n");

        if (text) return text;
    }

    return JSON.stringify(payload, null, 2);
}