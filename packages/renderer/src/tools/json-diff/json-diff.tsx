import { useState } from "react";
import type { JsonDiffResult } from "@codetool/shared";
import { getApi } from "../../api";
import { CodeBlock, Panel, PrimaryButton, StatusStrip, TextArea, ToolLayout } from "../../components/tool-layout";

export function JsonDiffPage(): JSX.Element {
  const [left, setLeft] = useState('{"name":"CodeTool","count":1}');
  const [right, setRight] = useState('{"name":"CodeTool","count":2,"local":true}');
  const [result, setResult] = useState<JsonDiffResult | null>(null);

  return (
    <ToolLayout
      title="JSON Diff"
      description="Compare two JSON documents and inspect changed structural paths."
      actions={
        <PrimaryButton type="button" onClick={async () => setResult(await getApi().tools.runJsonDiff({ left, right }))}>
          Compare
        </PrimaryButton>
      }
    >
      <div className="grid gap-5 xl:grid-cols-2">
        <Panel title="Left">
          <TextArea spellCheck={false} value={left} onChange={(event) => setLeft(event.target.value)} />
        </Panel>
        <Panel title="Right">
          <TextArea spellCheck={false} value={right} onChange={(event) => setRight(event.target.value)} />
        </Panel>
      </div>
      {result ? (
        <Panel title="Changes">
          <StatusStrip>
            {result.ok
              ? `${result.changes.length} changes · added ${result.summary.added} · removed ${result.summary.removed} · modified ${result.summary.modified}`
              : result.error}
          </StatusStrip>
          <div className="mt-3 grid gap-2">
            {result.changes.map((change) => (
              <CodeBlock key={`${change.kind}:${change.path}`} className="text-[12px] leading-5 text-[#cbd4c8]">
                <span className="text-[#d1ff4a]">{change.kind}</span> {change.path}
              </CodeBlock>
            ))}
          </div>
        </Panel>
      ) : null}
    </ToolLayout>
  );
}
