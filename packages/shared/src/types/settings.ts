import type { MarkdownEditorSettings } from "../tools/markdown-editor";

export interface AppSettings {
  theme: "dark" | "light" | "system";
  compactMode: boolean;
  defaultTimezone: string;
  markdownEditor: MarkdownEditorSettings;
}

export interface MiniMaxProviderStatus {
  provider: "minimax";
  configured: boolean;
  maskedKey?: string;
}

export interface SaveMiniMaxKeyInput {
  apiKey: string;
}
