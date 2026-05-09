export type ToolCategory = "devTools" | "aiTools";

export type ToolId =
  | "jsonTool"
  | "imageConverter"
  | "jsonDiff"
  | "timestampConverter"
  | "jwtTool"
  | "wordCloud"
  | "kanban"
  | "aiChat"
  | "piAgent"
  | "aiSpeech"
  | "aiImage"
  | "aiMusic";

export interface ToolCatalogEntry {
  id: ToolId;
  title: string;
  description: string;
  category: ToolCategory;
  icon: string;
  routePath: string;
  capabilities: Array<"history" | "file" | "ai" | "streaming" | "media">;
}

export type JsonPrimitive = string | number | boolean | null;
export type JsonValue = JsonPrimitive | JsonValue[] | { [key: string]: JsonValue };
