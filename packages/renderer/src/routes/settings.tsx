import { useEffect, useState } from "react";
import type { MiniMaxProviderStatus } from "@codetool/shared";
import { getApi } from "../api";
import { Panel, PrimaryButton, SecondaryButton, ToolLayout } from "../components/tool-layout";

export function SettingsPage(): JSX.Element {
  const [status, setStatus] = useState<MiniMaxProviderStatus | null>(null);
  const [key, setKey] = useState("");
  const [message, setMessage] = useState("Loading MiniMax status");

  async function refresh(): Promise<void> {
    const next = await getApi().secrets.getMiniMaxStatus();
    setStatus(next);
    setMessage(next.configured ? `MiniMax configured: ${next.maskedKey}` : "MiniMax API key is not configured.");
  }

  useEffect(() => {
    void refresh().catch((error) => setMessage(error instanceof Error ? error.message : "Unable to load settings."));
  }, []);

  return (
    <ToolLayout title="Settings" description="Provider secrets stay in the main process and are stored through macOS Keychain/keytar.">
      <Panel title="MiniMax">
        <div className="grid gap-3 md:grid-cols-[1fr_auto]">
          <input
            value={key}
            onChange={(event) => setKey(event.target.value)}
            type="password"
            placeholder={status?.configured ? "Enter a new key to replace current value" : "MiniMax API key"}
            className="h-10 min-w-0 rounded-[8px] border border-[var(--app-border)] bg-[var(--app-panel)] px-3 text-[13px] text-[var(--app-text)] outline-none transition-[border-color,box-shadow] duration-150 placeholder:text-[var(--app-text-dim)] focus:border-[var(--app-border-strong)] focus:shadow-[0_0_0_4px_rgba(36,36,36,0.06)]"
          />
          <div className="flex gap-2">
            <PrimaryButton
              type="button"
              disabled={!key.trim()}
              onClick={async () => {
                const next = await getApi().secrets.saveMiniMaxKey({ apiKey: key });
                setStatus(next);
                setKey("");
                setMessage(`Saved MiniMax key: ${next.maskedKey}`);
              }}
            >
              Save key
            </PrimaryButton>
            <SecondaryButton
              type="button"
              onClick={async () => {
                const next = await getApi().secrets.clearMiniMaxKey();
                setStatus(next);
                setMessage("MiniMax key cleared.");
              }}
            >
              Clear
            </SecondaryButton>
          </div>
        </div>
        <p className="mt-3 text-[12px] text-[var(--app-text-muted)]">{message}</p>
      </Panel>
    </ToolLayout>
  );
}
