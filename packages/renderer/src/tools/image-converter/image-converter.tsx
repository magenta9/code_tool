import { useState } from "react";
import type { ImageBase64Inspection } from "@codetool/shared";
import { Save, Search } from "lucide-react";
import { getApi } from "../../api";
import { ActionButton, Panel, StatusStrip, TextArea, TextInput, ToolLayout } from "../../components/tool-layout";

export function ImageConverterPage(): JSX.Element {
  const [base64, setBase64] = useState("");
  const [filename, setFilename] = useState("converted-image.png");
  const [inspection, setInspection] = useState<ImageBase64Inspection | null>(null);
  const [message, setMessage] = useState("");

  return (
    <ToolLayout title="Image Converter" description="Inspect image Base64 and save decoded files through main-process asset storage.">
      <Panel
        title="Base64"
        actions={
          <div className="flex flex-wrap gap-2">
            <ActionButton type="button" onClick={async () => setInspection(await getApi().tools.inspectImageBase64({ base64 }))}>
              <Search size={14} /> Inspect
            </ActionButton>
            <ActionButton
              type="button"
              variant="primary"
              onClick={async () => {
                const asset = await getApi().tools.saveImageBase64({ base64, filename });
                setMessage(`Saved ${asset.filename} · ${asset.byteLength} bytes`);
              }}
            >
              <Save size={14} /> Save asset
            </ActionButton>
          </div>
        }
      >
        <TextArea spellCheck={false} value={base64} onChange={(event) => setBase64(event.target.value)} placeholder="Paste data URL or raw Base64 image bytes" />
        <div className="mt-3 grid gap-2">
          <TextInput
            value={filename}
            onChange={(event) => setFilename(event.target.value)}
            placeholder="Filename"
          />
        </div>
        {inspection ? (
          <div className="mt-3">
            <StatusStrip>{inspection.ok ? `${inspection.mimeType} · ${inspection.byteLength} bytes` : inspection.error}</StatusStrip>
          </div>
        ) : null}
        {message ? <p className="mt-3 text-[12px] text-[#9da69b]">{message}</p> : null}
      </Panel>
    </ToolLayout>
  );
}
