export type MarkdownViewMode = "write" | "source" | "split";

export type MarkdownDirectoryEntryKind = "file" | "directory";

export type MarkdownExportFormat = "html" | "pdf";

export type MarkdownPluginId = "gfm" | "math" | "mermaid" | "codeHighlight" | "frontmatter" | "toc" | "outline";

export interface MarkdownDocument {
    path: string;
    name: string;
    directory: string;
    content: string;
    updatedAt?: string;
}

export interface MarkdownDirectoryEntry {
    path: string;
    name: string;
    kind: MarkdownDirectoryEntryKind;
}

export interface MarkdownDirectoryListing {
    rootPath: string;
    entries: MarkdownDirectoryEntry[];
}

export interface MarkdownOpenFileResult {
    cancelled: boolean;
    document?: MarkdownDocument;
}

export interface MarkdownOpenDirectoryResult {
    cancelled: boolean;
    rootPath?: string;
    listing?: MarkdownDirectoryListing;
}

export interface MarkdownReadFileInput {
    path: string;
}

export interface MarkdownSaveFileInput {
    path: string;
    content: string;
}

export interface MarkdownSaveFileAsInput {
    suggestedName?: string;
    content: string;
}

export interface MarkdownSaveFileResult {
    cancelled: boolean;
    document?: MarkdownDocument;
    savedAt?: string;
}

export interface MarkdownListDirectoryInput {
    rootPath: string;
}

export interface MarkdownSaveImageAssetInput {
    documentPath: string;
    filename?: string;
    mimeType: string;
    data: ArrayBuffer;
}

export interface MarkdownSaveImageAssetResult {
    relativePath: string;
    absolutePath: string;
    markdown: string;
}

export interface MarkdownExportInput {
    format: MarkdownExportFormat;
    content: string;
    title?: string;
    sourcePath?: string;
    themeCss?: string;
    enabledPlugins?: MarkdownPluginId[];
}

export interface MarkdownExportResult {
    cancelled: boolean;
    path?: string;
}

export interface MarkdownThemeManifest {
    id: string;
    name: string;
    source: "builtin" | "typora" | "obsidian" | "custom";
    css: string;
}

export interface MarkdownEditorSettings {
    viewMode: MarkdownViewMode;
    autosave: boolean;
    enabledPlugins: MarkdownPluginId[];
    themeId?: string;
    recentDirectories: string[];
}
