import { useState } from "react";
import type { JsonToolResult } from "@codetool/shared";
import { getApi } from "../../api";
import { Panel, PrimaryButton, SecondaryButton, StatusStrip, TextArea, ToolLayout } from "../../components/tool-layout";

export function JsonToolPage(): JSX.Element {
  const [input, setInput] = useState('{"hello":"world","items":[1,2,3]}');
  const [result, setResult] = useState<JsonToolResult | null>(null);

  async function run(mode: "format" | "minify" | "validate"): Promise<void> {
    const next = await getApi().tools.runJsonTool({ text: input, mode });
    setResult(next);
    if (next.ok && mode !== "validate") setInput(next.output);
  }

  return (
    <ToolLayout title="JSON Tool" description="Format, minify, validate, and collect structural stats for JSON data.">
      <div className="grid gap-4 xl:grid-cols-2">
        <Panel title="Input">
          <TextArea value={input} onChange={(event) => setInput(event.target.value)} />
          <div className="mt-3 flex flex-wrap gap-2">
            <PrimaryButton type="button" onClick={() => void run("format")}>
              Format
            </PrimaryButton>
            <SecondaryButton type="button" onClick={() => void run("minify")}>
              Minify
            </SecondaryButton>
            <SecondaryButton type="button" onClick={() => void run("validate")}>
              Validate
            </SecondaryButton>
          </div>
        </Panel>
        <Panel title="Result">
          <TextArea readOnly value={result?.output ?? ""} placeholder="Run the tool to see output" />
          {result ? (
            <div className="mt-3">
              <StatusStrip>
                {result.ok
                  ? `valid · ${result.stats?.keys ?? 0} keys · ${result.stats?.objects ?? 0} objects · depth ${result.stats?.maxDepth ?? 0}`
                  : result.error}
              </StatusStrip>
            </div>
          ) : null}
        </Panel>
      </div>
    </ToolLayout>
  );
}
