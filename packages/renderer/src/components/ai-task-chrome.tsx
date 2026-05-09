import type { GeneratedArtifact } from "@codetool/shared";
import {
    AlertTriangle,
    Bot,
    CheckCircle2,
    Clock3,
    FileAudio2,
    FileImage,
    LoaderCircle,
    MessageSquareText,
    Music4,
    Sparkles,
    User,
    Wrench
} from "lucide-react";
import type { ReactNode } from "react";
import type { AiTaskStep, AiTaskStepState } from "../tools/shared/use-ai-task";
import { CodeBlock, PillTag } from "./tool-layout";

export function resolveTaskState(status: string, running: boolean): AiTaskStepState {
    if (running) return "running";
    if (status === "Cancelled" || status.startsWith("Failed")) return "error";
    if (status.startsWith("Completed")) return "success";
    return "idle";
}

export function TaskStateTag({ state, label }: { state: AiTaskStepState; label: string }): JSX.Element {
    const config = {
        idle: {
            className: "border-[var(--app-border)] bg-[var(--app-bg-muted)] text-[var(--app-text-muted)]",
            icon: <Clock3 size={12} />
        },
        running: {
            className: "border-[var(--app-border-strong)] bg-[var(--app-accent-soft)] text-[var(--app-text)]",
            icon: <LoaderCircle size={12} className="animate-spin" />
        },
        success: {
            className: "border-[rgba(32,180,134,0.22)] bg-[rgba(32,180,134,0.1)] text-[#157b61]",
            icon: <CheckCircle2 size={12} />
        },
        error: {
            className: "border-[rgba(194,65,45,0.22)] bg-[rgba(194,65,45,0.1)] text-[#a73424]",
            icon: <AlertTriangle size={12} />
        }
    }[state];

    return (
        <span className={`inline-flex h-7 items-center gap-1.5 rounded-full border px-3 text-[11px] font-medium ${config.className}`}>
            {config.icon}
            <span>{label}</span>
        </span>
    );
}

export function MessageBubble({
    role,
    title,
    caption,
    tags,
    children,
    streaming = false
}: {
    role: "user" | "assistant";
    title: string;
    caption?: string;
    tags?: ReactNode;
    children: ReactNode;
    streaming?: boolean;
}): JSX.Element {
    const isUser = role === "user";

    return (
        <div className={`flex ${isUser ? "justify-end" : "justify-start"}`}>
            <div
                className={[
                    "max-w-[92%] rounded-[8px] border p-5 shadow-[0_10px_26px_rgba(24,24,22,0.04)]",
                    isUser
                        ? "border-[var(--app-border-strong)] bg-[var(--app-accent-soft)]"
                        : "border-[var(--app-border)] bg-[var(--app-panel)]"
                ].join(" ")}
            >
                <div className="mb-4 flex flex-wrap items-start justify-between gap-3">
                    <div className="flex items-center gap-3">
                        <span
                            className={[
                                "grid h-9 w-9 place-items-center rounded-[8px]",
                                isUser
                                    ? "border border-[var(--app-border-strong)] bg-[var(--app-accent-soft)] text-[var(--app-accent)]"
                                    : "bg-[var(--app-bg-muted)] text-[var(--app-text-muted)]"
                            ].join(" ")}
                        >
                            {isUser ? <User size={15} /> : <Bot size={15} />}
                        </span>
                        <div>
                            <div className="text-[13px] font-semibold tracking-normal text-[var(--app-text)]">{title}</div>
                            {caption ? <div className="mt-1 text-[12px] text-[var(--app-text-muted)]">{caption}</div> : null}
                        </div>
                    </div>
                    {tags ? <div className="flex flex-wrap justify-end gap-2">{tags}</div> : null}
                </div>
                <div className="whitespace-pre-wrap text-[14px] leading-7 text-[var(--app-text)]">{children}</div>
                {streaming ? (
                    <div className="mt-4 flex items-center gap-2 text-[12px] text-[var(--app-text-muted)]">
                        <LoaderCircle size={12} className="animate-spin" />
                        Streaming response
                    </div>
                ) : null}
            </div>
        </div>
    );
}

export function WorkflowSteps({
    steps,
    emptyTitle = "No workflow yet",
    emptyDescription = "Start a task to reveal execution steps, tool calls and artifact milestones."
}: {
    steps: AiTaskStep[];
    emptyTitle?: string;
    emptyDescription?: string;
}): JSX.Element {
    if (steps.length === 0) {
        return (
            <div className="rounded-[8px] border border-[var(--app-border)] bg-[var(--app-panel)] p-4 text-sm text-[var(--app-text-muted)]">
                <div className="text-[13px] font-medium text-[var(--app-text)]">{emptyTitle}</div>
                <div className="mt-2 leading-6">{emptyDescription}</div>
            </div>
        );
    }

    return (
        <div className="space-y-3">
            {steps.map((step) => (
                <div key={step.id} className="rounded-[8px] border border-[var(--app-border)] bg-[var(--app-panel)] p-4 shadow-[0_8px_22px_rgba(24,24,22,0.04)]">
                    <div className="flex items-start justify-between gap-3">
                        <div className="flex min-w-0 items-start gap-3">
                            <span className="mt-0.5 grid h-9 w-9 shrink-0 place-items-center rounded-[8px] bg-[var(--app-bg-muted)] text-[var(--app-text-muted)]">
                                {iconForStep(step)}
                            </span>
                            <div className="min-w-0">
                                <div className="text-[13px] font-medium tracking-normal text-[var(--app-text)]">{step.title}</div>
                                <div className="mt-1 text-[12px] leading-5 text-[var(--app-text-muted)]">{step.detail}</div>
                            </div>
                        </div>
                        <TaskStateTag state={step.state} label={labelForStep(step)} />
                    </div>
                    {step.payload ? <CodeBlock className="mt-3 max-h-44 overflow-auto text-[12px] leading-5">{step.payload}</CodeBlock> : null}
                </div>
            ))}
        </div>
    );
}

export function ArtifactCard({ artifact, summary }: { artifact: GeneratedArtifact | null; summary: string }): JSX.Element {
    if (!artifact) {
        return (
            <div className="rounded-[8px] border border-[var(--app-border)] bg-[var(--app-panel)] p-4 text-sm text-[var(--app-text-muted)]">
                <div className="text-[13px] font-medium text-[var(--app-text)]">Artifact pending</div>
                <div className="mt-2 leading-6">{summary}</div>
            </div>
        );
    }

    const label = artifact.kind.charAt(0).toUpperCase() + artifact.kind.slice(1);
    const detail = artifact.asset
        ? `${artifact.asset.filename} · ${artifact.mimeType}`
        : artifact.text
            ? `${artifact.text.length} chars · ${artifact.mimeType}`
            : artifact.mimeType;
    const payload = artifact.text ?? JSON.stringify(artifact.metadata ?? artifact.asset ?? {}, null, 2);

    return (
        <div className="space-y-3">
            <div className="rounded-[8px] border border-[var(--app-border)] bg-[var(--app-panel)] p-4 shadow-[0_8px_22px_rgba(24,24,22,0.04)]">
                <div className="flex items-center justify-between gap-3">
                    <div className="flex items-center gap-3">
                        <span className="grid h-10 w-10 place-items-center rounded-[8px] bg-[var(--app-accent-soft)] text-[var(--app-text)]">
                            {iconForArtifact(artifact)}
                        </span>
                        <div>
                            <div className="text-[13px] font-medium text-[var(--app-text)]">{label} artifact</div>
                            <div className="mt-1 text-[12px] text-[var(--app-text-muted)]">{detail}</div>
                        </div>
                    </div>
                    <PillTag tone="accent">{label}</PillTag>
                </div>
            </div>
            {payload ? <CodeBlock className="max-h-52 overflow-auto text-[12px] leading-5">{payload}</CodeBlock> : null}
        </div>
    );
}

function labelForStep(step: AiTaskStep): string {
    switch (step.kind) {
        case "system":
            return "System";
        case "tool":
            return "Tool call";
        case "artifact":
            return "Artifact";
    }
}

function iconForStep(step: AiTaskStep): JSX.Element {
    switch (step.kind) {
        case "system":
            return <Sparkles size={16} />;
        case "tool":
            return <Wrench size={16} />;
        case "artifact":
            return <MessageSquareText size={16} />;
    }
}

function iconForArtifact(artifact: GeneratedArtifact): JSX.Element {
    switch (artifact.kind) {
        case "text":
            return <MessageSquareText size={18} />;
        case "image":
            return <FileImage size={18} />;
        case "speech":
            return <FileAudio2 size={18} />;
        case "music":
            return <Music4 size={18} />;
    }
}