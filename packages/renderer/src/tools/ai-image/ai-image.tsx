import { useState } from "react";
import type { AiTaskRequest } from "@codetool/shared";
import { useAiTask } from "../shared/use-ai-task";
import { Panel, PrimaryButton, SecondaryButton, StatusStrip, TextArea, ToolLayout } from "../../components/tool-layout";

export function AiImagePage(): JSX.Element {
  const [aspectRatio, setAspectRatio] = useState<Extract<AiTaskRequest, { toolId: "aiImage" }>["aspectRatio"]>("1:1");
  const [count, setCount] = useState(1);
  const task = useAiTask("A precise desktop utility workbench in a cold code lab.");

  return (
    <ToolLayout title="AI Image" description="Submit MiniMax image prompts with aspect settings and store resulting assets through main.">
      <Panel title="Image request">
        <TextArea value={task.prompt} onChange={(event) => task.setPrompt(event.target.value)} />
        <div className="mt-3 grid gap-2 md:grid-cols-[180px_120px_auto_auto]">
          <select
            value={aspectRatio}
            onChange={(event) => setAspectRatio(event.target.value as typeof aspectRatio)}
            className="h-10 rounded-[8px] bg-[#050607] px-3 text-[13px] outline-none shadow-[inset_0_0_0_1px_rgba(255,255,255,0.08)]"
          >
            <option value="1:1">1:1</option>
            <option value="16:9">16:9</option>
            <option value="9:16">9:16</option>
            <option value="4:3">4:3</option>
            <option value="3:4">3:4</option>
          </select>
          <input
            value={count}
            min={1}
            max={4}
            type="number"
            onChange={(event) => setCount(Number(event.target.value))}
            className="h-10 rounded-[8px] bg-[#050607] px-3 text-[13px] outline-none shadow-[inset_0_0_0_1px_rgba(255,255,255,0.08)]"
          />
          <PrimaryButton type="button" disabled={!task.prompt.trim() || task.running} onClick={() => void task.start({ provider: "minimax", toolId: "aiImage", prompt: task.prompt, aspectRatio, count })}>
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
