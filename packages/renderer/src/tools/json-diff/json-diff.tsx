import { useState } from "react";
import type { JsonDiffResult } from "@codetool/shared";
import { getApi } from "../../api";
import { Panel, PrimaryButton, StatusStrip, TextArea, ToolLayout } from "../../components/tool-layout";

export function JsonDiffPage(): JSX.Element {
  const [left, setLeft] = useState('{"name":"CodeTool","count":1}');
  const [right, setRight] = useState('{"name":"CodeTool","count":2,"electron":true}');
  const [result, setResult] = useState<JsonDiffResult | null>(null);

  return (
    <ToolLayout title="JSON Diff" description="Compare two JSON documents and inspect changed structural paths.">
      <div className="grid gap-4 xl:grid-cols-2">
        <Panel title="Left">
          <TextArea value={left} onChange={(event) => setLeft(event.target.value)} />
        </Panel>
        <Panel title="Right">
          <TextArea value={right} onChange={(event) => setRight(event.target.value)} />
        </Panel>
      </div>
      <div className="mt-4 flex justify-end">
        <PrimaryButton type="button" onClick={async () => setResult(await getApi().tools.runJsonDiff({ left, right }))}>
          Compare
        </PrimaryButton>
      </div>
      {result ? (
        <Panel title="Changes" className="mt-4">
          <StatusStrip>
            {result.ok
              ? `${result.changes.length} changes · added ${result.summary.added} · removed ${result.summary.removed} · modified ${result.summary.modified}`
              : result.error}
          </StatusStrip>
          <div className="mt-3 grid gap-2">
            {result.changes.map((change) => (
              <div key={`${change.kind}:${change.path}`} className="rounded-[8px] bg-[#050607] p-3 font-mono text-[12px] text-[#cbd4c8]">
                <span className="text-[#d1ff4a]">{change.kind}</span> {change.path}
              </div>
            ))}
          </div>
        </Panel>
      ) : null}
    </ToolLayout>
  );
}
