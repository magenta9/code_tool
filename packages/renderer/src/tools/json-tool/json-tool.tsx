import { useState } from "react";
import type { JsonToolResult } from "@codetool/shared";
import { Braces, CheckCircle2, Minimize2 } from "lucide-react";
import { getApi } from "../../api";
import { ActionButton, Panel, StatusStrip, TextArea, ToolLayout } from "../../components/tool-layout";

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
      <div className="grid gap-5 xl:grid-cols-[minmax(0,1.08fr)_minmax(360px,0.92fr)] xl:items-start">
        <Panel
          title="Input"
          actions={
            <div className="flex flex-wrap gap-2">
              <ActionButton type="button" onClick={() => void run("format")}>
                <Braces size={14} /> Format
              </ActionButton>
              <ActionButton type="button" onClick={() => void run("minify")}>
                <Minimize2 size={14} /> Minify
              </ActionButton>
              <ActionButton type="button" onClick={() => void run("validate")}>
                <CheckCircle2 size={14} /> Validate
              </ActionButton>
            </div>
          }
        >
          <TextArea spellCheck={false} value={input} onChange={(event) => setInput(event.target.value)} />
        </Panel>
        <Panel
          title="Result"
          actions={
            <span className="rounded-full border border-[var(--app-border)] bg-[var(--app-bg-muted)] px-2.5 py-1 text-[10px] font-medium uppercase tracking-[0.14em] text-[var(--app-text-muted)]">
              Read only
            </span>
          }
          className="xl:sticky xl:top-0"
        >
          <TextArea
            readOnly
            spellCheck={false}
            value={result?.output ?? ""}
            placeholder="Run Format, Minify, or Validate to inspect the JSON output."
          />
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
