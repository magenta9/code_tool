import { useAiTask } from "../shared/use-ai-task";
import { CodeBlock, Panel, PrimaryButton, SecondaryButton, StatusStrip, TextArea, ToolLayout } from "../../components/tool-layout";

export function AiChatPage(): JSX.Element {
  const task = useAiTask();

  return (
    <ToolLayout title="AI Chat" description="Create MiniMax chat tasks and stream deltas through the shared execution strip.">
      <Panel
        title="Prompt"
        actions={
          <div className="flex flex-wrap gap-2">
            <PrimaryButton type="button" disabled={!task.prompt.trim() || task.running} onClick={() => void task.start({ provider: "minimax", toolId: "aiChat", prompt: task.prompt })}>
              Send
            </PrimaryButton>
            <SecondaryButton type="button" disabled={!task.running} onClick={() => void task.cancel()}>
              Cancel
            </SecondaryButton>
          </div>
        }
      >
        <TextArea value={task.prompt} onChange={(event) => task.setPrompt(event.target.value)} placeholder="Ask MiniMax..." />
      </Panel>
      <Panel title="Assistant">
        <StatusStrip>{task.status}</StatusStrip>
        <CodeBlock className="mt-3 min-h-56">{task.output}</CodeBlock>
      </Panel>
    </ToolLayout>
  );
}
