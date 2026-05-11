import { useState } from "react";
import type { DecodeJwtResult, EncodeJwtResult } from "@codetool/shared";
import { Braces, KeyRound } from "lucide-react";
import { getApi } from "../../api";
import { ActionButton, Panel, SegmentedControl, StatusStrip, TextArea, TextInput, ToolLayout } from "../../components/tool-layout";

type JwtMode = "decode" | "encode";

const defaultHeader = JSON.stringify({ alg: "none", typ: "JWT" }, null, 2);
const defaultPayload = JSON.stringify({ sub: "123", name: "CodeTool" }, null, 2);

export function JwtToolPage(): JSX.Element {
  const [mode, setMode] = useState<JwtMode>("decode");
  const [token, setToken] = useState("");
  const [decodeResult, setDecodeResult] = useState<DecodeJwtResult | null>(null);
  const [header, setHeader] = useState(defaultHeader);
  const [payload, setPayload] = useState(defaultPayload);
  const [signature, setSignature] = useState("");
  const [encodeResult, setEncodeResult] = useState<EncodeJwtResult | null>(null);

  return (
    <ToolLayout title="JWT Tool" description="Decode JWTs or assemble local unsigned tokens from JSON header and payload.">
      <SegmentedControl
        value={mode}
        ariaLabel="JWT mode"
        options={[
          { value: "decode", label: "Decode", icon: <KeyRound size={13} /> },
          { value: "encode", label: "Encode", icon: <Braces size={13} /> }
        ]}
        onChange={(value) => setMode(value as JwtMode)}
      />

      {mode === "decode" ? <DecodePanel token={token} setToken={setToken} setDecodeResult={setDecodeResult} /> : null}
      {mode === "encode" ? (
        <EncodePanel
          header={header}
          setHeader={setHeader}
          payload={payload}
          setPayload={setPayload}
          signature={signature}
          setSignature={setSignature}
          setEncodeResult={setEncodeResult}
        />
      ) : null}

      {mode === "decode" && decodeResult ? <DecodedResult result={decodeResult} /> : null}
      {mode === "encode" && encodeResult ? <EncodedResult result={encodeResult} /> : null}
    </ToolLayout>
  );
}

function DecodePanel({
  token,
  setToken,
  setDecodeResult
}: {
  token: string;
  setToken: (value: string) => void;
  setDecodeResult: (result: DecodeJwtResult) => void;
}): JSX.Element {
  return (
    <Panel
      title="Token"
      actions={
        <ActionButton type="button" onClick={async () => setDecodeResult(await getApi().tools.decodeJwt({ token }))}>
          <KeyRound size={14} /> Decode
        </ActionButton>
      }
    >
      <TextArea spellCheck={false} value={token} onChange={(event) => setToken(event.target.value)} placeholder="Paste JWT here" />
    </Panel>
  );
}

function EncodePanel({
  header,
  setHeader,
  payload,
  setPayload,
  signature,
  setSignature,
  setEncodeResult
}: {
  header: string;
  setHeader: (value: string) => void;
  payload: string;
  setPayload: (value: string) => void;
  signature: string;
  setSignature: (value: string) => void;
  setEncodeResult: (result: EncodeJwtResult) => void;
}): JSX.Element {
  return (
    <Panel
      title="Claims"
      actions={
        <ActionButton type="button" onClick={async () => setEncodeResult(await getApi().tools.encodeJwt({ header, payload, signature }))}>
          <Braces size={14} /> Encode
        </ActionButton>
      }
    >
      <div className="grid gap-3 xl:grid-cols-2">
        <TextArea spellCheck={false} value={header} onChange={(event) => setHeader(event.target.value)} placeholder="Header JSON" />
        <TextArea spellCheck={false} value={payload} onChange={(event) => setPayload(event.target.value)} placeholder="Payload JSON" />
      </div>
      <div className="mt-3">
        <TextInput value={signature} onChange={(event) => setSignature(event.target.value)} placeholder="Signature segment (optional)" />
      </div>
    </Panel>
  );
}

function DecodedResult({ result }: { result: DecodeJwtResult }): JSX.Element {
  return (
    <Panel title="Decoded">
      <StatusStrip>{result.ok ? `signature ${result.signaturePreview}${result.expiresAt ? ` · exp ${result.expiresAt}` : ""}` : result.error}</StatusStrip>
      {result.ok ? (
        <div className="mt-3 grid gap-3 xl:grid-cols-2">
          <TextArea readOnly spellCheck={false} value={JSON.stringify(result.header, null, 2)} />
          <TextArea readOnly spellCheck={false} value={JSON.stringify(result.payload, null, 2)} />
        </div>
      ) : null}
    </Panel>
  );
}

function EncodedResult({ result }: { result: EncodeJwtResult }): JSX.Element {
  return (
    <Panel title="Encoded">
      <StatusStrip>{result.ok ? "Token assembled locally. It is not signed or verified." : result.error}</StatusStrip>
      {result.ok ? <TextArea className="mt-3" readOnly spellCheck={false} value={result.token ?? ""} /> : null}
    </Panel>
  );
}
