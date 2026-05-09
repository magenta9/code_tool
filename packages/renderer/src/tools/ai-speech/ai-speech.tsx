import { useState } from "react";
import { useAiTask } from "../shared/use-ai-task";
import { Panel, PrimaryButton, SecondaryButton, StatusStrip, TextArea, ToolLayout } from "../../components/tool-layout";

export function AiSpeechPage(): JSX.Element {
  const [voiceId, setVoiceId] = useState("male-qn-qingse");
  const task = useAiTask("Text for MiniMax speech generation.");

  return (
    <ToolLayout title="AI Speech" description="Generate speech tasks with MiniMax and persist audio artifacts in main-process storage.">
      <Panel title="Speech request">
        <TextArea value={task.prompt} onChange={(event) => task.setPrompt(event.target.value)} />
        <input
          value={voiceId}
          onChange={(event) => setVoiceId(event.target.value)}
          className="mt-3 h-10 w-full rounded-[8px] bg-[#050607] px-3 text-[13px] outline-none shadow-[inset_0_0_0_1px_rgba(255,255,255,0.08)]"
        />
        <div className="mt-3 flex gap-2">
          <PrimaryButton type="button" disabled={!task.prompt.trim() || task.running} onClick={() => void task.start({ provider: "minimax", toolId: "aiSpeech", text: task.prompt, voiceId })}>
            Generate
          </PrimaryButton>
          <SecondaryButton type="button" disabled={!task.running} onClick={() => void task.cancel()}>
            Cancel
          </SecondaryButton>
        </div>
      </Panel>
      <Panel title="Execution" className="mt-4">
        <StatusStrip>{task.status}</StatusStrip>
        <pre className="mt-3 rounded-[8px] bg-[#050607] p-3 text-[12px] text-[#9da69b]">{task.artifactSummary}</pre>
      </Panel>
    </ToolLayout>
  );
}
