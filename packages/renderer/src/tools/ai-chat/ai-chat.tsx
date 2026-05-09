import { useAiTask } from "../shared/use-ai-task";
import { Panel, PrimaryButton, SecondaryButton, StatusStrip, TextArea, ToolLayout } from "../../components/tool-layout";

export function AiChatPage(): JSX.Element {
  const task = useAiTask();

  return (
    <ToolLayout title="AI Chat" description="Create MiniMax chat tasks and stream deltas through the shared execution strip.">
      <Panel title="Prompt">
        <TextArea value={task.prompt} onChange={(event) => task.setPrompt(event.target.value)} placeholder="Ask MiniMax..." />
        <div className="mt-3 flex gap-2">
          <PrimaryButton type="button" disabled={!task.prompt.trim() || task.running} onClick={() => void task.start({ provider: "minimax", toolId: "aiChat", prompt: task.prompt })}>
            Send
          </PrimaryButton>
          <SecondaryButton type="button" disabled={!task.running} onClick={() => void task.cancel()}>
            Cancel
          </SecondaryButton>
        </div>
      </Panel>
      <Panel title="Assistant" className="mt-4">
        <StatusStrip>{task.status}</StatusStrip>
        <pre className="mt-3 min-h-56 whitespace-pre-wrap rounded-[8px] bg-[#050607] p-3 text-[13px] leading-5 text-[#dce2d9]">{task.output}</pre>
      </Panel>
    </ToolLayout>
  );
}
