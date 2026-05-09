import { useState } from "react";
import type { TimestampConversionResult } from "@codetool/shared";
import { getApi } from "../../api";
import { Panel, PrimaryButton, StatusStrip, ToolLayout } from "../../components/tool-layout";

export function TimestampConverterPage(): JSX.Element {
  const [value, setValue] = useState(String(Date.now()));
  const [timezone, setTimezone] = useState(Intl.DateTimeFormat().resolvedOptions().timeZone || "UTC");
  const [result, setResult] = useState<TimestampConversionResult | null>(null);

  return (
    <ToolLayout title="Timestamp Converter" description="Convert seconds, milliseconds, ISO strings, and local date input.">
      <Panel title="Convert">
        <div className="grid gap-3 md:grid-cols-[1fr_220px_auto]">
          <input
            value={value}
            onChange={(event) => setValue(event.target.value)}
            className="h-10 rounded-[8px] bg-[#050607] px-3 font-mono text-[13px] outline-none shadow-[inset_0_0_0_1px_rgba(255,255,255,0.08)]"
          />
          <input
            value={timezone}
            onChange={(event) => setTimezone(event.target.value)}
            className="h-10 rounded-[8px] bg-[#050607] px-3 text-[13px] outline-none shadow-[inset_0_0_0_1px_rgba(255,255,255,0.08)]"
          />
          <PrimaryButton type="button" onClick={async () => setResult(await getApi().tools.convertTimestamp({ value, timezone }))}>
            Convert
          </PrimaryButton>
        </div>
        {result ? (
          <div className="mt-4 grid gap-2">
            <StatusStrip>{result.ok ? `${result.inputKind} · ${result.timezone}` : result.error}</StatusStrip>
            {result.ok ? (
              <pre className="rounded-[8px] bg-[#050607] p-3 font-mono text-[13px] leading-6 text-[#dce2d9]">{`ISO: ${result.iso}
Local: ${result.local}
Seconds: ${result.unixSeconds}
Milliseconds: ${result.unixMilliseconds}`}</pre>
            ) : null}
          </div>
        ) : null}
      </Panel>
    </ToolLayout>
  );
}
