import type { AiTaskStep, AiTaskStepState } from "../shared/use-ai-task";
import type { PiToolPolicy, ThinkingLevel } from "@codetool/shared";
import { useEffect, useRef, useState } from "react";
import { getApi } from "../../api";

const WORKSPACE_STORAGE_KEY = "codetool.piAgent.workspaceRoot";

export interface PiConversationMessage {
    id: string;
    role: "user" | "assistant";
    text: string;
    thinking: string;
    stopReason?: string;
}

interface PiToolCallTrace {
    id: string;
    name: string;
    args: string;
    output: string;
    state: AiTaskStepState;
    detail: string;
}

interface PiAgentConfig {
    workspaceRoot: string;
    providerName: string;
    modelId: string;
    thinkingLevel: ThinkingLevel;
    toolPolicy: PiToolPolicy;
}

const DEFAULT_CONFIG: PiAgentConfig = {
    workspaceRoot: readStoredWorkspaceRoot(),
    providerName: "",
    modelId: "",
    thinkingLevel: "medium",
    toolPolicy: "readOnly"
};

export function usePiAgentTask() {
    const api = getApi();
    const [prompt, setPrompt] = useState("");
    const [config, setConfig] = useState<PiAgentConfig>(DEFAULT_CONFIG);
    const [running, setRunning] = useState(false);
    const [status, setStatus] = useState("Idle");
    const [sessionId, setSessionId] = useState<string | null>(null);
    const [messages, setMessages] = useState<PiConversationMessage[]>([]);
    const [toolCalls, setToolCalls] = useState<PiToolCallTrace[]>([]);
    const [steeringQueue, setSteeringQueue] = useState<string[]>([]);
    const [followUpQueue, setFollowUpQueue] = useState<string[]>([]);
    const [compactionNote, setCompactionNote] = useState("");
    const [retryNote, setRetryNote] = useState("");
    const currentTaskIdRef = useRef<string | null>(null);

    useEffect(() => {
        window.localStorage.setItem(WORKSPACE_STORAGE_KEY, config.workspaceRoot);
    }, [config.workspaceRoot]);

    useEffect(() => {
        return api.ai.onTaskEvent((event) => {
            if (event.taskId !== currentTaskIdRef.current) return;

            switch (event.type) {
                case "agent_start":
                    setRunning(true);
                    setSessionId(event.sessionId);
                    setStatus(`Running · ${event.workspaceRoot}`);
                    return;
                case "agent_end":
                    setRunning(false);
                    setStatus(`Agent finished · ${event.messageCount} messages`);
                    return;
                case "message_start":
                    if (event.role !== "assistant") return;
                    setMessages((current) => ensureAssistantMessage(current, event.messageId));
                    return;
                case "message_delta":
                    setMessages((current) => updateAssistantMessage(current, event.messageId, event.deltaType, event.text));
                    return;
                case "message_end":
                    if (event.role !== "assistant") return;
                    setMessages((current) =>
                        current.map((message) =>
                            message.id === event.messageId ? { ...message, stopReason: event.stopReason ?? message.stopReason } : message
                        )
                    );
                    return;
                case "toolcall_start":
                    setToolCalls((current) =>
                        upsertToolCall(current, {
                            id: event.toolCallId,
                            name: event.toolName,
                            args: prettyJson(event.args),
                            output: "",
                            state: event.phase === "execution" ? "running" : "idle",
                            detail: event.phase === "execution" ? "Tool execution in progress" : "Tool call drafted"
                        })
                    );
                    return;
                case "toolcall_delta":
                    setToolCalls((current) =>
                        current.map((toolCall) => {
                            if (toolCall.id !== event.toolCallId) return toolCall;
                            if (event.phase === "call") {
                                return {
                                    ...toolCall,
                                    args: prettyJson(event.partialResult?.arguments ?? {}),
                                    detail: "Tool call drafted"
                                };
                            }
                            return {
                                ...toolCall,
                                output: appendChunk(toolCall.output, event.partialText),
                                state: "running",
                                detail: "Tool execution in progress"
                            };
                        })
                    );
                    return;
                case "toolcall_end":
                    setToolCalls((current) =>
                        current.map((toolCall) => {
                            if (toolCall.id !== event.toolCallId) return toolCall;
                            if (event.phase === "call") {
                                return {
                                    ...toolCall,
                                    args: prettyJson(event.result?.arguments ?? {}),
                                    detail: "Tool call ready"
                                };
                            }
                            return {
                                ...toolCall,
                                output: event.resultText || toolCall.output,
                                state: event.isError ? "error" : "success",
                                detail: event.isError ? "Tool execution failed" : "Tool execution completed"
                            };
                        })
                    );
                    return;
                case "queue_update":
                    setSteeringQueue(event.steering);
                    setFollowUpQueue(event.followUp);
                    return;
                case "compaction_start":
                    setCompactionNote(`Compaction started · ${event.reason}`);
                    return;
                case "compaction_end":
                    setCompactionNote(
                        event.errorMessage
                            ? `Compaction failed · ${event.errorMessage}`
                            : event.summary
                                ? `Compaction complete · ${event.summary}`
                                : `Compaction complete · ${event.reason}`
                    );
                    return;
                case "auto_retry_start":
                    setRetryNote(`Retry ${event.attempt}/${event.maxAttempts} in ${event.delayMs} ms`);
                    setStatus(`Retrying · ${event.attempt}/${event.maxAttempts}`);
                    return;
                case "auto_retry_end":
                    setRetryNote(event.success ? `Retry recovered on attempt ${event.attempt}` : `Retry failed · ${event.finalError ?? "Unknown error"}`);
                    return;
                case "completed":
                    currentTaskIdRef.current = null;
                    setRunning(false);
                    setStatus(`Completed · ${event.durationMs} ms`);
                    return;
                case "cancelled":
                    currentTaskIdRef.current = null;
                    setRunning(false);
                    setStatus("Cancelled");
                    return;
                case "failed":
                    currentTaskIdRef.current = null;
                    setRunning(false);
                    setStatus(`Failed · ${event.message}`);
                    return;
                case "progress":
                case "artifact":
                    return;
            }
        });
    }, [api.ai]);

    const steps: AiTaskStep[] = [
        ...toolCalls.map((toolCall) => ({
            id: `tool-${toolCall.id}`,
            title: toolCall.name,
            detail: toolCall.detail,
            kind: "tool" as const,
            state: toolCall.state,
            payload: [toolCall.args ? `Args\n${toolCall.args}` : "", toolCall.output ? `Output\n${toolCall.output}` : ""]
                .filter(Boolean)
                .join("\n\n")
        })),
        ...(compactionNote
            ? [
                {
                    id: "compaction",
                    title: "Context compaction",
                    detail: compactionNote,
                    kind: "system" as const,
                    state: (compactionNote.startsWith("Compaction failed") ? "error" : "success") as AiTaskStepState
                }
            ]
            : []),
        ...(retryNote
            ? [
                {
                    id: "retry",
                    title: "Auto retry",
                    detail: retryNote,
                    kind: "system" as const,
                    state: (retryNote.startsWith("Retry failed") ? "error" : running ? "running" : "success") as AiTaskStepState
                }
            ]
            : [])
    ];

    async function start(): Promise<void> {
        const trimmedPrompt = prompt.trim();
        const workspaceRoot = config.workspaceRoot.trim();
        if (!trimmedPrompt || !workspaceRoot || running) return;

        setMessages((current) => [
            ...current,
            {
                id: `user-${Date.now()}`,
                role: "user",
                text: trimmedPrompt,
                thinking: ""
            }
        ]);
        setPrompt("");
        setRunning(true);
        setStatus(sessionId ? "Queued follow-up" : "Queued new session");

        try {
            const result = await api.ai.createTask({
                provider: "pi",
                toolId: "piAgent",
                prompt: trimmedPrompt,
                workspaceRoot,
                sessionId: sessionId ?? undefined,
                providerName: config.providerName.trim() || undefined,
                modelId: config.modelId.trim() || undefined,
                thinkingLevel: config.thinkingLevel,
                toolPolicy: config.toolPolicy
            });
            currentTaskIdRef.current = result.taskId;
            setSessionId(result.sessionId ?? sessionId);
        } catch (error) {
            currentTaskIdRef.current = null;
            setRunning(false);
            setStatus(error instanceof Error ? `Failed · ${error.message}` : "Failed · Unable to start Pi Agent");
        }
    }

    async function cancel(): Promise<void> {
        const taskId = currentTaskIdRef.current;
        if (!taskId) return;
        const result = await api.ai.cancelTask({ taskId });
        if (!result.cancelled) {
            setStatus("Failed · Unable to cancel task");
        }
    }

    function resetSession(): void {
        currentTaskIdRef.current = null;
        setSessionId(null);
        setMessages([]);
        setToolCalls([]);
        setSteeringQueue([]);
        setFollowUpQueue([]);
        setCompactionNote("");
        setRetryNote("");
        setStatus("Idle");
        setRunning(false);
    }

    function updateConfig<K extends keyof PiAgentConfig>(key: K, value: PiAgentConfig[K]): void {
        setConfig((current) => ({ ...current, [key]: value }));
    }

    return {
        prompt,
        setPrompt,
        config,
        updateConfig,
        running,
        status,
        sessionId,
        messages,
        steps,
        steeringQueue,
        followUpQueue,
        compactionNote,
        retryNote,
        start,
        cancel,
        resetSession
    };
}

function ensureAssistantMessage(messages: PiConversationMessage[], messageId: string): PiConversationMessage[] {
    if (messages.some((message) => message.id === messageId)) {
        return messages;
    }
    return [...messages, { id: messageId, role: "assistant", text: "", thinking: "" }];
}

function updateAssistantMessage(
    messages: PiConversationMessage[],
    messageId: string,
    deltaType: "text" | "thinking",
    text: string
): PiConversationMessage[] {
    return ensureAssistantMessage(messages, messageId).map((message) => {
        if (message.id !== messageId) return message;
        return deltaType === "thinking"
            ? { ...message, thinking: appendChunk(message.thinking, text) }
            : { ...message, text: appendChunk(message.text, text) };
    });
}

function upsertToolCall(toolCalls: PiToolCallTrace[], next: PiToolCallTrace): PiToolCallTrace[] {
    const index = toolCalls.findIndex((toolCall) => toolCall.id === next.id);
    if (index === -1) {
        return [...toolCalls, next];
    }
    return toolCalls.map((toolCall, toolCallIndex) => (toolCallIndex === index ? { ...toolCall, ...next } : toolCall));
}

function appendChunk(current: string, next: string): string {
    return `${current}${next}`;
}

function prettyJson(value: unknown): string {
    if (!value || (typeof value === "object" && Object.keys(value as Record<string, unknown>).length === 0)) {
        return "";
    }
    return JSON.stringify(value, null, 2);
}

function readStoredWorkspaceRoot(): string {
    if (typeof window === "undefined") return "";
    return window.localStorage.getItem(WORKSPACE_STORAGE_KEY) ?? "";
}