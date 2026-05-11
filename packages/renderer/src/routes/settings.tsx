import { useEffect, useState } from "react";
import type { KanbanBoard, KanbanBoardExport, MiniMaxProviderStatus } from "@codetool/shared";
import { Download, Save, Trash2, Upload, X } from "lucide-react";
import { getApi } from "../api";
import { ActionButton, Panel, SelectField, TextArea, TextInput, ToolLayout } from "../components/tool-layout";

export function SettingsPage(): JSX.Element {
  const [status, setStatus] = useState<MiniMaxProviderStatus | null>(null);
  const [key, setKey] = useState("");
  const [message, setMessage] = useState("Loading MiniMax status");
  const [boards, setBoards] = useState<KanbanBoard[]>([]);
  const [selectedBoardId, setSelectedBoardId] = useState("");
  const [kanbanExport, setKanbanExport] = useState("");
  const [kanbanImport, setKanbanImport] = useState("");
  const [kanbanMessage, setKanbanMessage] = useState("Loading boards");

  async function refresh(): Promise<void> {
    const next = await getApi().secrets.getMiniMaxStatus();
    setStatus(next);
    setMessage(next.configured ? `MiniMax configured: ${next.maskedKey}` : "MiniMax API key is not configured.");
  }

  async function refreshBoards(nextSelectedId = selectedBoardId): Promise<void> {
    const nextBoards = await getApi().kanban.listBoards();
    setBoards(nextBoards);
    const validSelectedId = nextSelectedId && nextBoards.some((board) => board.id === nextSelectedId) ? nextSelectedId : nextBoards[0]?.id ?? "";
    setSelectedBoardId(validSelectedId);
    setKanbanMessage(nextBoards.length === 0 ? "Create a Kanban board before exporting." : `${nextBoards.length} board${nextBoards.length === 1 ? "" : "s"} available.`);
  }

  useEffect(() => {
    void Promise.all([refresh(), refreshBoards()]).catch((error) => {
      const text = error instanceof Error ? error.message : "Unable to load settings.";
      setMessage(text);
      setKanbanMessage(text);
    });
  }, []);

  async function exportBoard(): Promise<void> {
    if (!selectedBoardId) return;
    try {
      const payload = await getApi().kanban.exportBoard({ boardId: selectedBoardId });
      const text = JSON.stringify(payload, null, 2);
      setKanbanExport(text);
      if (navigator.clipboard) {
        await navigator.clipboard.writeText(text);
        setKanbanMessage("Board JSON exported and copied to clipboard.");
      } else {
        setKanbanMessage("Board JSON exported.");
      }
    } catch (error) {
      setKanbanMessage(error instanceof Error ? error.message : "Unable to export board.");
    }
  }

  async function importBoard(): Promise<void> {
    try {
      const payload = JSON.parse(kanbanImport) as KanbanBoardExport;
      const board = await getApi().kanban.importBoard({ payload });
      setKanbanImport("");
      setKanbanMessage(`Imported board: ${board.name}`);
      await refreshBoards(board.id);
    } catch (error) {
      setKanbanMessage(error instanceof Error ? error.message : "Unable to import board.");
    }
  }

  return (
    <ToolLayout title="Settings" description="Provider secrets stay in the main process and are stored through macOS Keychain/keytar.">
      <Panel title="MiniMax">
        <div className="grid gap-3 md:grid-cols-[1fr_auto]">
          <TextInput
            value={key}
            onChange={(event) => setKey(event.target.value)}
            type="password"
            placeholder={status?.configured ? "Enter a new key to replace current value" : "MiniMax API key"}
          />
          <div className="flex gap-2">
            <ActionButton
              type="button"
              variant="primary"
              disabled={!key.trim()}
              onClick={async () => {
                const next = await getApi().secrets.saveMiniMaxKey({ apiKey: key });
                setStatus(next);
                setKey("");
                setMessage(`Saved MiniMax key: ${next.maskedKey}`);
              }}
            >
              <Save size={14} /> Save key
            </ActionButton>
            <ActionButton
              type="button"
              variant="danger"
              onClick={async () => {
                const next = await getApi().secrets.clearMiniMaxKey();
                setStatus(next);
                setMessage("MiniMax key cleared.");
              }}
            >
              <Trash2 size={14} /> Clear
            </ActionButton>
          </div>
        </div>
        <p className="mt-3 text-[12px] text-[var(--app-text-muted)]">{message}</p>
      </Panel>
      <Panel title="Kanban data">
        <div className="grid gap-4 lg:grid-cols-2">
          <div className="grid gap-3">
            <SelectField value={selectedBoardId} onChange={(event) => setSelectedBoardId(event.target.value)} disabled={boards.length === 0}>
              {boards.length === 0 ? <option value="">No boards available</option> : null}
              {boards.map((board) => <option key={board.id} value={board.id}>{board.name}</option>)}
            </SelectField>
            <div className="flex flex-wrap gap-2">
              <ActionButton type="button" onClick={() => void exportBoard()} disabled={!selectedBoardId}><Download size={14} /> Export selected board</ActionButton>
              <ActionButton type="button" onClick={() => setKanbanExport("")} disabled={!kanbanExport}><X size={14} /> Clear export</ActionButton>
            </div>
            <TextArea readOnly value={kanbanExport} placeholder="Exported board JSON appears here" className="min-h-48" />
          </div>
          <div className="grid gap-3">
            <TextArea value={kanbanImport} onChange={(event) => setKanbanImport(event.target.value)} placeholder="Paste board JSON to import" className="min-h-48" />
            <div className="flex flex-wrap gap-2">
              <ActionButton type="button" variant="primary" onClick={() => void importBoard()} disabled={!kanbanImport.trim()}><Upload size={14} /> Import board</ActionButton>
              <ActionButton type="button" onClick={() => setKanbanImport("")} disabled={!kanbanImport}><X size={14} /> Clear import</ActionButton>
            </div>
          </div>
        </div>
        <p className="mt-3 text-[12px] text-[var(--app-text-muted)]">{kanbanMessage}</p>
      </Panel>
    </ToolLayout>
  );
}
