import type { ToolCatalogEntry, ToolId } from "./types/tools";

export const toolCatalog = [
  {
    id: "jsonTool",
    title: "JSON Tool",
    description: "Format, validate, minify, and analyze JSON data.",
    category: "devTools",
    icon: "Braces",
    routePath: "/tools/json",
    capabilities: ["history"]
  },
  {
    id: "imageConverter",
    title: "Image Converter",
    description: "Convert images between Base64 strings and files.",
    category: "devTools",
    icon: "Image",
    routePath: "/tools/image-converter",
    capabilities: ["history", "file", "media"]
  },
  {
    id: "jsonDiff",
    title: "JSON Diff",
    description: "Compare two JSON objects and find structural differences.",
    category: "devTools",
    icon: "GitCompare",
    routePath: "/tools/json-diff",
    capabilities: ["history"]
  },
  {
    id: "timestampConverter",
    title: "Timestamp Converter",
    description: "Convert timestamps, ISO strings, and local dates.",
    category: "devTools",
    icon: "Clock3",
    routePath: "/tools/timestamp",
    capabilities: ["history"]
  },
  {
    id: "jwtTool",
    title: "JWT Tool",
    description: "Decode and inspect JWT headers, payloads, and expiry claims.",
    category: "devTools",
    icon: "KeyRound",
    routePath: "/tools/jwt",
    capabilities: ["history"]
  },
  {
    id: "wordCloud",
    title: "Word Cloud",
    description: "Tokenize text and rank terms for deterministic word clouds.",
    category: "devTools",
    icon: "Cloud",
    routePath: "/tools/word-cloud",
    capabilities: ["history"]
  },
  {
    id: "aiChat",
    title: "AI Chat",
    description: "Stream MiniMax chat responses with history and diagnostics.",
    category: "aiTools",
    icon: "MessagesSquare",
    routePath: "/tools/ai-chat",
    capabilities: ["history", "ai", "streaming"]
  },
  {
    id: "aiSpeech",
    title: "AI Speech",
    description: "Generate speech audio with MiniMax and keep output history.",
    category: "aiTools",
    icon: "AudioLines",
    routePath: "/tools/ai-speech",
    capabilities: ["history", "ai", "media"]
  },
  {
    id: "aiImage",
    title: "AI Image",
    description: "Generate images with MiniMax prompts and references.",
    category: "aiTools",
    icon: "Images",
    routePath: "/tools/ai-image",
    capabilities: ["history", "ai", "media"]
  },
  {
    id: "aiMusic",
    title: "AI Music",
    description: "Generate MiniMax music tasks with timeout diagnostics.",
    category: "aiTools",
    icon: "Music",
    routePath: "/tools/ai-music",
    capabilities: ["history", "ai", "media"]
  }
] as const satisfies readonly ToolCatalogEntry[];

export const toolIds = toolCatalog.map((tool) => tool.id) as ToolId[];

export function getToolById(toolId: ToolId): ToolCatalogEntry {
  const entry = toolCatalog.find((tool) => tool.id === toolId);
  if (!entry) {
    throw new Error(`Unknown tool id: ${toolId}`);
  }
  return entry;
}
