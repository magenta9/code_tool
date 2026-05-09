import { useEffect, useState } from "react";
import type { DiagnosticEvent } from "@codetool/shared";
import { getApi } from "../api";
import { Panel, SecondaryButton, ToolLayout } from "../components/tool-layout";

export function DiagnosticsPage(): JSX.Element {
  const [events, setEvents] = useState<DiagnosticEvent[]>([]);

  async function refresh(): Promise<void> {
    setEvents(await getApi().log.list({ limit: 80 }));
  }

  useEffect(() => {
    void refresh();
  }, []);

  return (
    <ToolLayout
      title="Diagnostics"
      description="Indexed diagnostic events and reference IDs for renderer, main process, and MiniMax provider failures."
      actions={
        <div className="flex gap-2">
          <SecondaryButton type="button" onClick={() => void refresh()}>
            Refresh
          </SecondaryButton>
          <SecondaryButton type="button" onClick={() => void getApi().log.openDirectory()}>
            Open logs
          </SecondaryButton>
        </div>
      }
    >
      <Panel title="Recent events">
        <div className="grid gap-2">
          {events.length === 0 ? (
            <div className="text-[13px] text-[#8c948b]">No diagnostics yet.</div>
          ) : (
            events.map((event) => (
              <div key={event.id} className="rounded-[8px] bg-[#050607] p-3 text-[12px] shadow-[inset_0_0_0_1px_rgba(255,255,255,0.06)]">
                <div className="flex flex-wrap items-center gap-2 text-[#dce2d9]">
                  <span className="font-mono text-[#d1ff4a]">{event.level}</span>
                  <span>{event.timestamp}</span>
                  {event.referenceId ? <span className="font-mono text-[#aeb7ab]">{event.referenceId}</span> : null}
                </div>
                <div className="mt-1 text-[#9da69b]">{event.message}</div>
              </div>
            ))
          )}
        </div>
      </Panel>
    </ToolLayout>
  );
}
