export interface ImageBase64Inspection {
  ok: boolean;
  mimeType?: string;
  byteLength?: number;
  extension?: string;
  data?: Uint8Array;
  error?: string;
}

export function inspectImageBase64(input: string): ImageBase64Inspection {
  try {
    const base64 = input.includes(",") ? input.slice(input.indexOf(",") + 1) : input;
    const bytes = decodeBase64(base64.trim());
    const detected = detectMime(bytes);
    if (!detected) {
      return { ok: false, error: "Unsupported or invalid image bytes." };
    }
    return {
      ok: true,
      mimeType: detected.mimeType,
      extension: detected.extension,
      byteLength: bytes.byteLength,
      data: bytes
    };
  } catch (error) {
    return { ok: false, error: error instanceof Error ? error.message : "Invalid base64 input." };
  }
}

export function decodeBase64(value: string): Uint8Array {
  if (typeof atob === "function") {
    const binary = atob(value);
    return Uint8Array.from(binary, (char) => char.charCodeAt(0));
  }
  const buffer = (globalThis as { Buffer?: { from(value: string, encoding: "base64"): Uint8Array } }).Buffer;
  if (!buffer) {
    throw new Error("No base64 decoder is available.");
  }
  return new Uint8Array(buffer.from(value, "base64"));
}

export function detectMime(bytes: Uint8Array): { mimeType: string; extension: string } | null {
  if (bytes.length >= 8 && bytes[0] === 0x89 && bytes[1] === 0x50 && bytes[2] === 0x4e && bytes[3] === 0x47) {
    return { mimeType: "image/png", extension: "png" };
  }
  if (bytes.length >= 3 && bytes[0] === 0xff && bytes[1] === 0xd8 && bytes[2] === 0xff) {
    return { mimeType: "image/jpeg", extension: "jpg" };
  }
  if (bytes.length >= 6 && bytes[0] === 0x47 && bytes[1] === 0x49 && bytes[2] === 0x46) {
    return { mimeType: "image/gif", extension: "gif" };
  }
  if (
    bytes.length >= 12 &&
    bytes[0] === 0x52 &&
    bytes[1] === 0x49 &&
    bytes[2] === 0x46 &&
    bytes[3] === 0x46 &&
    bytes[8] === 0x57 &&
    bytes[9] === 0x45 &&
    bytes[10] === 0x42 &&
    bytes[11] === 0x50
  ) {
    return { mimeType: "image/webp", extension: "webp" };
  }
  return null;
}
