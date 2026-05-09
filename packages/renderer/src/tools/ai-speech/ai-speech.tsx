import { useState } from "react";
import { useAiTask } from "../shared/use-ai-task";
import { ArtifactCard, resolveTaskState, TaskStateTag, WorkflowSteps } from "../../components/ai-task-chrome";
import { Panel, PillTag, PrimaryButton, SecondaryButton, TextArea, TextInput, ToolLayout } from "../../components/tool-layout";

export function AiSpeechPage(): JSX.Element {
  const [voiceId, setVoiceId] = useState("male-qn-qingse");
  const task = useAiTask("Text for MiniMax speech generation.");
  const taskState = resolveTaskState(task.status, task.running);

  return (
    <ToolLayout title="AI Speech" description="Generate speech tasks with MiniMax and persist audio artifacts in main-process storage.">
      <div className="grid gap-6 xl:grid-cols-[minmax(0,1fr)_360px] xl:items-start">
        <div className="grid gap-5">
          <Panel
            title="Speech request"
            actions={
              <div className="flex flex-wrap gap-2">
                <PrimaryButton type="button" disabled={!task.prompt.trim() || task.running} onClick={() => void task.start({ provider: "minimax", toolId: "aiSpeech", text: task.prompt, voiceId })}>
                  Generate
                </PrimaryButton>
                <SecondaryButton type="button" disabled={!task.running} onClick={() => void task.cancel()}>
                  Cancel
                </SecondaryButton>
              </div>
            }
          >
            <TextArea value={task.prompt} onChange={(event) => task.setPrompt(event.target.value)} className="min-h-56" />
            <TextInput
              value={voiceId}
              onChange={(event) => setVoiceId(event.target.value)}
              className="mt-3"
              placeholder="Voice ID"
            />
            <div className="mt-3 flex flex-wrap gap-2 text-[12px] text-[var(--app-text-muted)]">
              <PillTag tone="neutral">Voice</PillTag>
              <PillTag tone="accent">{voiceId}</PillTag>
            </div>
          </Panel>
        </div>

        <div className="grid gap-5 xl:sticky xl:top-0">
          <Panel title="Execution" actions={<TaskStateTag state={taskState} label={task.status.split(" · ")[0] || "Idle"} />}>
            <WorkflowSteps steps={task.steps} emptyTitle="No speech job yet" emptyDescription="Execution stages and speech artifact details will appear here after generation starts." />
          </Panel>
          <Panel title="Artifact" actions={task.artifact ? <PillTag tone="accent">Speech</PillTag> : undefined}>
            <ArtifactCard artifact={task.artifact} summary={task.artifactSummary} />
          </Panel>
        </div>
      </div>
    </ToolLayout>
  );
}
