import { useState } from "react";
import { useAiTask } from "../shared/use-ai-task";
import { CodeBlock, Panel, PrimaryButton, SecondaryButton, StatusStrip, TextArea, TextInput, ToolLayout } from "../../components/tool-layout";

export function AiMusicPage(): JSX.Element {
  const [lyrics, setLyrics] = useState("");
  const [style, setStyle] = useState("cinematic electronic");
  const task = useAiTask("Generate a concise instrumental theme for a code tool.");

  return (
    <ToolLayout title="AI Music" description="Run MiniMax music tasks with long-running status and failure diagnostics.">
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
          <TextArea value={task.prompt} onChange={(event) => task.setPrompt(event.target.value)} />
          <TextInput
            value={style}
            onChange={(event) => setStyle(event.target.value)}
            className="mt-3"
            placeholder="Style descriptor"
          />
        </Panel>
        <Panel title="Lyrics">
          <TextArea value={lyrics} onChange={(event) => setLyrics(event.target.value)} placeholder="Optional lyrics" />
        </Panel>
      </div>
      <Panel title="Execution">
        <StatusStrip>{task.status}</StatusStrip>
        <CodeBlock className="mt-3 text-[12px] text-[#9da69b]">{task.artifactSummary}</CodeBlock>
      </Panel>
    </ToolLayout>
  );
}
