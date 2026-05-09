import { useEffect, useRef, useState } from "react";
import type { AiTaskEvent, AiTaskRequest, GeneratedArtifact } from "@codetool/shared";
import { getApi } from "../../api";

export type AiTaskStepState = "idle" | "running" | "success" | "error";

export interface AiTaskStep {
  id: string;
  kind: "system" | "tool" | "artifact";
  title: string;
  detail: string;
  state: AiTaskStepState;
  payload?: string;
}

export function useAiTask(initialPrompt = "") {
  const [prompt, setPrompt] = useState(initialPrompt);
  const [taskId, setTaskId] = useState<string | null>(null);
  const [running, setRunning] = useState(false);
  const [status, setStatus] = useState("Idle");
  const [output, setOutput] = useState("");
  const [artifactSummary, setArtifactSummary] = useState("No artifact yet.");
  const [artifact, setArtifact] = useState<GeneratedArtifact | null>(null);
  const [submittedPrompt, setSubmittedPrompt] = useState("");
  const [steps, setSteps] = useState<AiTaskStep[]>([]);
  const currentTask = useRef<string | null>(null);

  useEffect(() => {
    const unsubscribe = getApi().ai.onTaskEvent((event) => {
      if (event.taskId !== currentTask.current) return;
      handleEvent(event);
    });
    return unsubscribe;
  }, []);

  function pushProgressStep(stage: string, message?: string): void {
    setSteps((current) => updateStepsForProgress(current, stage, message));
  }

  function completeRunningSteps(): void {
    setSteps((current) => completeSteps(current));
  }

  function failRunningSteps(message: string): void {
    setSteps((current) => errorSteps(current, message));
  }

  function handleEvent(event: AiTaskEvent): void {
    switch (event.type) {
      case "started":
        setRunning(true);
        setStatus(`Started · ${event.referenceId}`);
        setOutput("");
        setArtifactSummary("Waiting for artifacts.");
        setArtifact(null);
        setSteps([
          {
            id: "started",
            kind: "system",
            title: "Task started",
            detail: `${labelForTool(event.toolId)} · ${event.referenceId}`,
            state: "success"
          }
        ]);
        break;
      case "progress":
        setStatus(`${event.stage} · ${event.message ?? "working"}`);
        pushProgressStep(event.stage, event.message);
        break;
      case "delta":
        setOutput((value) => value + event.text);
        break;
      case "artifact":
        completeRunningSteps();
        setArtifact(event.artifact);
        setArtifactSummary(JSON.stringify(event.artifact, null, 2));
        setSteps((current) => [
          ...current,
          {
            id: `artifact-${current.length + 1}`,
            kind: "artifact",
            title: `${labelForArtifact(event.artifact)} ready`,
            detail: artifactDetail(event.artifact),
            state: "success",
            payload: event.artifact.text ?? JSON.stringify(event.artifact.metadata ?? event.artifact.asset ?? {}, null, 2)
          }
        ]);
        break;
      case "completed":
        setRunning(false);
        setStatus(`Completed · history ${event.historyId} · ${event.durationMs} ms`);
        completeRunningSteps();
        setSteps((current) => [
          ...current,
          {
            id: `completed-${event.historyId}`,
            kind: "system",
            title: "Task completed",
            detail: `History ${event.historyId} · ${event.durationMs} ms`,
            state: "success"
          }
        ]);
        break;
      case "cancelled":
        setRunning(false);
        setStatus("Cancelled");
        failRunningSteps("Task cancelled.");
        break;
      case "failed":
        setRunning(false);
        setStatus(`Failed · ${event.referenceId} · ${event.message}`);
        failRunningSteps(event.message);
        break;
    }
  }

  async function start(request: AiTaskRequest): Promise<void> {
    const nextPrompt = request.toolId === "aiSpeech" ? request.text : request.prompt;
    setSubmittedPrompt(nextPrompt);
    setArtifact(null);
    setOutput("");
    setArtifactSummary("No artifact yet.");
    setSteps([
      {
        id: "queued",
        kind: "system",
        title: "Queued",
        detail: "Waiting for execution slot.",
        state: "running"
      }
    ]);
    const result = await getApi().ai.createTask(request);
    currentTask.current = result.taskId;
    setTaskId(result.taskId);
    setRunning(true);
    setStatus(`Queued · ${result.taskId}`);
  }

  async function cancel(): Promise<void> {
    if (!taskId) return;
    await getApi().ai.cancelTask({ taskId });
  }

  return {
    prompt,
    setPrompt,
    running,
    status,
    output,
    artifact,
    artifactSummary,
    submittedPrompt,
    steps,
    start,
    cancel
  };
}

function labelForTool(toolId: AiTaskRequest["toolId"]): string {
  switch (toolId) {
    case "aiChat":
      return "AI Chat";
    case "aiSpeech":
      return "AI Speech";
    case "aiImage":
      return "AI Image";
    case "aiMusic":
      return "AI Music";
  }
}

function labelForArtifact(artifact: GeneratedArtifact): string {
  switch (artifact.kind) {
    case "text":
      return "Response";
    case "image":
      return "Image";
    case "speech":
      return "Speech";
    case "music":
      return "Music";
  }
}

function artifactDetail(artifact: GeneratedArtifact): string {
  if (artifact.asset) {
    return `${artifact.asset.filename} · ${artifact.mimeType}`;
  }
  if (artifact.text) {
    return `${artifact.text.length} chars · ${artifact.mimeType}`;
  }
  return artifact.mimeType;
}

function humanizeStage(stage: string): string {
  switch (stage) {
    case "provider":
      return "Provider setup";
    case "request":
      return "Model request";
    default:
      return stage.charAt(0).toUpperCase() + stage.slice(1);
  }
}

function updateStepsForProgress(current: AiTaskStep[], stage: string, message?: string): AiTaskStep[] {
  const next = current.map((step) =>
    step.state === "running" ? { ...step, state: "success" as const } : step
  );
  const id = `progress-${stage}`;
  const existingIndex = next.findIndex((step) => step.id === id);
  const entry: AiTaskStep = {
    id,
    kind: "tool",
    title: humanizeStage(stage),
    detail: message ?? "Working",
    state: "running"
  };

  if (existingIndex >= 0) {
    next[existingIndex] = entry;
    return next;
  }

  return [...next, entry];
}

function completeSteps(current: AiTaskStep[]): AiTaskStep[] {
  return current.map((step) => (step.state === "running" ? { ...step, state: "success" as const } : step));
}

function errorSteps(current: AiTaskStep[], message: string): AiTaskStep[] {
  const next = current.map((step) => (step.state === "running" ? { ...step, state: "error" as const, detail: message } : step));
  return [
    ...next,
    {
      id: `error-${next.length + 1}`,
      kind: "system",
      title: "Task failed",
      detail: message,
      state: "error"
    }
  ];
}

