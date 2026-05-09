import {
  convertTimestamp,
  decodeJwt,
  diffJsonText,
  inspectImageBase64,
  runJsonTool,
  analyzeWordCloud,
  type SaveImageBase64Input
} from "@codetool/shared";
import type { AssetStore } from "../storage/asset-store";
import type { HistoryRepository } from "../db/repositories/history-repository";

export class ToolHandlers {
  constructor(
    private readonly history: HistoryRepository,
    private readonly assets: AssetStore
  ) {}

  runJsonTool(input: Parameters<typeof runJsonTool>[0]): ReturnType<typeof runJsonTool> {
    const result = runJsonTool(input);
    if (result.ok) {
      this.history.create({
        toolId: "jsonTool",
        title: `JSON ${input.mode}`,
        summary: result.stats ? `${result.stats.keys} keys · depth ${result.stats.maxDepth}` : "Valid JSON",
        payload: { input, result }
      });
    }
    return result;
  }

  runJsonDiff(input: { left: string; right: string }) {
    const result = diffJsonText(input.left, input.right);
    if (result.ok) {
      this.history.create({
        toolId: "jsonDiff",
        title: `Diff: ${result.changes.length} changes`,
        summary: `+${result.summary.added} -${result.summary.removed} ~${result.summary.modified}`,
        payload: { input, result }
      });
    }
    return result;
  }

  convertTimestamp(input: Parameters<typeof convertTimestamp>[0]): ReturnType<typeof convertTimestamp> {
    const result = convertTimestamp(input);
    if (result.ok) {
      this.history.create({
        toolId: "timestampConverter",
        title: input.value,
        summary: result.iso ?? "Converted timestamp",
        payload: { input, result }
      });
    }
    return result;
  }

  decodeJwt(input: { token: string }) {
    const result = decodeJwt(input.token);
    if (result.ok) {
      this.history.create({
        toolId: "jwtTool",
        title: "JWT inspection",
        summary: result.expiresAt ? `exp ${result.expiresAt}` : "Decoded header and payload",
        payload: { input: { tokenPreview: `${input.token.slice(0, 18)}...` }, result }
      });
    }
    return result;
  }

  analyzeWordCloud(input: { text: string }) {
    const result = analyzeWordCloud(input.text);
    this.history.create({
      toolId: "wordCloud",
      title: "Word cloud",
      summary: `${result.uniqueWords} unique terms`,
      payload: { input, result }
    });
    return result;
  }

  inspectImageBase64(input: { base64: string }) {
    const result = inspectImageBase64(input.base64);
    return { ...result, data: undefined };
  }

  saveImageBase64(input: SaveImageBase64Input) {
    const inspection = inspectImageBase64(input.base64);
    if (!inspection.ok || !inspection.data || !inspection.mimeType || !inspection.extension) {
      throw new Error(inspection.error ?? "Invalid image data.");
    }
    const asset = this.assets.writeAsset({
      kind: "image",
      bytes: inspection.data,
      mimeType: inspection.mimeType,
      extension: inspection.extension,
      filename: input.filename
    });
    this.history.create({
      toolId: "imageConverter",
      title: "Base64 image saved",
      summary: `${asset.mimeType} · ${asset.byteLength} bytes`,
      payload: { input: { filename: input.filename }, asset },
      assetIds: [asset.id]
    });
    return asset;
  }
}
