import type {
    MarkdownDirectoryListing,
    MarkdownExportInput,
    MarkdownExportResult,
    MarkdownListDirectoryInput,
    MarkdownOpenDirectoryResult,
    MarkdownOpenFileResult,
    MarkdownReadFileInput,
    MarkdownSaveFileAsInput,
    MarkdownSaveFileInput,
    MarkdownSaveFileResult,
    MarkdownSaveImageAssetInput,
    MarkdownSaveImageAssetResult
} from "@codetool/shared";
import { BrowserWindow, dialog } from "electron";
import katex from "katex";
import { marked } from "marked";
import { mkdir, readFile, readdir, stat, writeFile } from "node:fs/promises";
import { randomUUID } from "node:crypto";
import { basename, dirname, extname, isAbsolute, join, relative, resolve } from "node:path";
import { pathToFileURL } from "node:url";
import type { SettingsRepository } from "../db/repositories/settings-repository";

export class MarkdownHandlers {
    private readonly authorizedFiles = new Set<string>();
    private readonly authorizedDirectories = new Set<string>();

    constructor(private readonly settings: SettingsRepository) { }

    async openFile(): Promise<MarkdownOpenFileResult> {
        const result = await dialog.showOpenDialog({
            properties: ["openFile"],
            filters: markdownFileFilters
        });
        const filePath = result.filePaths[0];
        if (result.canceled || !filePath) {
            return { cancelled: true };
        }
        return this.readAuthorizedDocument(filePath);
    }

    async readFile(input: MarkdownReadFileInput): Promise<MarkdownOpenFileResult> {
        const absolutePath = resolve(input.path);
        ensureMarkdownPath(absolutePath);
        this.ensureCanRead(absolutePath);
        return this.readAuthorizedDocument(absolutePath);
    }

    async saveFile(input: MarkdownSaveFileInput): Promise<MarkdownSaveFileResult> {
        const absolutePath = resolve(input.path);
        ensureMarkdownPath(absolutePath);
        this.ensureCanWrite(absolutePath);
        await writeFile(absolutePath, input.content, "utf8");
        this.authorizeFile(absolutePath);
        return {
            cancelled: false,
            document: await makeDocument(absolutePath, input.content),
            savedAt: new Date().toISOString()
        };
    }

    async saveFileAs(input: MarkdownSaveFileAsInput): Promise<MarkdownSaveFileResult> {
        const result = await dialog.showSaveDialog({
            defaultPath: input.suggestedName,
            filters: markdownFileFilters
        });
        if (result.canceled || !result.filePath) {
            return { cancelled: true };
        }
        const absolutePath = withMarkdownExtension(resolve(result.filePath));
        await writeFile(absolutePath, input.content, "utf8");
        this.authorizeFile(absolutePath);
        return {
            cancelled: false,
            document: await makeDocument(absolutePath, input.content),
            savedAt: new Date().toISOString()
        };
    }

    async openDirectory(): Promise<MarkdownOpenDirectoryResult> {
        const result = await dialog.showOpenDialog({
            properties: ["openDirectory"]
        });
        const directoryPath = result.filePaths[0];
        if (result.canceled || !directoryPath) {
            return { cancelled: true };
        }
        const rootPath = resolve(directoryPath);
        this.authorizedDirectories.add(rootPath);
        return {
            cancelled: false,
            rootPath,
            listing: await this.listDirectory({ rootPath })
        };
    }

    async listDirectory(input: MarkdownListDirectoryInput): Promise<MarkdownDirectoryListing> {
        const rootPath = resolve(input.rootPath);
        this.ensureCanReadDirectory(rootPath);
        const entries = await readdir(rootPath, { withFileTypes: true });
        return {
            rootPath,
            entries: entries
                .filter((entry) => !entry.name.startsWith("."))
                .filter((entry) => entry.isDirectory() || isMarkdownPath(entry.name))
                .map((entry) => ({
                    path: resolve(rootPath, entry.name),
                    name: entry.name,
                    kind: entry.isDirectory() ? ("directory" as const) : ("file" as const)
                }))
                .sort((left, right) => {
                    if (left.kind !== right.kind) return left.kind === "directory" ? -1 : 1;
                    return left.name.localeCompare(right.name);
                })
        };
    }

    private authorizeFile(path: string): void {
        const absolutePath = resolve(path);
        this.authorizedFiles.add(absolutePath);
        this.authorizedDirectories.add(dirname(absolutePath));
    }

    private async readAuthorizedDocument(path: string): Promise<MarkdownOpenFileResult> {
        const absolutePath = resolve(path);
        ensureMarkdownPath(absolutePath);
        this.authorizeFile(absolutePath);
        return readDocument(absolutePath);
    }

    private ensureCanRead(path: string): void {
        const absolutePath = resolve(path);
        if (this.authorizedFiles.has(absolutePath)) return;
        if ([...this.authorizedDirectories].some((directory) => isInsideDirectory(absolutePath, directory))) return;
        if (this.isInRecentDirectory(absolutePath)) return;
        throw new Error("Markdown file access has not been authorized by a system dialog.");
    }

    private ensureCanWrite(path: string): void {
        const absolutePath = resolve(path);
        if (this.authorizedFiles.has(absolutePath)) return;
        throw new Error("Markdown file write access has not been authorized by a system dialog.");
    }

    private ensureCanReadDirectory(path: string): void {
        const absolutePath = resolve(path);
        if (this.authorizedDirectories.has(absolutePath)) return;
        if ([...this.authorizedDirectories].some((directory) => isInsideDirectory(absolutePath, directory))) return;
        if (this.isInRecentDirectory(absolutePath)) return;
        throw new Error("Markdown directory access has not been authorized by a system dialog.");
    }

    private isInRecentDirectory(path: string): boolean {
        const recentDirectories = this.settings.get().markdownEditor.recentDirectories.map((directory) => resolve(directory));
        return recentDirectories.some((directory) => isInsideDirectory(path, directory));
    }

    async saveImageAsset(input: MarkdownSaveImageAssetInput): Promise<MarkdownSaveImageAssetResult> {
        const documentPath = resolve(input.documentPath);
        ensureMarkdownPath(documentPath);
        this.ensureCanWrite(documentPath);
        const extension = imageExtension(input.mimeType, input.filename);
        const assetDirectory = join(dirname(documentPath), "assets");
        const filename = `${randomUUID()}-${sanitizeFilename(input.filename || `image.${extension}`)}`;
        const normalizedFilename = filename.endsWith(`.${extension}`) ? filename : `${filename}.${extension}`;
        const absolutePath = join(assetDirectory, normalizedFilename);
        await mkdir(assetDirectory, { recursive: true });
        await writeFile(absolutePath, Buffer.from(input.data));
        const relativePath = `assets/${normalizedFilename}`;
        return {
            relativePath,
            absolutePath,
            markdown: `![${imageAltText(normalizedFilename)}](${relativePath})`
        };
    }

    async exportHtml(input: MarkdownExportInput): Promise<MarkdownExportResult> {
        const result = await dialog.showSaveDialog({
            defaultPath: exportDefaultName(input, "html"),
            filters: [{ name: "HTML", extensions: ["html"] }]
        });
        if (result.canceled || !result.filePath) {
            return { cancelled: true };
        }
        const exportPath = withFileExtension(resolve(result.filePath), "html");
        const sourceDirectory = this.exportSourceDirectory(input.sourcePath);
        const html = await renderExportHtml(input, sourceDirectory, "html");
        await writeFile(exportPath, html, "utf8");
        return { cancelled: false, path: exportPath };
    }

    async exportPdf(input: MarkdownExportInput): Promise<MarkdownExportResult> {
        const result = await dialog.showSaveDialog({
            defaultPath: exportDefaultName(input, "pdf"),
            filters: [{ name: "PDF", extensions: ["pdf"] }]
        });
        if (result.canceled || !result.filePath) {
            return { cancelled: true };
        }
        const exportPath = withFileExtension(resolve(result.filePath), "pdf");
        const sourceDirectory = this.exportSourceDirectory(input.sourcePath);
        const html = await renderExportHtml(input, sourceDirectory, "pdf");
        const pdf = await renderPdf(html);
        await writeFile(exportPath, pdf);
        return { cancelled: false, path: exportPath };
    }

    private exportSourceDirectory(sourcePath?: string): string | undefined {
        if (!sourcePath) return undefined;
        const absolutePath = resolve(sourcePath);
        ensureMarkdownPath(absolutePath);
        this.ensureCanRead(absolutePath);
        return dirname(absolutePath);
    }
}

const markdownFileFilters = [{ name: "Markdown", extensions: ["md", "markdown"] }];

async function makeDocument(path: string, content: string): Promise<MarkdownOpenFileResult["document"]> {
    const metadata = await stat(path);
    return {
        path,
        name: basename(path),
        directory: dirname(path),
        content,
        updatedAt: metadata.mtime.toISOString()
    };
}

function isMarkdownPath(path: string): boolean {
    return [".md", ".markdown"].includes(extname(path).toLowerCase());
}

function ensureMarkdownPath(path: string): void {
    if (!isMarkdownPath(path)) {
        throw new Error("Only Markdown files can be opened or saved.");
    }
}

function withMarkdownExtension(path: string): string {
    return isMarkdownPath(path) ? path : `${path}.md`;
}

function withFileExtension(path: string, extension: "html" | "pdf"): string {
    return extname(path).toLowerCase() === `.${extension}` ? path : `${path}.${extension}`;
}

function exportDefaultName(input: MarkdownExportInput, extension: "html" | "pdf"): string {
    const title = input.title ? basename(input.title, extname(input.title)) : "Untitled";
    return `${sanitizeFilename(title)}.${extension}`;
}

async function renderExportHtml(input: MarkdownExportInput, sourceDirectory: string | undefined, target: "html" | "pdf"): Promise<string> {
    const markdown = (input.enabledPlugins?.includes("math") ?? true) ? renderMathMarkdown(input.content) : input.content;
    const body = resolveExportReferences(await marked.parse(markdown, { gfm: input.enabledPlugins?.includes("gfm") ?? true }), sourceDirectory, target);
    const base = sourceDirectory && target === "html" ? `<base href="${escapeHtml(pathToFileURL(`${sourceDirectory}/`).toString())}">` : "";
    const title = escapeHtml(input.title || "Markdown Export");
    const themeCss = input.themeCss ? input.themeCss : defaultMarkdownExportCss;
    return `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
${base}
<title>${title}</title>
<style>${defaultExportPageCss}\n${themeCss}</style>
</head>
<body>
<main class="markdown-export markdown-body">
${body}
</main>
</body>
</html>`;
}

async function renderPdf(html: string): Promise<Buffer> {
    const window = new BrowserWindow({
        show: false,
        webPreferences: {
            javascript: false,
            sandbox: true,
            contextIsolation: true
        }
    });
    try {
        await window.loadURL(`data:text/html;charset=utf-8,${encodeURIComponent(html)}`);
        return await window.webContents.printToPDF({
            printBackground: true,
            pageSize: "A4",
            margins: {
                marginType: "default"
            }
        });
    } finally {
        window.destroy();
    }
}

function resolveExportReferences(html: string, sourceDirectory: string | undefined, target: "html" | "pdf"): string {
    if (!sourceDirectory || target !== "pdf") return html;
    return html.replace(/\bsrc="([^"]+)"/g, (match, reference: string) => {
        if (isExternalReference(reference)) return match;
        const absolutePath = resolve(sourceDirectory, reference);
        if (!isInsideDirectory(absolutePath, sourceDirectory)) return match;
        return `src="${escapeHtml(pathToFileURL(absolutePath).toString())}"`;
    });
}

function isExternalReference(reference: string): boolean {
    return /^([a-z][a-z0-9+.-]*:|#|\/)/i.test(reference);
}

function escapeHtml(value: string): string {
    return value
        .replace(/&/g, "&amp;")
        .replace(/</g, "&lt;")
        .replace(/>/g, "&gt;")
        .replace(/"/g, "&quot;");
}

const defaultExportPageCss = `
html { background: #f5f5f2; color: #20201d; }
body { margin: 0; font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; }
.markdown-export { box-sizing: border-box; width: min(840px, calc(100vw - 48px)); margin: 32px auto; padding: 48px 56px; background: #fff; border: 1px solid #deded8; }
@media print { html, body { background: #fff; } .markdown-export { width: auto; margin: 0; padding: 0; border: 0; } }
`;

const defaultMarkdownExportCss = `
.markdown-body { font-size: 15px; line-height: 1.75; }
.markdown-body h1, .markdown-body h2, .markdown-body h3 { line-height: 1.25; margin: 1.35em 0 0.55em; }
.markdown-body h1 { font-size: 2em; }
.markdown-body h2 { font-size: 1.55em; }
.markdown-body h3 { font-size: 1.25em; }
.markdown-body p, .markdown-body ul, .markdown-body ol, .markdown-body blockquote, .markdown-body pre, .markdown-body table { margin: 0 0 1em; }
.markdown-body ul { list-style: disc; padding-left: 1.55em; }
.markdown-body ol { list-style: decimal; padding-left: 1.55em; }
.markdown-body li { margin: 0.2em 0; padding-left: 0.15em; }
.markdown-body li > p { margin: 0.15em 0; }
.markdown-body li > ul, .markdown-body li > ol { margin: 0.25em 0; }
.markdown-body code, .markdown-body pre { font-family: "SF Mono", "Cascadia Code", Menlo, monospace; }
.markdown-body pre { overflow: auto; padding: 14px 16px; border-radius: 8px; background: #f3f3ef; }
.markdown-body blockquote { border-left: 3px solid #8d8062; color: #66645d; padding-left: 14px; }
.markdown-body img { max-width: 100%; height: auto; }
.markdown-body table { width: 100%; border-collapse: collapse; }
.markdown-body th, .markdown-body td { border: 1px solid #d8d8d0; padding: 6px 8px; }
.katex-display { overflow-x: auto; overflow-y: hidden; }
`;

function renderMathMarkdown(markdown: string): string {
    const lines = markdown.split(/\r?\n/);
    const output: string[] = [];
    let inFence = false;
    let mathBuffer: string[] | null = null;
    for (const line of lines) {
        if (/^\s*```/.test(line) || /^\s*~~~/.test(line)) {
            inFence = !inFence;
            output.push(line);
            continue;
        }
        if (!inFence && line.trim() === "$$") {
            if (mathBuffer) {
                output.push(katex.renderToString(mathBuffer.join("\n"), { displayMode: true, throwOnError: false }));
                mathBuffer = null;
            } else {
                mathBuffer = [];
            }
            continue;
        }
        if (mathBuffer) {
            mathBuffer.push(line);
            continue;
        }
        output.push(inFence ? line : renderInlineMath(line));
    }
    if (mathBuffer) output.push("$$", ...mathBuffer);
    return output.join("\n");
}

function renderInlineMath(line: string): string {
    return line.replace(/(^|[^\\])\$([^$\n]+?)\$/g, (_match, prefix: string, expression: string) => {
        return `${prefix}${katex.renderToString(expression, { displayMode: false, throwOnError: false })}`;
    });
}

function imageExtension(mimeType: string, filename?: string): string {
    const fromName = filename ? extname(filename).replace(/^\./, "").toLowerCase() : "";
    if (["png", "jpg", "jpeg", "gif", "webp"].includes(fromName)) return fromName;
    const fromMime = mimeType.toLowerCase().split("/")[1] ?? "";
    if (fromMime === "jpeg") return "jpg";
    if (["png", "jpg", "gif", "webp"].includes(fromMime)) return fromMime;
    throw new Error("Only PNG, JPEG, GIF, and WebP images are supported.");
}

function sanitizeFilename(filename: string): string {
    return filename.replace(/[^a-zA-Z0-9._-]/g, "-").slice(0, 120) || "image";
}

function imageAltText(filename: string): string {
    const name = basename(filename, extname(filename)).replace(/^[0-9a-f-]+-/, "");
    return name || "image";
}

function isInsideDirectory(path: string, directory: string): boolean {
    const child = resolve(path);
    const parent = resolve(directory);
    const segment = relative(parent, child);
    return segment === "" || (!!segment && !segment.startsWith("..") && !isAbsolute(segment));
}

async function readDocument(path: string): Promise<MarkdownOpenFileResult> {
    const content = await readFile(path, "utf8");
    return {
        cancelled: false,
        document: await makeDocument(path, content)
    };
}

