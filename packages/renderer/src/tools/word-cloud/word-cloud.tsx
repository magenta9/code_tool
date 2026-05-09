import { useState } from "react";
import type { WordCloudResult } from "@codetool/shared";
import { getApi } from "../../api";
import { Panel, PrimaryButton, TextArea, ToolLayout } from "../../components/tool-layout";

export function WordCloudPage(): JSX.Element {
  const [text, setText] = useState("CodeTool code tool electron react minimax code code diagnostics");
  const [result, setResult] = useState<WordCloudResult | null>(null);

  return (
    <ToolLayout title="Word Cloud" description="Tokenize text, remove common stop words, and rank terms deterministically.">
      <div className="grid gap-4 xl:grid-cols-[1fr_420px]">
        <Panel title="Text">
          <TextArea value={text} onChange={(event) => setText(event.target.value)} />
          <div className="mt-3">
            <PrimaryButton type="button" onClick={async () => setResult(await getApi().tools.analyzeWordCloud({ text }))}>
              Analyze
            </PrimaryButton>
          </div>
        </Panel>
        <Panel title="Tokens">
          <div className="grid min-h-64 content-start gap-2">
            {(result?.tokens ?? []).map((token) => (
              <div key={token.text} className="grid grid-cols-[1fr_64px] items-center gap-3 rounded-[8px] bg-[#050607] px-3 py-2">
                <div className="min-w-0">
                  <div className="truncate text-[13px] font-medium text-[#e8ece7]">{token.text}</div>
                  <div className="mt-1 h-1.5 overflow-hidden rounded-full bg-white/[0.07]">
                    <div className="h-full rounded-full bg-[#d1ff4a]" style={{ width: `${Math.max(8, token.weight * 100)}%` }} />
                  </div>
                </div>
                <div className="font-mono text-[13px] text-[#d1ff4a]">{token.count}</div>
              </div>
            ))}
          </div>
        </Panel>
      </div>
    </ToolLayout>
  );
}
