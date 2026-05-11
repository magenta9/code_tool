import type { MarkdownPluginId } from "@codetool/shared";

export interface MarkdownThemeOption {
    id: string;
    label: string;
    exportCss: string;
}

export const markdownPluginOptions: Array<{ id: MarkdownPluginId; label: string }> = [
    { id: "gfm", label: "GFM" },
    { id: "math", label: "Math" },
    { id: "mermaid", label: "Mermaid" },
    { id: "codeHighlight", label: "Code highlight" },
    { id: "frontmatter", label: "Frontmatter" },
    { id: "toc", label: "TOC" },
    { id: "outline", label: "Outline" }
];

export const markdownThemeOptions: MarkdownThemeOption[] = [
    {
        id: "codetool",
        label: "CodeTool",
        exportCss: `.markdown-body { color: #20201d; } .markdown-body a { color: #315f8f; }`
    },
    {
        id: "paper",
        label: "Paper",
        exportCss: `.markdown-body { color: #27231d; font-family: Georgia, "Times New Roman", serif; } .markdown-body a { color: #7a4e21; } .markdown-body pre { background: #f3eadc; }`
    },
    {
        id: "graphite",
        label: "Graphite",
        exportCss: `.markdown-body { color: #e9e7df; background: #202323; } .markdown-body a { color: #8fc7d4; } .markdown-body pre { background: #171a1a; } .markdown-body blockquote { color: #b9b5aa; }`
    }
];

export function markdownThemeClass(themeId: string | undefined): string {
    return `markdown-theme-${themeId && markdownThemeOptions.some((theme) => theme.id === themeId) ? themeId : "codetool"}`;
}

export function markdownThemeCss(themeId: string | undefined): string {
    return markdownThemeOptions.find((theme) => theme.id === themeId)?.exportCss ?? markdownThemeOptions[0].exportCss;
}