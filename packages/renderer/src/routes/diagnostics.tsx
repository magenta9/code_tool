import { useEffect, useState } from "react";
import type { DiagnosticEvent } from "@codetool/shared";
import { FolderOpen, RefreshCw } from "lucide-react";
import { getApi } from "../api";
import { ActionButton, Panel, ToolLayout } from "../components/tool-layout";

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
          <ActionButton type="button" onClick={() => void refresh()}>
            <RefreshCw size={14} /> Refresh
          </ActionButton>
          <ActionButton type="button" onClick={() => void getApi().log.openDirectory()}>
            <FolderOpen size={14} /> Open logs
          </ActionButton>
        </div>
      }
    >
      <Panel title="Recent events">
        <div className="grid gap-2">
          {events.length === 0 ? (
            <div className="text-[13px] text-[var(--ui-text-muted)]">No diagnostics yet.</div>
          ) : (
            events.map((event) => (
              <div key={event.id} className="rounded-[8px] border border-[var(--ui-border)] bg-[var(--ui-surface)] p-3 text-[12px] shadow-[0_1px_2px_rgba(24,24,22,0.03)]">
                <div className="flex flex-wrap items-center gap-2 text-[var(--ui-text)]">
                  <span className="font-mono text-[var(--app-danger)]">{event.level}</span>
                  <span>{event.timestamp}</span>
                  {event.referenceId ? <span className="font-mono text-[var(--ui-text-muted)]">{event.referenceId}</span> : null}
                </div>
                <div className="mt-1 text-[var(--ui-text-muted)]">{event.message}</div>
              </div>
            ))
          )}
        </div>
      </Panel>
    </ToolLayout>
  );
}
