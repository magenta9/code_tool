import type { MiniMaxProviderStatus, SaveMiniMaxKeyInput } from "@codetool/shared";
import keytar from "keytar";

const serviceName = "CodeTool MiniMax";
const accountName = "default";

export class MiniMaxSecretStore {
  async getApiKey(): Promise<string | null> {
    return keytar.getPassword(serviceName, accountName);
  }

  async status(): Promise<MiniMaxProviderStatus> {
    const key = await this.getApiKey();
    return {
      provider: "minimax",
      configured: Boolean(key),
      maskedKey: key ? maskKey(key) : undefined
    };
  }

  async save(input: SaveMiniMaxKeyInput): Promise<MiniMaxProviderStatus> {
    const key = input.apiKey.trim();
    if (!key) {
      await keytar.deletePassword(serviceName, accountName);
      return this.status();
    }
    await keytar.setPassword(serviceName, accountName, key);
    return this.status();
  }

  async clear(): Promise<MiniMaxProviderStatus> {
    await keytar.deletePassword(serviceName, accountName);
    return this.status();
  }
}

function maskKey(key: string): string {
  if (key.length <= 8) return "••••";
  return `${key.slice(0, 4)}••••${key.slice(-4)}`;
}
