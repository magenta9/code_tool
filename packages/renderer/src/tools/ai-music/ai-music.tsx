import { useState } from "react";
import { useAiTask } from "../shared/use-ai-task";
import { Panel, PrimaryButton, SecondaryButton, StatusStrip, TextArea, ToolLayout } from "../../components/tool-layout";

export function AiMusicPage(): JSX.Element {
  const [lyrics, setLyrics] = useState("");
  const [style, setStyle] = useState("cinematic electronic");
  const task = useAiTask("Generate a concise instrumental theme for a code tool.");

  return (
    <ToolLayout title="AI Music" description="Run MiniMax music tasks with long-running status and failure diagnostics.">
      <div className="grid gap-4 xl:grid-cols-2">
        <Panel title="Prompt">
          <TextArea value={task.prompt} onChange={(event) => task.setPrompt(event.target.value)} />
          <input
            value={style}
            onChange={(event) => setStyle(event.target.value)}
            className="mt-3 h-10 w-full rounded-[8px] bg-[#050607] px-3 text-[13px] outline-none shadow-[inset_0_0_0_1px_rgba(255,255,255,0.08)]"
          />
        </Panel>
        <Panel title="Lyrics">
          <TextArea value={lyrics} onChange={(event) => setLyrics(event.target.value)} placeholder="Optional lyrics" />
        </Panel>
      </div>
      <div className="mt-4 flex gap-2">
        <PrimaryButton type="button" disabled={!task.prompt.trim() || task.running} onClick={() => void task.start({ provider: "minimax", toolId: "aiMusic", prompt: task.prompt, lyrics, style })}>
          Generate
        </PrimaryButton>
        <SecondaryButton type="button" disabled={!task.running} onClick={() => void task.cancel()}>
          Cancel
        </SecondaryButton>
      </div>
      <Panel title="Execution" className="mt-4">
        <StatusStrip>{task.status}</StatusStrip>
        <pre className="mt-3 rounded-[8px] bg-[#050607] p-3 text-[12px] text-[#9da69b]">{task.artifactSummary}</pre>
      </Panel>
    </ToolLayout>
  );
}
