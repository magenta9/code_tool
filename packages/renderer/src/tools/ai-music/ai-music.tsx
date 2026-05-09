import { useState } from "react";
import { useAiTask } from "../shared/use-ai-task";
import { ArtifactCard, resolveTaskState, TaskStateTag, WorkflowSteps } from "../../components/ai-task-chrome";
import { Panel, PillTag, PrimaryButton, SecondaryButton, TextArea, TextInput, ToolLayout } from "../../components/tool-layout";

export function AiMusicPage(): JSX.Element {
  const [lyrics, setLyrics] = useState("");
  const [style, setStyle] = useState("cinematic electronic");
  const task = useAiTask("Generate a concise instrumental theme for a code tool.");
  const taskState = resolveTaskState(task.status, task.running);

  return (
    <ToolLayout title="AI Music" description="Run MiniMax music tasks with long-running status and failure diagnostics.">
      <div className="grid gap-6 xl:grid-cols-[minmax(0,1fr)_360px] xl:items-start">
        <div className="grid gap-5">
          <div className="grid gap-5 xl:grid-cols-[minmax(0,1.05fr)_minmax(0,0.95fr)]">
            <Panel
              title="Prompt"
              actions={
                <div className="flex flex-wrap gap-2">
                  <PrimaryButton type="button" disabled={!task.prompt.trim() || task.running} onClick={() => void task.start({ provider: "minimax", toolId: "aiMusic", prompt: task.prompt, lyrics, style })}>
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
                value={style}
                onChange={(event) => setStyle(event.target.value)}
                className="mt-3"
                placeholder="Style descriptor"
              />
              <div className="mt-3 flex flex-wrap gap-2 text-[12px] text-[var(--app-text-muted)]">
                <PillTag tone="neutral">Style</PillTag>
                <PillTag tone="accent">{style}</PillTag>
              </div>
            </Panel>
            <Panel title="Lyrics">
              <TextArea value={lyrics} onChange={(event) => setLyrics(event.target.value)} placeholder="Optional lyrics" className="min-h-56" />
              <div className="mt-3 flex flex-wrap gap-2 text-[12px] text-[var(--app-text-muted)]">
                <PillTag tone={lyrics.trim() ? "success" : "neutral"}>{lyrics.trim() ? "Lyrics attached" : "Instrumental"}</PillTag>
              </div>
            </Panel>
          </div>
        </div>

        <div className="grid gap-5 xl:sticky xl:top-0">
          <Panel title="Execution" actions={<TaskStateTag state={taskState} label={task.status.split(" · ")[0] || "Idle"} />}>
            <WorkflowSteps steps={task.steps} emptyTitle="No music run yet" emptyDescription="Execution stages and artifact milestones will appear here once generation starts." />
          </Panel>
          <Panel title="Artifact" actions={task.artifact ? <PillTag tone="accent">Music</PillTag> : undefined}>
            <ArtifactCard artifact={task.artifact} summary={task.artifactSummary} />
          </Panel>
        </div>
      </div>
    </ToolLayout>
  );
}
