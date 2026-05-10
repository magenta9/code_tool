import type { AiTaskRequest, GeneratedArtifact } from "@codetool/shared";

type MiniMaxTaskRequest = Extract<AiTaskRequest, { provider: "minimax" }>;

export interface MiniMaxClientResult {
  text?: string;
  artifact?: {
    kind: "speech" | "image" | "music";
    bytes: Uint8Array;
    mimeType: string;
    extension: string;
    filename: string;
    metadata?: Record<string, unknown>;
  };
}

export const minimaxDefaults = {
  baseURL: "https://api.minimaxi.com/v1",
  chatModel: "MiniMax-M2.7",
  speechModel: "speech-2.8-hd",
  imageModel: "image-01",
  musicModel: "music-2.5"
};

export function buildMiniMaxRequest(input: MiniMaxTaskRequest): { path: string; body: Record<string, unknown> } {
  switch (input.toolId) {
    case "aiChat":
      return {
        path: "/text/chatcompletion_v2",
        body: {
          model: input.model ?? minimaxDefaults.chatModel,
          messages: [...(input.history ?? []), { role: "user", content: input.prompt }],
          stream: true
        }
      };
    case "aiSpeech":
      return {
        path: "/t2a_v2",
        body: {
          model: input.model ?? minimaxDefaults.speechModel,
          text: input.text,
          voice_setting: { voice_id: input.voiceId || "male-qn-qingse" },
          audio_setting: { sample_rate: 32000, bitrate: 128000, format: "mp3" }
        }
      };
    case "aiImage":
      return {
        path: "/image_generation",
        body: {
          model: input.model ?? minimaxDefaults.imageModel,
          prompt: input.prompt,
          aspect_ratio: input.aspectRatio ?? "1:1",
          n: input.count ?? 1,
          reference_asset_ids: input.referenceAssetIds ?? []
        }
      };
    case "aiMusic":
      return {
        path: "/music_generation",
        body: {
          model: input.model ?? minimaxDefaults.musicModel,
          prompt: input.prompt,
          lyrics: normalizedLyrics(input.lyrics) ?? undefined,
          style: input.style,
          audio_setting: {
            sample_rate: 44100,
            bitrate: 256000,
            format: "mp3"
          },
          output_format: "url",
          ...(normalizedLyrics(input.lyrics)
            ? {}
            : { lyrics_optimizer: true })
        }
      };
  }
}

export class MiniMaxClient {
  constructor(
    private readonly getApiKey: () => Promise<string | null>,
    private readonly baseURL = minimaxDefaults.baseURL
  ) { }

  async assertConfigured(): Promise<void> {
    const key = await this.getApiKey();
    if (!key) {
      throw new Error("MiniMax API key is not configured.");
    }
  }

  async run(input: MiniMaxTaskRequest, signal: AbortSignal): Promise<MiniMaxClientResult> {
    switch (input.toolId) {
      case "aiChat":
        return { text: await this.chat(input, signal) };
      case "aiSpeech":
        return { artifact: await this.speech(input, signal) };
      case "aiImage":
        return { artifact: await this.image(input, signal) };
      case "aiMusic":
        return { artifact: await this.music(input, signal) };
    }
  }

  private async chat(input: Extract<MiniMaxTaskRequest, { toolId: "aiChat" }>, signal: AbortSignal): Promise<string> {
    const json = await this.requestJson(
      "/chat/completions",
      {
        model: input.model ?? minimaxDefaults.chatModel,
        messages: [...(input.history ?? []), { role: "user", content: input.prompt }],
        temperature: 0.7,
        max_tokens: 2048,
        stream: false
      },
      signal
    );
    const choices = readObjectArray(json, "choices");
    const first = choices[0];
    const message = first ? readObject(first, "message") : null;
    const content = message ? message.content : undefined;
    if (typeof content !== "string") throw new Error("MiniMax chat response did not include message content.");
    return content;
  }

  private async speech(input: Extract<MiniMaxTaskRequest, { toolId: "aiSpeech" }>, signal: AbortSignal) {
    const json = await this.requestJson(
      "/t2a_v2",
      {
        model: input.model ?? minimaxDefaults.speechModel,
        text: input.text,
        voice_setting: {
          voice_id: input.voiceId || "male-qn-qingse",
          speed: 1,
          vol: 1,
          pitch: 0
        },
        audio_setting: {
          sample_rate: 32000,
          bitrate: 128000,
          format: "mp3",
          channel: 1
        },
        output_format: "hex"
      },
      signal
    );
    const data = readObject(json, "data");
    const audio = data.audio;
    if (typeof audio !== "string") throw new Error("MiniMax speech response did not include audio hex.");
    return {
      kind: "speech" as const,
      bytes: decodeHex(audio),
      mimeType: "audio/mpeg",
      extension: "mp3",
      filename: "minimax-speech.mp3",
      metadata: { voiceId: input.voiceId }
    };
  }

  private async image(input: Extract<MiniMaxTaskRequest, { toolId: "aiImage" }>, signal: AbortSignal) {
    const json = await this.requestJson(
      "/image_generation",
      {
        model: input.model ?? minimaxDefaults.imageModel,
        prompt: input.prompt,
        aspect_ratio: input.aspectRatio ?? "1:1",
        n: input.count ?? 1,
        prompt_optimizer: true
      },
      signal
    );
    const data = readObject(json, "data");
    const inlineImage = firstString(data.image_base64);
    if (inlineImage) {
      return {
        kind: "image" as const,
        bytes: decodeBase64(inlineImage),
        mimeType: "image/png",
        extension: "png",
        filename: "minimax-image.png",
        metadata: { aspectRatio: input.aspectRatio, count: input.count, transport: "base64" }
      };
    }

    const imageUrl = firstString(data.image_url) ?? firstString(data.image_urls) ?? firstString(data.images);
    if (!imageUrl) {
      throw new Error("MiniMax image response did not include image_base64 or image_url output.");
    }

    const downloaded = await this.downloadAsset(imageUrl, signal);
    const mimeType = normalizeMimeType(downloaded.mimeType) ?? "image/png";
    const extension = extensionForMimeType(mimeType) ?? extensionFromUrl(imageUrl) ?? "png";
    return {
      kind: "image" as const,
      bytes: downloaded.bytes,
      mimeType,
      extension,
      filename: `minimax-image.${extension}`,
      metadata: { aspectRatio: input.aspectRatio, count: input.count, transport: "url" }
    };
  }

  private async music(input: Extract<MiniMaxTaskRequest, { toolId: "aiMusic" }>, signal: AbortSignal) {
    const lyrics = normalizedLyrics(input.lyrics);
    const json = await this.requestJson(
      "/music_generation",
      {
        model: input.model ?? minimaxDefaults.musicModel,
        prompt: input.prompt,
        lyrics: lyrics ?? undefined,
        ...(lyrics ? {} : { lyrics_optimizer: true }),
        style: input.style,
        audio_setting: {
          sample_rate: 44100,
          bitrate: 256000,
          format: "mp3"
        },
        output_format: "url"
      },
      signal,
      600_000
    );
    const data = readObject(json, "data");
    const audio = data.audio ?? data.audio_url;
    if (typeof audio !== "string" || !audio) {
      throw new Error("MiniMax music response did not include an audio URL or audio payload.");
    }
    const bytes = audio.startsWith("http://") || audio.startsWith("https://")
      ? await this.download(audio, signal)
      : decodeHex(audio);
    return {
      kind: "music" as const,
      bytes,
      mimeType: "audio/mpeg",
      extension: "mp3",
      filename: "minimax-music.mp3",
      metadata: { style: input.style }
    };
  }

  private async requestJson(
    path: string,
    body: Record<string, unknown>,
    signal: AbortSignal,
    timeoutMs = 120_000
  ): Promise<Record<string, unknown>> {
    const key = await this.getApiKey();
    if (!key) throw new Error("MiniMax API key is not configured.");
    const timeout = AbortSignal.timeout(timeoutMs);
    const response = await fetch(`${this.baseURL}${path}`, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${key}`,
        "Content-Type": "application/json"
      },
      body: JSON.stringify(body),
      signal: AbortSignal.any([signal, timeout])
    });
    const text = await response.text();
    let json: Record<string, unknown>;
    try {
      json = JSON.parse(text) as Record<string, unknown>;
    } catch {
      throw new Error(`MiniMax returned non-JSON response: HTTP ${response.status}`);
    }
    const baseResp = readOptionalObject(json, "base_resp");
    const statusCode = baseResp && typeof baseResp.status_code === "number" ? baseResp.status_code : 0;
    if (!response.ok || statusCode !== 0) {
      const statusMessage = baseResp && typeof baseResp.status_msg === "string" ? baseResp.status_msg : response.statusText;
      throw new Error(`MiniMax request failed: ${statusCode || response.status} ${statusMessage}`);
    }
    return json;
  }

  private async download(url: string, signal: AbortSignal): Promise<Uint8Array> {
    return (await this.downloadAsset(url, signal)).bytes;
  }

  private async downloadAsset(
    url: string,
    signal: AbortSignal
  ): Promise<{ bytes: Uint8Array; mimeType: string | null }> {
    const response = await fetch(url, { signal });
    if (!response.ok) throw new Error(`MiniMax asset download failed: HTTP ${response.status}`);
    return {
      bytes: new Uint8Array(await response.arrayBuffer()),
      mimeType: response.headers.get("content-type")
    };
  }
}

function readObject(input: Record<string, unknown>, key: string): Record<string, unknown> {
  const value = input[key];
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new Error(`MiniMax response missing object field: ${key}`);
  }
  return value as Record<string, unknown>;
}

function readOptionalObject(input: Record<string, unknown>, key: string): Record<string, unknown> | null {
  const value = input[key];
  return value && typeof value === "object" && !Array.isArray(value) ? (value as Record<string, unknown>) : null;
}

function readObjectArray(input: Record<string, unknown>, key: string): Record<string, unknown>[] {
  const value = input[key];
  if (!Array.isArray(value)) throw new Error(`MiniMax response missing array field: ${key}`);
  return value.filter((item): item is Record<string, unknown> => Boolean(item) && typeof item === "object" && !Array.isArray(item));
}

function decodeHex(hex: string): Uint8Array {
  const normalized = hex.trim();
  if (normalized.length % 2 !== 0) throw new Error("MiniMax audio hex has an invalid length.");
  const bytes = new Uint8Array(normalized.length / 2);
  for (let index = 0; index < normalized.length; index += 2) {
    const value = Number.parseInt(normalized.slice(index, index + 2), 16);
    if (Number.isNaN(value)) throw new Error("MiniMax audio hex contains invalid bytes.");
    bytes[index / 2] = value;
  }
  return bytes;
}

function decodeBase64(value: string): Uint8Array {
  return new Uint8Array(Buffer.from(value, "base64"));
}

function normalizedLyrics(value: string | undefined): string | null {
  const trimmed = value?.trim();
  return trimmed ? trimmed : null;
}

function firstString(value: unknown): string | null {
  if (typeof value === "string") {
    const trimmed = value.trim();
    return trimmed ? trimmed : null;
  }

  if (Array.isArray(value)) {
    for (const item of value) {
      const nested = firstString(item);
      if (nested) return nested;
    }
    return null;
  }

  if (value && typeof value === "object") {
    const record = value as Record<string, unknown>;
    return firstString(record.url) ?? firstString(record.image_url) ?? firstString(record.imageUrl);
  }

  return null;
}

function normalizeMimeType(value: string | null): string | null {
  if (!value) return null;
  return value.split(";", 1)[0]?.trim() || null;
}

function extensionForMimeType(mimeType: string): string | null {
  switch (mimeType) {
    case "image/png":
      return "png";
    case "image/jpeg":
      return "jpg";
    case "image/webp":
      return "webp";
    case "image/gif":
      return "gif";
    default:
      return null;
  }
}

function extensionFromUrl(url: string): string | null {
  const pathname = new URL(url).pathname;
  const match = pathname.match(/\.([a-zA-Z0-9]+)$/);
  const extension = match?.[1];
  return extension ? extension.toLowerCase() : null;
}
