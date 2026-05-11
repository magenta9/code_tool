import type Database from "better-sqlite3";

export function migrate(database: Database.Database): void {
  database.exec(`
    PRAGMA journal_mode = WAL;
    PRAGMA foreign_keys = ON;

    CREATE TABLE IF NOT EXISTS history_entries (
      id TEXT PRIMARY KEY,
      tool_id TEXT NOT NULL,
      title TEXT NOT NULL,
      summary TEXT NOT NULL,
      payload_json TEXT NOT NULL,
      reference_id TEXT,
      asset_ids_json TEXT NOT NULL DEFAULT '[]',
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    );

    CREATE INDEX IF NOT EXISTS history_entries_tool_created_idx
      ON history_entries(tool_id, created_at DESC);

    CREATE TABLE IF NOT EXISTS assets (
      id TEXT PRIMARY KEY,
      kind TEXT NOT NULL,
      filename TEXT NOT NULL,
      mime_type TEXT NOT NULL,
      byte_length INTEGER NOT NULL,
      relative_path TEXT NOT NULL,
      metadata_json TEXT,
      created_at TEXT NOT NULL
    );

    CREATE TABLE IF NOT EXISTS settings (
      key TEXT PRIMARY KEY,
      value_json TEXT NOT NULL,
      updated_at TEXT NOT NULL
    );

    CREATE TABLE IF NOT EXISTS ai_tasks (
      id TEXT PRIMARY KEY,
      tool_id TEXT NOT NULL,
      provider TEXT NOT NULL,
      status TEXT NOT NULL,
      reference_id TEXT NOT NULL,
      request_json TEXT NOT NULL,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    );

    CREATE TABLE IF NOT EXISTS diagnostic_events (
      id TEXT PRIMARY KEY,
      timestamp TEXT NOT NULL,
      level TEXT NOT NULL,
      message TEXT NOT NULL,
      source TEXT NOT NULL,
      reference_id TEXT,
      tool_id TEXT,
      metadata_json TEXT
    );

    CREATE INDEX IF NOT EXISTS diagnostic_reference_idx
      ON diagnostic_events(reference_id, timestamp DESC);

    CREATE TABLE IF NOT EXISTS kanban_boards (
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      description TEXT,
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL,
      archived_at INTEGER
    );

    CREATE TABLE IF NOT EXISTS kanban_columns (
      id TEXT PRIMARY KEY,
      board_id TEXT NOT NULL REFERENCES kanban_boards(id) ON DELETE CASCADE,
      name TEXT NOT NULL,
      color TEXT,
      sort_order REAL NOT NULL,
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL,
      archived_at INTEGER
    );

    CREATE INDEX IF NOT EXISTS idx_kanban_columns_board_order
      ON kanban_columns(board_id, archived_at, sort_order);

    CREATE TABLE IF NOT EXISTS kanban_cards (
      id TEXT PRIMARY KEY,
      board_id TEXT NOT NULL REFERENCES kanban_boards(id) ON DELETE CASCADE,
      column_id TEXT NOT NULL REFERENCES kanban_columns(id) ON DELETE RESTRICT,
      title TEXT NOT NULL,
      description_json TEXT,
      description_text TEXT,
      subtasks_json TEXT NOT NULL DEFAULT '[]',
      comments_json TEXT NOT NULL DEFAULT '[]',
      priority TEXT NOT NULL DEFAULT 'none',
      due_date INTEGER,
      sort_order REAL NOT NULL,
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL,
      archived_at INTEGER
    );

    CREATE INDEX IF NOT EXISTS idx_kanban_cards_board_column
      ON kanban_cards(board_id, column_id, archived_at, sort_order);

    CREATE TABLE IF NOT EXISTS kanban_labels (
      id TEXT PRIMARY KEY,
      board_id TEXT NOT NULL REFERENCES kanban_boards(id) ON DELETE CASCADE,
      name TEXT NOT NULL,
      color TEXT NOT NULL
    );

    CREATE TABLE IF NOT EXISTS kanban_card_labels (
      card_id TEXT NOT NULL REFERENCES kanban_cards(id) ON DELETE CASCADE,
      label_id TEXT NOT NULL REFERENCES kanban_labels(id) ON DELETE CASCADE,
      PRIMARY KEY (card_id, label_id)
    );
  `);

  ensureColumn(database, "kanban_cards", "subtasks_json", "TEXT NOT NULL DEFAULT '[]'");
  ensureColumn(database, "kanban_cards", "comments_json", "TEXT NOT NULL DEFAULT '[]'");
}

function ensureColumn(database: Database.Database, table: string, column: string, definition: string): void {
  const columns = database.prepare(`PRAGMA table_info(${table})`).all() as Array<{ name: string }>;
  if (!columns.some((item) => item.name === column)) {
    database.prepare(`ALTER TABLE ${table} ADD COLUMN ${column} ${definition}`).run();
  }
}
