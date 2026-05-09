import { useState } from "react";
import { useAiTask } from "../shared/use-ai-task";
import { CodeBlock, Panel, PrimaryButton, SecondaryButton, StatusStrip, TextArea, TextInput, ToolLayout } from "../../components/tool-layout";

export function AiSpeechPage(): JSX.Element {
  const [voiceId, setVoiceId] = useState("male-qn-qingse");
  const task = useAiTask("Text for MiniMax speech generation.");

  return (
    <ToolLayout title="AI Speech" description="Generate speech tasks with MiniMax and persist audio artifacts in main-process storage.">
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
        <TextArea value={task.prompt} onChange={(event) => task.setPrompt(event.target.value)} />
        <TextInput
          value={voiceId}
          onChange={(event) => setVoiceId(event.target.value)}
          className="mt-3"
          placeholder="Voice ID"
        />
      </Panel>
      <Panel title="Execution">
        <StatusStrip>{task.status}</StatusStrip>
        <CodeBlock className="mt-3 text-[12px] text-[#9da69b]">{task.artifactSummary}</CodeBlock>
      </Panel>
    </ToolLayout>
  );
}
