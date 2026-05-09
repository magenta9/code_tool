import type { AppSettings } from "@codetool/shared";
import type { SettingsRepository } from "../db/repositories/settings-repository";

export class SettingsHandlers {
  constructor(private readonly settings: SettingsRepository) {}

  get() {
    return this.settings.get();
  }

  save(input: Partial<AppSettings>) {
    return this.settings.save(input);
  }
}
