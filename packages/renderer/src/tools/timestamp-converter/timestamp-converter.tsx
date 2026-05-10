import { useState } from "react";
import type { TimestampConversionResult } from "@codetool/shared";
import { getApi } from "../../api";
import { CodeBlock, Panel, PrimaryButton, StatusStrip, TextInput, ToolLayout } from "../../components/tool-layout";

export function TimestampConverterPage(): JSX.Element {
  const [value, setValue] = useState(String(Date.now()));
  const [timezone, setTimezone] = useState(Intl.DateTimeFormat().resolvedOptions().timeZone || "UTC");
  const [result, setResult] = useState<TimestampConversionResult | null>(null);

  return (
    <ToolLayout
      title="Timestamp Converter"
      description="Convert seconds, milliseconds, ISO strings, and local date input."
      actions={
        <PrimaryButton type="button" onClick={async () => setResult(await getApi().tools.convertTimestamp({ value, timezone }))}>
          Convert
        </PrimaryButton>
      }
    >
      <Panel title="Convert">
        <div className="grid gap-3 md:grid-cols-[minmax(0,1fr)_240px]">
          <TextInput
            value={value}
            onChange={(event) => setValue(event.target.value)}
            className="font-mono"
            placeholder="Milliseconds, seconds, ISO, or local date"
          />
          <TextInput
            value={timezone}
            onChange={(event) => setTimezone(event.target.value)}
            placeholder="Timezone"
          />
        </div>
        {result ? (
          <div className="mt-4 grid gap-2">
            <StatusStrip>{result.ok ? `${result.inputKind} · ${result.timezone}` : result.error}</StatusStrip>
            {result.ok ? (
              <CodeBlock>{`ISO: ${result.iso}
Local: ${result.local}
Seconds: ${result.unixSeconds}
Milliseconds: ${result.unixMilliseconds}`}</CodeBlock>
            ) : null}
          </div>
        ) : null}
      </Panel>
    </ToolLayout>
  );
}
