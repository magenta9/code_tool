import type { AppSettings } from "@codetool/shared";
import type Database from "better-sqlite3";

const defaultSettings: AppSettings = {
  theme: "dark",
  compactMode: true,
  defaultTimezone: "UTC"
};

export class SettingsRepository {
  constructor(private readonly database: Database.Database) {}

  get(): AppSettings {
    const row = this.database.prepare("SELECT value_json FROM settings WHERE key = 'app'").get() as
      | { value_json: string }
      | undefined;
    if (!row) return defaultSettings;
    return { ...defaultSettings, ...(JSON.parse(row.value_json) as Partial<AppSettings>) };
  }

  save(input: Partial<AppSettings>): AppSettings {
    const next = { ...this.get(), ...input };
    this.database
      .prepare(
        `INSERT INTO settings (key, value_json, updated_at)
         VALUES ('app', ?, ?)
         ON CONFLICT(key) DO UPDATE SET value_json = excluded.value_json, updated_at = excluded.updated_at`
      )
      .run(JSON.stringify(next), new Date().toISOString());
    return next;
  }
}
