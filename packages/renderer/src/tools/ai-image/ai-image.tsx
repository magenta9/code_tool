import { useState } from "react";
import type { AiTaskRequest } from "@codetool/shared";
import { ImagePlus, Square } from "lucide-react";
import { useAiTask } from "../shared/use-ai-task";
import { ArtifactCard, resolveTaskState, TaskStateTag, WorkflowSteps } from "../../components/ai-task-chrome";
import { ActionButton, Panel, PillTag, SelectField, TextArea, TextInput, ToolLayout } from "../../components/tool-layout";

export function AiImagePage(): JSX.Element {
  const [aspectRatio, setAspectRatio] = useState<Extract<AiTaskRequest, { toolId: "aiImage" }>["aspectRatio"]>("1:1");
  const [count, setCount] = useState(1);
  const task = useAiTask("A precise desktop utility workbench in a cold code lab.");
  const taskState = resolveTaskState(task.status, task.running);

  return (
    <ToolLayout title="AI Image" description="Submit MiniMax image prompts with aspect settings and store resulting assets through main.">
      <div className="grid gap-6 xl:grid-cols-[minmax(0,1fr)_360px] xl:items-start">
        <div className="grid gap-5">
          <Panel
            title="Image request"
            actions={
              <div className="flex flex-wrap gap-2">
                <ActionButton type="button" variant="primary" disabled={!task.prompt.trim() || task.running} onClick={() => void task.start({ provider: "minimax", toolId: "aiImage", prompt: task.prompt, aspectRatio, count })}>
                  <ImagePlus size={14} /> Generate
                </ActionButton>
                <ActionButton type="button" disabled={!task.running} onClick={() => void task.cancel()}>
                  <Square size={13} /> Cancel
                </ActionButton>
              </div>
            }
          >
            <TextArea value={task.prompt} onChange={(event) => task.setPrompt(event.target.value)} className="min-h-56" />
            <div className="mt-3 grid gap-2 md:grid-cols-[180px_120px]">
              <SelectField
                value={aspectRatio}
                onChange={(event) => setAspectRatio(event.target.value as typeof aspectRatio)}
              >
                <option value="1:1">1:1</option>
                <option value="16:9">16:9</option>
                <option value="9:16">9:16</option>
                <option value="4:3">4:3</option>
                <option value="3:4">3:4</option>
              </SelectField>
              <TextInput
                value={count}
                min={1}
                max={4}
                type="number"
                onChange={(event) => setCount(Number(event.target.value))}
                className="[appearance:textfield]"
                placeholder="Count"
              />
            </div>
            <div className="mt-3 flex flex-wrap gap-2 text-[12px] text-[var(--app-text-muted)]">
              <PillTag tone="neutral">Aspect {aspectRatio}</PillTag>
              <PillTag tone="neutral">{count} output{count > 1 ? "s" : ""}</PillTag>
            </div>
          </Panel>
        </div>

        <div className="grid gap-5 xl:sticky xl:top-0">
          <Panel title="Execution" actions={<TaskStateTag state={taskState} label={task.status.split(" · ")[0] || "Idle"} />}>
            <WorkflowSteps steps={task.steps} emptyTitle="No generation trace yet" emptyDescription="Provider, request and artifact stages will appear here after you start an image job." />
          </Panel>
          <Panel title="Artifact" actions={task.artifact ? <PillTag tone="accent">Image</PillTag> : undefined}>
            <ArtifactCard artifact={task.artifact} summary={task.artifactSummary} />
          </Panel>
        </div>
      </div>
    </ToolLayout>
  );
}
