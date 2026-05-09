import { useState } from "react";
import type { DecodeJwtResult } from "@codetool/shared";
import { getApi } from "../../api";
import { Panel, PrimaryButton, StatusStrip, TextArea, ToolLayout } from "../../components/tool-layout";

export function JwtToolPage(): JSX.Element {
  const [token, setToken] = useState("");
  const [result, setResult] = useState<DecodeJwtResult | null>(null);

  return (
    <ToolLayout title="JWT Tool" description="Decode JWT header and payload without trusting or executing the token.">
      <Panel
        title="Token"
        actions={
          <PrimaryButton type="button" onClick={async () => setResult(await getApi().tools.decodeJwt({ token }))}>
            Decode
          </PrimaryButton>
        }
      >
        <TextArea spellCheck={false} value={token} onChange={(event) => setToken(event.target.value)} placeholder="Paste JWT here" />
      </Panel>
      {result ? (
        <Panel title="Decoded">
          <StatusStrip>{result.ok ? `signature ${result.signaturePreview}${result.expiresAt ? ` · exp ${result.expiresAt}` : ""}` : result.error}</StatusStrip>
          {result.ok ? (
            <div className="mt-3 grid gap-3 xl:grid-cols-2">
              <TextArea readOnly spellCheck={false} value={JSON.stringify(result.header, null, 2)} />
              <TextArea readOnly spellCheck={false} value={JSON.stringify(result.payload, null, 2)} />
            </div>
          ) : null}
        </Panel>
      ) : null}
    </ToolLayout>
  );
}
