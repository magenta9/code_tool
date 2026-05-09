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
            className="h-10 min-w-0 rounded-[8px] bg-[#050607] px-3 text-[13px] text-[#e8ece7] shadow-[inset_0_0_0_1px_rgba(255,255,255,0.08)] outline-none focus:shadow-[inset_0_0_0_1px_rgba(209,255,74,0.55)]"
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
        <p className="mt-3 text-[12px] text-[#9da69b]">{message}</p>
      </Panel>
    </ToolLayout>
  );
}
