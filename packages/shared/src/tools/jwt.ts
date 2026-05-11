export interface DecodeJwtResult {
  ok: boolean;
  header?: unknown;
  payload?: Record<string, unknown>;
  signaturePreview?: string;
  expiresAt?: string;
  error?: string;
}

export interface EncodeJwtInput {
  header: string;
  payload: string;
  signature?: string;
}

export interface EncodeJwtResult {
  ok: boolean;
  token?: string;
  header?: unknown;
  payload?: unknown;
  error?: string;
}

export function decodeJwt(token: string): DecodeJwtResult {
  const parts = token.trim().split(".");
  if (parts.length !== 3 || !parts[0] || !parts[1]) {
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
      signaturePreview: signatureSegment ? `${signatureSegment.slice(0, 10)}...${signatureSegment.slice(-6)}` : "(empty)",
      expiresAt: exp
    };
  } catch (error) {
    return {
      ok: false,
      error: error instanceof Error ? error.message : "Unable to decode JWT."
    };
  }
}

export function encodeJwt(input: EncodeJwtInput): EncodeJwtResult {
  try {
    const header = JSON.parse(input.header) as unknown;
    const payload = JSON.parse(input.payload) as unknown;
    const headerSegment = encodeBase64Url(JSON.stringify(header));
    const payloadSegment = encodeBase64Url(JSON.stringify(payload));
    return {
      ok: true,
      token: `${headerSegment}.${payloadSegment}.${input.signature?.trim() ?? ""}`,
      header,
      payload
    };
  } catch (error) {
    return {
      ok: false,
      error: error instanceof Error ? error.message : "Unable to encode JWT."
    };
  }
}

export function encodeBase64Url(value: string): string {
  const bytes = new TextEncoder().encode(value);
  if (typeof btoa === "function") {
    let binary = "";
    for (const byte of bytes) binary += String.fromCharCode(byte);
    return btoa(binary).replace(/=/g, "").replace(/\+/g, "-").replace(/\//g, "_");
  }
  const buffer = (globalThis as { Buffer?: { from(value: Uint8Array): { toString(encoding: "base64"): string } } }).Buffer;
  if (!buffer) {
    throw new Error("No base64 encoder is available.");
  }
  return buffer.from(bytes).toString("base64").replace(/=/g, "").replace(/\+/g, "-").replace(/\//g, "_");
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
