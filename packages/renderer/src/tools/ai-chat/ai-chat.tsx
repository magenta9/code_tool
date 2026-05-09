import { useAiTask } from "../shared/use-ai-task";
import { ArtifactCard, MessageBubble, resolveTaskState, TaskStateTag, WorkflowSteps } from "../../components/ai-task-chrome";
import { Panel, PillTag, PrimaryButton, SecondaryButton, TextArea, ToolLayout } from "../../components/tool-layout";

export function AiChatPage(): JSX.Element {
  const task = useAiTask();
  const taskState = resolveTaskState(task.status, task.running);

  return (
    <ToolLayout title="AI Chat" description="Create MiniMax chat tasks and stream deltas through the shared execution strip.">
      <div className="grid gap-6 xl:grid-cols-[minmax(0,1fr)_360px] xl:items-start">
        <div className="grid gap-5">
          <Panel
            title="Conversation"
            actions={
              <div className="flex flex-wrap gap-2">
                <PillTag tone="accent">MiniMax</PillTag>
                <TaskStateTag state={taskState} label={task.running ? "Streaming" : "Ready"} />
              </div>
            }
            className="overflow-hidden"
          >
            <div className="space-y-4">
              {task.submittedPrompt ? (
                <MessageBubble role="user" title="You" caption="Submitted prompt" tags={<PillTag tone="accent">Request</PillTag>}>
                  {task.submittedPrompt}
                </MessageBubble>
              ) : (
                <div className="rounded-[8px] border border-dashed border-[var(--app-border)] bg-[var(--app-bg-muted)] px-5 py-8 text-center text-[13px] leading-6 text-[var(--app-text-muted)]">
                  Draft a prompt below to start a streaming MiniMax conversation.
                </div>
              )}
              <MessageBubble
                role="assistant"
                title="Assistant"
                caption={task.status}
                tags={
                  <>
                    <PillTag tone="neutral">Output</PillTag>
                    {task.output ? <PillTag tone="success">Live</PillTag> : null}
                  </>
                }
                streaming={task.running}
              >
                {task.output || "The assistant response will stream here once the task starts."}
              </MessageBubble>
            </div>
          </Panel>

          <Panel
            title="Composer"
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
            <TextArea value={task.prompt} onChange={(event) => task.setPrompt(event.target.value)} placeholder="Ask MiniMax..." className="min-h-40" />
            <div className="mt-3 flex flex-wrap items-center gap-2 text-[12px] text-[var(--app-text-muted)]">
              <PillTag tone="neutral">Streaming</PillTag>
              <PillTag tone="neutral">Desktop workspace</PillTag>
              <span>Prompt, status, workflow and artifact summary stay in one place.</span>
            </div>
          </Panel>
        </div>

        <div className="grid gap-5 xl:sticky xl:top-0">
          <Panel title="Workflow" actions={<PillTag tone="accent">{task.steps.length}</PillTag>}>
            <WorkflowSteps steps={task.steps} emptyTitle="No tool calls yet" emptyDescription="Queued, provider setup, request and artifact stages will appear here in a LobeHub-style workflow rail." />
          </Panel>
          <Panel title="Artifact" actions={<TaskStateTag state={taskState} label={task.status.split(" · ")[0] || "Idle"} />}>
            <ArtifactCard artifact={task.artifact} summary={task.artifactSummary} />
          </Panel>
        </div>
      </div>
    </ToolLayout>
  );
}
