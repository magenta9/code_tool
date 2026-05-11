import { Bot, RotateCcw, Send, SquareTerminal, Workflow } from "lucide-react";
import { MessageBubble, TaskStateTag, WorkflowSteps, resolveTaskState } from "../../components/ai-task-chrome";
import {
    ActionButton,
    Panel,
    PillTag,
    SelectField,
    StatusStrip,
    TextArea,
    TextInput,
    ToolLayout
} from "../../components/tool-layout";
import { usePiAgentTask } from "./use-pi-agent-task";

export function PiAgentPage(): JSX.Element {
    const {
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
    } = usePiAgentTask();

    const state = resolveTaskState(status, running);

    return (
        <ToolLayout
            title="Pi Agent"
            description="Run a real Pi coding-agent session against a workspace, stream assistant output, and inspect tool execution traces without leaving the workbench."
            actions={
                <>
                    <PillTag tone="accent" icon={<Bot size={12} />}>
                        Official SDK
                    </PillTag>
                    <TaskStateTag state={state} label={status} />
                </>
            }
        >
            <div className="grid gap-6 xl:grid-cols-[minmax(0,1.55fr)_minmax(320px,0.95fr)]">
                <div className="space-y-6">
                    <Panel
                        title="Conversation"
                        actions={
                            <div className="flex flex-wrap items-center gap-2">
                                {sessionId ? <PillTag tone="success">Session active</PillTag> : <PillTag>New session</PillTag>}
                                <PillTag>{messages.length} messages</PillTag>
                            </div>
                        }
                    >
                        <div className="space-y-4">
                            {messages.length === 0 ? (
                                <div className="rounded-[8px] border border-[var(--app-border)] bg-[var(--app-bg-muted)] p-5 text-[14px] leading-7 text-[var(--app-text-muted)]">
                                    Pi Agent uses your existing Pi CLI auth and runs inside the workspace root you provide below. Start with a concrete coding request so the tool trace stays readable.
                                </div>
                            ) : null}
                            {messages.map((message) => (
                                <MessageBubble
                                    key={message.id}
                                    role={message.role}
                                    title={message.role === "user" ? "You" : "Pi Agent"}
                                    caption={message.role === "assistant" ? "Tool-aware coding session" : "Prompt"}
                                    tags={
                                        message.role === "assistant" && message.stopReason ? <PillTag tone="accent">{message.stopReason}</PillTag> : undefined
                                    }
                                    streaming={message.role === "assistant" && running && !message.stopReason}
                                >
                                    <div className="space-y-3">
                                        {message.thinking ? (
                                            <div className="rounded-[8px] border border-[var(--app-border)] bg-[var(--app-bg-muted)] px-4 py-3 text-[12px] leading-6 text-[var(--app-text-muted)]">
                                                {message.thinking}
                                            </div>
                                        ) : null}
                                        <div>{message.text || (message.role === "assistant" ? "Waiting for response…" : "")}</div>
                                    </div>
                                </MessageBubble>
                            ))}
                        </div>
                    </Panel>

                    <Panel
                        title="Composer"
                        actions={
                            <div className="flex flex-wrap items-center gap-2">
                                <ActionButton type="button" onClick={resetSession} disabled={running}>
                                    <RotateCcw size={14} /> New session
                                </ActionButton>
                                <ActionButton type="button" onClick={() => void cancel()} disabled={!running}>
                                    <SquareTerminal size={14} /> Cancel
                                </ActionButton>
                                <ActionButton type="button" variant="primary" onClick={() => void start()} disabled={running || !prompt.trim() || !config.workspaceRoot.trim()}>
                                    <Send size={14} /> Run prompt
                                </ActionButton>
                            </div>
                        }
                    >
                        <div className="grid gap-4 lg:grid-cols-2">
                            <Field label="Workspace root">
                                <TextInput
                                    value={config.workspaceRoot}
                                    onChange={(event) => updateConfig("workspaceRoot", event.target.value)}
                                    placeholder="/Users/you/code/project"
                                />
                            </Field>
                            <Field label="Provider name">
                                <TextInput
                                    value={config.providerName}
                                    onChange={(event) => updateConfig("providerName", event.target.value)}
                                    placeholder="anthropic / openai / google"
                                />
                            </Field>
                            <Field label="Model id">
                                <TextInput
                                    value={config.modelId}
                                    onChange={(event) => updateConfig("modelId", event.target.value)}
                                    placeholder="Leave blank for Pi default"
                                />
                            </Field>
                            <Field label="Thinking level">
                                <SelectField value={config.thinkingLevel} onChange={(event) => updateConfig("thinkingLevel", event.target.value as typeof config.thinkingLevel)}>
                                    <option value="minimal">Minimal</option>
                                    <option value="low">Low</option>
                                    <option value="medium">Medium</option>
                                    <option value="high">High</option>
                                </SelectField>
                            </Field>
                            <Field label="Tool policy">
                                <SelectField value={config.toolPolicy} onChange={(event) => updateConfig("toolPolicy", event.target.value as typeof config.toolPolicy)}>
                                    <option value="readOnly">Read only</option>
                                    <option value="workspaceWrite">Workspace write</option>
                                </SelectField>
                            </Field>
                            <Field label="Session id">
                                <TextInput value={sessionId ?? "A new session will be created on first run"} readOnly />
                            </Field>
                        </div>

                        <div className="mt-4 space-y-3">
                            <Field label="Prompt">
                                <TextArea value={prompt} onChange={(event) => setPrompt(event.target.value)} placeholder="Ask Pi Agent to inspect a file, edit code, or explain a failing workflow." />
                            </Field>
                            <StatusStrip>
                                Pi Agent reuses the same session across follow-up prompts until you reset it. Authentication comes from your existing Pi CLI setup on this machine.
                            </StatusStrip>
                        </div>
                    </Panel>
                </div>

                <div className="space-y-6">
                    <Panel
                        title="Tool trace"
                        actions={
                            <div className="flex flex-wrap items-center gap-2">
                                <PillTag icon={<Workflow size={12} />}>{steps.length} steps</PillTag>
                                <PillTag tone={running ? "accent" : state === "error" ? "danger" : "neutral"}>{running ? "Streaming" : "Idle"}</PillTag>
                            </div>
                        }
                    >
                        <WorkflowSteps
                            steps={steps}
                            emptyTitle="No tool calls yet"
                            emptyDescription="Pi will surface real tool invocations here, including arguments, live execution output, compaction events and retries."
                        />
                    </Panel>

                    <Panel
                        title="Session state"
                        actions={
                            <div className="flex flex-wrap items-center gap-2">
                                <PillTag>{config.toolPolicy === "workspaceWrite" ? "Writable" : "Read only"}</PillTag>
                                <PillTag tone="accent">{config.thinkingLevel}</PillTag>
                            </div>
                        }
                    >
                        <div className="space-y-4 text-[13px] leading-6 text-[var(--app-text-muted)]">
                            <div>
                                <div className="text-[11px] font-semibold uppercase tracking-[0.18em] text-[var(--app-text-muted)]">Steering queue</div>
                                <div className="mt-2 flex flex-wrap gap-2">
                                    {steeringQueue.length > 0 ? steeringQueue.map((item) => <PillTag key={item}>{item}</PillTag>) : <PillTag>No queued steering</PillTag>}
                                </div>
                            </div>
                            <div>
                                <div className="text-[11px] font-semibold uppercase tracking-[0.18em] text-[var(--app-text-muted)]">Follow-up queue</div>
                                <div className="mt-2 flex flex-wrap gap-2">
                                    {followUpQueue.length > 0 ? followUpQueue.map((item) => <PillTag key={item}>{item}</PillTag>) : <PillTag>No follow-up tasks</PillTag>}
                                </div>
                            </div>
                            {compactionNote ? <StatusStrip>{compactionNote}</StatusStrip> : null}
                            {retryNote ? <StatusStrip>{retryNote}</StatusStrip> : null}
                        </div>
                    </Panel>
                </div>
            </div>
        </ToolLayout>
    );
}

function Field({ label, children }: { label: string; children: JSX.Element }): JSX.Element {
    return (
        <label className="space-y-2">
            <div className="text-[11px] font-semibold uppercase tracking-[0.18em] text-[var(--app-text-muted)]">{label}</div>
            {children}
        </label>
    );
}
