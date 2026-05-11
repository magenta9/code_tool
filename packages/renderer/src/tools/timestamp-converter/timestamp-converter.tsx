import { useEffect, useState } from "react";
import type { TimestampConversionResult } from "@codetool/shared";
import { CalendarClock, Clock3, RefreshCw } from "lucide-react";
import { getApi } from "../../api";
import { ActionButton, Panel, StatusStrip, TextInput, ToolLayout } from "../../components/tool-layout";

export function TimestampConverterPage(): JSX.Element {
  const [value, setValue] = useState(String(Date.now()));
  const [timezone, setTimezone] = useState(Intl.DateTimeFormat().resolvedOptions().timeZone || "UTC");
  const [nowMilliseconds, setNowMilliseconds] = useState(Date.now());
  const [result, setResult] = useState<TimestampConversionResult | null>(null);
  const [resultInput, setResultInput] = useState("");

  useEffect(() => {
    const interval = window.setInterval(() => setNowMilliseconds(Date.now()), 1000);
    return () => window.clearInterval(interval);
  }, []);

  async function convert(nextValue = value, nextTimezone = timezone): Promise<void> {
    setResultInput(nextValue);
    setResult(await getApi().tools.convertTimestamp({ value: nextValue, timezone: nextTimezone }));
  }

  function useCurrentTimestamp(unit: "seconds" | "milliseconds"): void {
    const current = Date.now();
    const nextValue = unit === "seconds" ? String(Math.floor(current / 1000)) : String(current);
    setValue(nextValue);
    void convert(nextValue);
  }

  return (
    <ToolLayout
      title="Timestamp Converter"
      description="Convert current time, Unix seconds, Unix milliseconds, ISO strings, and RFC date formats."
      actions={
        <ActionButton type="button" variant="primary" onClick={() => void convert()}>
          <Clock3 size={14} /> Convert
        </ActionButton>
      }
    >
      <div className="grid gap-5 xl:grid-cols-[360px_minmax(0,1fr)]">
        <Panel
          title="Current timestamp"
          actions={
            <ActionButton type="button" onClick={() => useCurrentTimestamp("milliseconds")}>
              <RefreshCw size={14} /> Use now
            </ActionButton>
          }
        >
          <div className="grid gap-3">
            <MetricBlock label="Unix seconds" value={String(Math.floor(nowMilliseconds / 1000))} />
            <MetricBlock label="Unix milliseconds" value={String(nowMilliseconds)} />
            <MetricBlock label="RFC3339 / ISO" value={new Date(nowMilliseconds).toISOString()} />
          </div>
          <div className="mt-3 flex flex-wrap gap-2">
            <ActionButton type="button" onClick={() => useCurrentTimestamp("seconds")}>Use seconds</ActionButton>
            <ActionButton type="button" onClick={() => useCurrentTimestamp("milliseconds")}>Use milliseconds</ActionButton>
          </div>
        </Panel>

        <Panel title="Convert input">
          <div className="grid gap-3 md:grid-cols-[minmax(0,1fr)_240px]">
            <TextInput
              value={value}
              onChange={(event) => setValue(event.target.value)}
              className="font-mono"
              placeholder="10-digit seconds, 13-digit milliseconds, ISO, or RFC date"
            />
            <TextInput
              value={timezone}
              onChange={(event) => setTimezone(event.target.value)}
              placeholder="Timezone, e.g. Asia/Shanghai"
            />
          </div>
          <div className="mt-3 flex flex-wrap gap-2 text-[11px] text-[var(--ui-text-muted)]">
            <HintPill>10 digits auto-read as seconds</HintPill>
            <HintPill>13 digits auto-read as milliseconds</HintPill>
            <HintPill>RFC / ISO date strings supported</HintPill>
          </div>
        </Panel>
      </div>

      {result ? (
        <Panel title="Result">
          <StatusStrip>{result.ok ? `${detectedInputLabel(result, resultInput)} · ${result.timezone}` : result.error}</StatusStrip>
          {result.ok ? <TimestampResult result={result} /> : null}
        </Panel>
      ) : null}
    </ToolLayout>
  );
}

function TimestampResult({ result }: { result: TimestampConversionResult }): JSX.Element {
  return (
    <div className="mt-4 grid gap-3 xl:grid-cols-2">
      <ResultSection title="Unix">
        <ResultLine label="Seconds" value={formatValue(result.unixSeconds)} />
        <ResultLine label="Milliseconds" value={formatValue(result.unixMilliseconds)} />
      </ResultSection>
      <ResultSection title="Local and UTC">
        <ResultLine label="Local" value={formatValue(result.local)} />
        <ResultLine label="UTC" value={formatValue(result.utc)} />
      </ResultSection>
      <ResultSection title="RFC and ISO" className="xl:col-span-2">
        <ResultLine label="RFC3339 / ISO 8601" value={formatValue(result.rfc3339 ?? result.iso)} />
        <ResultLine label="RFC2822" value={formatValue(result.rfc2822)} />
        <ResultLine label="RFC7231 / HTTP-date" value={formatValue(result.rfc7231)} />
      </ResultSection>
    </div>
  );
}

function MetricBlock({ label, value }: { label: string; value: string }): JSX.Element {
  return (
    <div className="rounded-[8px] border border-[var(--ui-border)] bg-[var(--ui-surface-soft)] px-3.5 py-3">
      <div className="text-[11px] font-semibold uppercase tracking-[0.12em] text-[var(--ui-text-muted)]">{label}</div>
      <div className="mt-1.5 break-all font-mono text-[13px] leading-5 text-[var(--ui-text)]">{value}</div>
    </div>
  );
}

function HintPill({ children }: { children: string }): JSX.Element {
  return <span className="rounded-[6px] border border-[var(--ui-border)] bg-[var(--ui-surface-soft)] px-2 py-1">{children}</span>;
}

function ResultSection({ title, className = "", children }: { title: string; className?: string; children: JSX.Element | JSX.Element[] }): JSX.Element {
  return (
    <section className={`rounded-[8px] border border-[var(--ui-border)] bg-[var(--ui-surface)] p-3 shadow-[0_1px_2px_rgba(24,24,22,0.03)] ${className}`}>
      <div className="mb-2 flex items-center gap-2 text-[11px] font-semibold uppercase tracking-[0.12em] text-[var(--ui-text-muted)]">
        <CalendarClock size={13} /> {title}
      </div>
      <div className="grid gap-2">{children}</div>
    </section>
  );
}

function ResultLine({ label, value }: { label: string; value: string }): JSX.Element {
  return (
    <div className="grid gap-1 rounded-[7px] bg-[var(--ui-surface-soft)] px-3 py-2 md:grid-cols-[150px_minmax(0,1fr)] md:items-start">
      <span className="text-[12px] font-medium text-[var(--ui-text-muted)]">{label}</span>
      <span className="break-all font-mono text-[12px] leading-5 text-[var(--ui-text)]">{value}</span>
    </div>
  );
}

function detectedInputLabel(result: TimestampConversionResult, input: string): string {
  const trimmed = input.trim();
  if (/^-?\d{10}$/.test(trimmed)) return "10-digit Unix seconds";
  if (/^-?\d{13}$/.test(trimmed)) return "13-digit Unix milliseconds";
  if (result.inputKind === "seconds") return "Unix seconds";
  if (result.inputKind === "milliseconds") return "Unix milliseconds";
  return "Date string";
}

function formatValue(value: string | number | undefined): string {
  return value === undefined ? "-" : String(value);
}
