import { useState } from "react";
import type { JsonDiffChange, JsonDiffResult, JsonValue } from "@codetool/shared";
import { GitCompare } from "lucide-react";
import { getApi } from "../../api";
import { ActionButton, Panel, StatusStrip, TextArea, ToolLayout } from "../../components/tool-layout";

export function JsonDiffPage(): JSX.Element {
  const [left, setLeft] = useState('{"name":"CodeTool","count":1}');
  const [right, setRight] = useState('{"name":"CodeTool","count":2,"local":true}');
  const [result, setResult] = useState<JsonDiffResult | null>(null);

  return (
    <ToolLayout
      title="JSON Diff"
      description="Compare two JSON documents and inspect changed structural paths."
      actions={
        <ActionButton type="button" onClick={async () => setResult(await getApi().tools.runJsonDiff({ left, right }))}>
          <GitCompare size={14} /> Compare
        </ActionButton>
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
              ? diffSummaryText(result)
              : result.error}
          </StatusStrip>
          {result.ok ? <DiffRows changes={result.changes} /> : null}
        </Panel>
      ) : null}
    </ToolLayout>
  );
}

function diffSummaryText(result: JsonDiffResult): string {
  const parts = [
    `added ${result.summary.added}`,
    `removed ${result.summary.removed}`,
    `modified ${result.summary.modified}`
  ];
  if (result.summary.typeChanged > 0) parts.push(`type changed ${result.summary.typeChanged}`);
  return `${result.changes.length} changes · ${parts.join(" · ")}`;
}

function DiffRows({ changes }: { changes: JsonDiffChange[] }): JSX.Element {
  if (changes.length === 0) {
    return (
      <div className="mt-3 rounded-[8px] border border-[var(--ui-border)] bg-[var(--ui-surface-soft)] px-3.5 py-3 text-[13px] text-[var(--ui-text-muted)]">
        No structural changes found.
      </div>
    );
  }

  return (
    <div className="mt-3 grid gap-2">
      {changes.map((change) => <DiffChangeBlock key={`${change.kind}:${change.path}`} change={change} />)}
    </div>
  );
}

function DiffChangeBlock({ change }: { change: JsonDiffChange }): JSX.Element {
  if (change.kind === "added") {
    return (
      <DiffShell>
        <DiffLine tone="added" marker="+" path={change.path} value={change.right} />
      </DiffShell>
    );
  }

  if (change.kind === "removed") {
    return (
      <DiffShell>
        <DiffLine tone="removed" marker="-" path={change.path} value={change.left} />
      </DiffShell>
    );
  }

  return (
    <DiffShell>
      <DiffLine tone="removed" marker="-" path={change.path} value={change.left} />
      <DiffLine tone="added" marker="+" path={change.path} value={change.right} />
    </DiffShell>
  );
}

function DiffShell({ children }: { children: JSX.Element | JSX.Element[] }): JSX.Element {
  return (
    <article className="overflow-hidden rounded-[8px] border border-[var(--ui-border)] bg-[var(--ui-surface)] shadow-[0_1px_2px_rgba(24,24,22,0.03)]">
      {children}
    </article>
  );
}

function DiffLine({ tone, marker, path, value }: { tone: "added" | "removed"; marker: "+" | "-"; path: string; value?: JsonValue }): JSX.Element {
  const toneClass =
    tone === "added"
      ? "bg-[rgba(32,180,134,0.075)]"
      : "bg-[rgba(194,65,45,0.065)]";
  const markerClass = tone === "added" ? "text-[#157b61]" : "text-[#a73424]";

  return (
    <div className={`grid grid-cols-[24px_minmax(110px,0.28fr)_minmax(0,1fr)] items-start gap-2 border-t border-t-[var(--ui-border)] px-3 py-2 first:border-t-0 ${toneClass}`}>
      <span className={`select-none font-mono text-[13px] font-semibold leading-5 ${markerClass}`}>{marker}</span>
      <span className="font-mono text-[12px] leading-5 text-[var(--ui-text-muted)]">{path}</span>
      <pre className="m-0 whitespace-pre-wrap font-mono text-[12px] leading-5 text-[var(--ui-text)]">{formatJsonValue(value)}</pre>
    </div>
  );
}

function formatJsonValue(value: JsonValue | undefined): string {
  if (value === undefined) return "undefined";
  if (typeof value === "string") return JSON.stringify(value);
  return JSON.stringify(value, null, 2);
}
