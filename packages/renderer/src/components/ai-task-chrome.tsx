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
            className: "border-white/[0.08] bg-white/[0.045] text-[var(--app-text-muted)]",
            icon: <Clock3 size={12} />
        },
        running: {
            className: "border-[var(--app-accent-soft-strong)] bg-[var(--app-accent-soft)] text-[#dce5ff]",
            icon: <LoaderCircle size={12} className="animate-spin" />
        },
        success: {
            className: "border-[rgba(89,193,142,0.25)] bg-[rgba(89,193,142,0.12)] text-[#b8f0d0]",
            icon: <CheckCircle2 size={12} />
        },
        error: {
            className: "border-[rgba(255,125,145,0.24)] bg-[rgba(255,125,145,0.12)] text-[#ffc2cb]",
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
                    "max-w-[92%] rounded-[24px] border p-5 shadow-[inset_0_1px_0_rgba(255,255,255,0.04)]",
                    isUser
                        ? "border-[var(--app-accent-soft-strong)] bg-[linear-gradient(180deg,rgba(124,150,255,0.16),rgba(124,150,255,0.08))]"
                        : "border-white/[0.06] bg-[linear-gradient(180deg,rgba(255,255,255,0.045),rgba(255,255,255,0.018))]"
                ].join(" ")}
            >
                <div className="mb-4 flex flex-wrap items-start justify-between gap-3">
                    <div className="flex items-center gap-3">
                        <span
                            className={[
                                "grid h-9 w-9 place-items-center rounded-[14px]",
                                isUser
                                    ? "bg-[linear-gradient(180deg,#8ea7ff_0%,#6f8eff_100%)] text-[var(--app-accent-ink)]"
                                    : "bg-white/[0.06] text-[#dbe5ff]"
                            ].join(" ")}
                        >
                            {isUser ? <User size={15} /> : <Bot size={15} />}
                        </span>
                        <div>
                            <div className="text-[13px] font-semibold tracking-[-0.01em] text-[var(--app-text)]">{title}</div>
                            {caption ? <div className="mt-1 text-[12px] text-[var(--app-text-muted)]">{caption}</div> : null}
                        </div>
                    </div>
                    {tags ? <div className="flex flex-wrap justify-end gap-2">{tags}</div> : null}
                </div>
                <div className="whitespace-pre-wrap text-[14px] leading-7 text-[var(--app-text)]">{children}</div>
                {streaming ? (
                    <div className="mt-4 flex items-center gap-2 text-[12px] text-[#c7d5ff]">
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
            <div className="rounded-[20px] border border-white/[0.06] bg-white/[0.03] p-4 text-sm text-[var(--app-text-muted)]">
                <div className="text-[13px] font-medium text-[var(--app-text)]">{emptyTitle}</div>
                <div className="mt-2 leading-6">{emptyDescription}</div>
            </div>
        );
    }

    return (
        <div className="space-y-3">
            {steps.map((step) => (
                <div key={step.id} className="rounded-[20px] border border-white/[0.06] bg-[rgba(255,255,255,0.028)] p-4 shadow-[inset_0_1px_0_rgba(255,255,255,0.03)]">
                    <div className="flex items-start justify-between gap-3">
                        <div className="flex min-w-0 items-start gap-3">
                            <span className="mt-0.5 grid h-9 w-9 shrink-0 place-items-center rounded-[14px] bg-white/[0.05] text-[#dbe5ff]">
                                {iconForStep(step)}
                            </span>
                            <div className="min-w-0">
                                <div className="text-[13px] font-medium tracking-[-0.01em] text-[var(--app-text)]">{step.title}</div>
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
            <div className="rounded-[20px] border border-white/[0.06] bg-white/[0.03] p-4 text-sm text-[var(--app-text-muted)]">
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
            <div className="rounded-[20px] border border-white/[0.06] bg-white/[0.03] p-4 shadow-[inset_0_1px_0_rgba(255,255,255,0.03)]">
                <div className="flex items-center justify-between gap-3">
                    <div className="flex items-center gap-3">
                        <span className="grid h-10 w-10 place-items-center rounded-[14px] bg-[var(--app-accent-soft)] text-[#dce5ff]">
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