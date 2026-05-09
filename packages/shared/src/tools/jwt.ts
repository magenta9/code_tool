export interface DecodeJwtResult {
  ok: boolean;
  header?: unknown;
  payload?: Record<string, unknown>;
  signaturePreview?: string;
  expiresAt?: string;
  error?: string;
}

export function decodeJwt(token: string): DecodeJwtResult {
  const parts = token.trim().split(".");
  if (parts.length !== 3 || parts.some((part) => part.length === 0)) {
    return { ok: false, error: "JWT must have header, payload, and signature segments." };
  }
  const [headerSegment, payloadSegment, signatureSegment] = parts as [string, string, string];

  try {
    const header = JSON.parse(decodeBase64Url(headerSegment)) as unknown;
    const payload = JSON.parse(decodeBase64Url(payloadSegment)) as Record<string, unknown>;
    const exp = typeof payload.exp === "number" ? new Date(payload.exp * 1000).toISOString() : undefined;
    return {
      ok: true,
      header,
      payload,
      signaturePreview: `${signatureSegment.slice(0, 10)}...${signatureSegment.slice(-6)}`,
      expiresAt: exp
    };
  } catch (error) {
    return {
      ok: false,
      error: error instanceof Error ? error.message : "Unable to decode JWT."
    };
  }
}

export function decodeBase64Url(segment: string): string {
  const normalized = segment.replace(/-/g, "+").replace(/_/g, "/");
  const padded = normalized.padEnd(Math.ceil(normalized.length / 4) * 4, "=");
  if (typeof atob === "function") {
    const binary = atob(padded);
    const bytes = Uint8Array.from(binary, (char) => char.charCodeAt(0));
    return new TextDecoder().decode(bytes);
  }
  const buffer = (globalThis as { Buffer?: { from(value: string, encoding: "base64"): { toString(encoding: "utf8"): string } } }).Buffer;
  if (!buffer) {
    throw new Error("No base64 decoder is available.");
  }
  return buffer.from(padded, "base64").toString("utf8");
}
