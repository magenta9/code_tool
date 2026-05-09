import { useEffect, useRef, useState } from "react";
import type { AiTaskEvent, AiTaskRequest } from "@codetool/shared";
import { getApi } from "../../api";

export function useAiTask(initialPrompt = "") {
  const [prompt, setPrompt] = useState(initialPrompt);
  const [taskId, setTaskId] = useState<string | null>(null);
  const [running, setRunning] = useState(false);
  const [status, setStatus] = useState("Idle");
  const [output, setOutput] = useState("");
  const [artifactSummary, setArtifactSummary] = useState("No artifact yet.");
  const currentTask = useRef<string | null>(null);

  useEffect(() => {
    const unsubscribe = getApi().ai.onTaskEvent((event) => {
      if (event.taskId !== currentTask.current) return;
      handleEvent(event);
    });
    return unsubscribe;
  }, []);

  function handleEvent(event: AiTaskEvent): void {
    switch (event.type) {
      case "started":
        setRunning(true);
        setStatus(`Started · ${event.referenceId}`);
        setOutput("");
        setArtifactSummary("Waiting for artifacts.");
        break;
      case "progress":
        setStatus(`${event.stage} · ${event.message ?? "working"}`);
        break;
      case "delta":
        setOutput((value) => value + event.text);
        break;
      case "artifact":
        setArtifactSummary(JSON.stringify(event.artifact, null, 2));
        break;
      case "completed":
        setRunning(false);
        setStatus(`Completed · history ${event.historyId} · ${event.durationMs} ms`);
        break;
      case "cancelled":
        setRunning(false);
        setStatus("Cancelled");
        break;
      case "failed":
        setRunning(false);
        setStatus(`Failed · ${event.referenceId} · ${event.message}`);
        break;
    }
  }

  async function start(request: AiTaskRequest): Promise<void> {
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
    artifactSummary,
    start,
    cancel
  };
}
