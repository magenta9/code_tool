export interface AppSettings {
  theme: "dark" | "light" | "system";
  compactMode: boolean;
  defaultTimezone: string;
}

export interface MiniMaxProviderStatus {
  provider: "minimax";
  configured: boolean;
  maskedKey?: string;
}

export interface SaveMiniMaxKeyInput {
  apiKey: string;
}
