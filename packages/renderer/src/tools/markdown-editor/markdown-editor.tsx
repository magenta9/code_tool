import { type ClipboardEvent, type DragEvent, useEffect, useMemo, useState } from "react";
import { Download, FilePlus2, FolderOpen, Save } from "lucide-react";
import type { MarkdownDirectoryEntry, MarkdownDocument, MarkdownEditorSettings, MarkdownPluginId } from "@codetool/shared";
import { getApi } from "../../api";
import { ActionButton, Panel, PillTag, SegmentedControl, StatusStrip, ToolLayout } from "../../components/tool-layout";
import { MilkdownMarkdownEditor } from "./editor/MilkdownMarkdownEditor";
import { RenderedMarkdownPreview } from "./editor/RenderedMarkdownPreview";
import { SourceMarkdownEditor } from "./editor/SourceMarkdownEditor";
import { markdownPluginOptions, markdownThemeClass, markdownThemeCss, markdownThemeOptions } from "./markdown-config";

type EditorViewMode = "write" | "source" | "split";
type SaveState = "idle" | "dirty" | "saving" | "saved" | "error";

interface MarkdownHeading {
    line: number;
    level: number;
    text: string;
}

export function MarkdownEditorPage(): JSX.Element {
    const [viewMode, setViewMode] = useState<EditorViewMode>("write");
    const [draft, setDraft] = useState("# Untitled\n\nStart writing Markdown here.");
    const [document, setDocument] = useState<MarkdownDocument | null>(null);
    const [directoryRoot, setDirectoryRoot] = useState<string | null>(null);
    const [entries, setEntries] = useState<MarkdownDirectoryEntry[]>([]);
    const [recentDirectories, setRecentDirectories] = useState<string[]>([]);
    const [autosaveEnabled, setAutosaveEnabled] = useState(true);
    const [enabledPlugins, setEnabledPlugins] = useState<MarkdownPluginId[]>(["gfm"]);
    const [themeId, setThemeId] = useState("codetool");
    const [lastSavedDraft, setLastSavedDraft] = useState(draft);
    const [saveState, setSaveState] = useState<SaveState>("idle");
    const [status, setStatus] = useState("Ready");
    const [editorRevision, setEditorRevision] = useState(0);
    const [outlineTarget, setOutlineTarget] = useState<{ line: number; nonce: number } | null>(null);
    const outline = useMemo(() => extractMarkdownOutline(draft), [draft]);

    useEffect(() => {
        let active = true;
        void getApi().settings.get().then((settings) => {
            if (!active) return;
            setRecentDirectories(settings.markdownEditor.recentDirectories);
            setViewMode(settings.markdownEditor.viewMode);
            setAutosaveEnabled(settings.markdownEditor.autosave);
            setEnabledPlugins(settings.markdownEditor.enabledPlugins);
            setThemeId(settings.markdownEditor.themeId ?? "codetool");
        });
        return () => {
            active = false;
        };
    }, []);

    useEffect(() => {
        if (!document) {
            setSaveState(draft === lastSavedDraft ? "idle" : "dirty");
            return;
        }
        if (draft === lastSavedDraft) {
            setSaveState("saved");
            return;
        }
        setSaveState("dirty");
        if (!autosaveEnabled) return;
        const timeout = window.setTimeout(() => {
            void saveExistingDocument(document.path, draft, "autosave");
        }, 1000);
        return () => window.clearTimeout(timeout);
    }, [autosaveEnabled, document, draft, lastSavedDraft]);

    async function openFile(): Promise<void> {
        try {
            const result = await getApi().markdown.openFile();
            if (result.cancelled || !result.document) return;
            setDocument(result.document);
            setDraft(result.document.content);
            setEditorRevision((current) => current + 1);
            setLastSavedDraft(result.document.content);
            setSaveState("saved");
            setStatus(`Opened ${result.document.name}`);
        } catch (error) {
            setStatus(error instanceof Error ? error.message : "Unable to open file");
        }
    }

    async function openDirectory(): Promise<void> {
        try {
            const result = await getApi().markdown.openDirectory();
            if (result.cancelled || !result.rootPath || !result.listing) return;
            setDirectoryRoot(result.rootPath);
            setEntries(result.listing.entries);
            await rememberDirectory(result.rootPath);
            setStatus(`Opened directory ${result.rootPath}`);
        } catch (error) {
            setStatus(error instanceof Error ? error.message : "Unable to open directory");
        }
    }

    async function openRecentDirectory(rootPath: string): Promise<void> {
        try {
            const listing = await getApi().markdown.listDirectory({ rootPath });
            setDirectoryRoot(rootPath);
            setEntries(listing.entries);
            await rememberDirectory(rootPath);
            setStatus(`Opened directory ${rootPath}`);
        } catch (error) {
            setStatus(error instanceof Error ? error.message : "Unable to open recent directory");
        }
    }

    async function rememberDirectory(rootPath: string): Promise<void> {
        const settings = await getApi().settings.get();
        const recent = [rootPath, ...settings.markdownEditor.recentDirectories.filter((directory) => directory !== rootPath)].slice(0, 8);
        const markdownEditor: MarkdownEditorSettings = {
            ...settings.markdownEditor,
            recentDirectories: recent
        };
        await getApi().settings.save({ markdownEditor });
        setRecentDirectories(recent);
    }

    async function saveMarkdownSettings(patch: Partial<MarkdownEditorSettings>): Promise<void> {
        const settings = await getApi().settings.get();
        const markdownEditor: MarkdownEditorSettings = {
            ...settings.markdownEditor,
            ...patch
        };
        await getApi().settings.save({ markdownEditor });
    }

    async function updateTheme(nextThemeId: string): Promise<void> {
        setThemeId(nextThemeId);
        await saveMarkdownSettings({ themeId: nextThemeId });
    }

    async function updateViewMode(nextViewMode: EditorViewMode): Promise<void> {
        setViewMode(nextViewMode);
        await saveMarkdownSettings({ viewMode: nextViewMode });
    }

    async function updatePlugin(pluginId: MarkdownPluginId, enabled: boolean): Promise<void> {
        const next = enabled ? [...new Set([...enabledPlugins, pluginId])] : enabledPlugins.filter((id) => id !== pluginId);
        setEnabledPlugins(next);
        await saveMarkdownSettings({ enabledPlugins: next });
        setEditorRevision((current) => current + 1);
    }

    async function jumpToHeading(heading: MarkdownHeading): Promise<void> {
        if (viewMode === "write") {
            await updateViewMode("source");
        }
        setOutlineTarget({ line: heading.line, nonce: Date.now() });
        setStatus(`Heading line ${heading.line}: ${heading.text}`);
    }

    async function openDirectoryFile(entry: MarkdownDirectoryEntry): Promise<void> {
        if (entry.kind !== "file") return;
        try {
            const result = await getApi().markdown.readFile({ path: entry.path });
            if (result.cancelled || !result.document) return;
            setDocument(result.document);
            setDraft(result.document.content);
            setEditorRevision((current) => current + 1);
            setLastSavedDraft(result.document.content);
            setSaveState("saved");
            setStatus(`Opened ${result.document.name}`);
        } catch (error) {
            setStatus(error instanceof Error ? error.message : "Unable to open file");
        }
    }

    async function saveDocument(): Promise<void> {
        if (document) {
            await saveExistingDocument(document.path, draft, "manual");
            return;
        }
        try {
            setSaveState("saving");
            const result = await getApi().markdown.saveFileAs({ suggestedName: "Untitled.md", content: draft });
            if (result.cancelled || !result.document) return;
            setDocument(result.document);
            setDraft(result.document.content);
            setEditorRevision((current) => current + 1);
            setLastSavedDraft(result.document.content);
            setSaveState("saved");
            setStatus(`Saved ${result.document.name}`);
        } catch (error) {
            setSaveState("error");
            setStatus(error instanceof Error ? error.message : "Unable to save file");
        }
    }

    async function saveExistingDocument(path: string, content: string, mode: "manual" | "autosave"): Promise<void> {
        try {
            setSaveState("saving");
            const result = await getApi().markdown.saveFile({ path, content });
            if (result.cancelled || !result.document) return;
            setDocument(result.document);
            setLastSavedDraft(content);
            setSaveState("saved");
            setStatus(mode === "autosave" ? `Autosaved ${result.document.name}` : `Saved ${result.document.name}`);
        } catch (error) {
            setSaveState("error");
            setStatus(error instanceof Error ? error.message : "Unable to save file");
        }
    }

    async function insertImageAsset(file: File): Promise<void> {
        if (!document) {
            setStatus("Save the Markdown file before adding images.");
            return;
        }
        try {
            const data = await file.arrayBuffer();
            const result = await getApi().markdown.saveImageAsset({
                documentPath: document.path,
                filename: file.name || undefined,
                mimeType: file.type,
                data
            });
            setDraft((current) => `${current.trimEnd()}\n\n${result.markdown}\n`);
            setEditorRevision((current) => current + 1);
            setStatus(`Inserted ${result.relativePath}`);
        } catch (error) {
            setStatus(error instanceof Error ? error.message : "Unable to insert image");
        }
    }

    function firstImageFile(files: FileList): File | null {
        return Array.from(files).find((file) => file.type.startsWith("image/")) ?? null;
    }

    function handlePaste(event: ClipboardEvent<HTMLDivElement>): void {
        const file = firstImageFile(event.clipboardData.files);
        if (!file) return;
        event.preventDefault();
        void insertImageAsset(file);
    }

    function handleDrop(event: DragEvent<HTMLDivElement>): void {
        const file = firstImageFile(event.dataTransfer.files);
        if (!file) return;
        event.preventDefault();
        void insertImageAsset(file);
    }

    async function exportDocument(format: "html" | "pdf"): Promise<void> {
        try {
            const input = {
                format,
                content: draft,
                title: document?.name,
                sourcePath: document?.path,
                themeCss: markdownThemeCss(themeId),
                enabledPlugins
            };
            const result = format === "html" ? await getApi().markdown.exportHtml(input) : await getApi().markdown.exportPdf(input);
            if (result.cancelled || !result.path) return;
            setStatus(`Exported ${result.path}`);
        } catch (error) {
            setStatus(error instanceof Error ? error.message : `Unable to export ${format.toUpperCase()}`);
        }
    }

    useEffect(() => {
        function handleKeyDown(event: KeyboardEvent): void {
            if (!(event.metaKey || event.ctrlKey)) return;
            const key = event.key.toLowerCase();
            if (key === "s" && !event.shiftKey) {
                event.preventDefault();
                void saveDocument();
                return;
            }
            if (key === "o") {
                event.preventDefault();
                void (event.shiftKey ? openDirectory() : openFile());
                return;
            }
            if (event.shiftKey && key === "e") {
                event.preventDefault();
                void exportDocument("html");
                return;
            }
            if (event.shiftKey && key === "p") {
                event.preventDefault();
                void exportDocument("pdf");
                return;
            }
            if (key === "1") {
                event.preventDefault();
                void updateViewMode("write");
                return;
            }
            if (key === "2") {
                event.preventDefault();
                void updateViewMode("source");
                return;
            }
            if (key === "3") {
                event.preventDefault();
                void updateViewMode("split");
            }
        }
        window.addEventListener("keydown", handleKeyDown);
        return () => window.removeEventListener("keydown", handleKeyDown);
    });

    const saveStateLabel = {
        idle: "Not saved",
        dirty: "Unsaved changes",
        saving: "Saving",
        saved: autosaveEnabled ? "Autosave on" : "Saved",
        error: "Save failed"
    }[saveState];

    return (
        <ToolLayout
            title="Markdown Editor"
            description="Edit Markdown files with directory access, themes, and export."
            actions={
                <>
                    <ActionButton type="button" onClick={() => void openFile()}>
                        <FilePlus2 size={14} /> Open file
                    </ActionButton>
                    <ActionButton type="button" onClick={() => void openDirectory()}>
                        <FolderOpen size={14} /> Open directory
                    </ActionButton>
                    <ActionButton type="button" variant="primary" onClick={() => void saveDocument()}>
                        <Save size={14} /> Save
                    </ActionButton>
                    <ActionButton type="button" onClick={() => void exportDocument("html")}>
                        <Download size={14} /> HTML
                    </ActionButton>
                    <ActionButton type="button" onClick={() => void exportDocument("pdf")}>
                        <Download size={14} /> PDF
                    </ActionButton>
                </>
            }
        >
            <div className="markdown-editor grid min-h-[calc(100vh-220px)] gap-4 lg:grid-cols-[260px_minmax(0,1fr)]">
                <Panel title="Files" className="min-h-[280px]">
                    <div className="space-y-3 text-[13px] leading-5 text-[var(--ui-text-muted)]">
                        <PillTag tone="accent">{directoryRoot ? "Directory open" : "Directory mode"}</PillTag>
                        {entries.length === 0 ? (
                            <div className="space-y-3">
                                <div className="rounded-[8px] border border-dashed border-[var(--ui-border)] bg-[var(--ui-surface-soft)] px-3 py-8 text-center">
                                    No directory open
                                </div>
                                {recentDirectories.length === 0 ? null : (
                                    <div className="space-y-1">
                                        {recentDirectories.map((directory) => (
                                            <button
                                                key={directory}
                                                type="button"
                                                onClick={() => void openRecentDirectory(directory)}
                                                className="min-h-8 w-full truncate rounded-[7px] px-2.5 text-left text-[12px] text-[var(--ui-text)] transition-colors [@media(hover:hover)]:hover:bg-[rgba(25,25,22,0.05)]"
                                            >
                                                {directory}
                                            </button>
                                        ))}
                                    </div>
                                )}
                            </div>
                        ) : (
                            <div className="space-y-1">
                                {entries.map((entry) => (
                                    <button
                                        key={entry.path}
                                        type="button"
                                        onClick={() => void openDirectoryFile(entry)}
                                        disabled={entry.kind !== "file"}
                                        className="flex min-h-8 w-full items-center justify-between gap-2 rounded-[7px] px-2.5 text-left text-[12px] text-[var(--ui-text)] transition-colors [@media(hover:hover)]:hover:bg-[rgba(25,25,22,0.05)] disabled:text-[var(--ui-text-muted)]"
                                    >
                                        <span className="truncate">{entry.name}</span>
                                        <span className="shrink-0 text-[10px] uppercase text-[var(--ui-text-faint)]">{entry.kind}</span>
                                    </button>
                                ))}
                            </div>
                        )}
                        <div className="border-t border-[var(--ui-border)] pt-3">
                            <label className="grid gap-1 text-[12px] text-[var(--ui-text)]">
                                <span className="font-medium">Theme</span>
                                <select
                                    value={themeId}
                                    onChange={(event) => void updateTheme(event.target.value)}
                                    className="h-8 rounded-[7px] border border-[var(--ui-border)] bg-[var(--ui-surface)] px-2 text-[12px] text-[var(--ui-text)] outline-none"
                                >
                                    {markdownThemeOptions.map((theme) => (
                                        <option key={theme.id} value={theme.id}>
                                            {theme.label}
                                        </option>
                                    ))}
                                </select>
                            </label>
                            <div className="mt-3 grid gap-2 text-[12px] text-[var(--ui-text)]">
                                <div className="font-medium">Plugins</div>
                                {markdownPluginOptions.map((plugin) => (
                                    <label key={plugin.id} className="flex min-h-6 items-center gap-2">
                                        <input
                                            type="checkbox"
                                            checked={enabledPlugins.includes(plugin.id)}
                                            onChange={(event) => void updatePlugin(plugin.id, event.target.checked)}
                                        />
                                        <span>{plugin.label}</span>
                                    </label>
                                ))}
                            </div>
                        </div>
                        {enabledPlugins.includes("outline") ? (
                            <div className="border-t border-[var(--ui-border)] pt-3">
                                <div className="mb-2 text-[12px] font-medium text-[var(--ui-text)]">Outline</div>
                                {outline.length === 0 ? (
                                    <div className="text-[12px] text-[var(--ui-text-muted)]">No headings</div>
                                ) : (
                                    <div className="grid gap-1">
                                        {outline.map((heading) => (
                                            <button
                                                key={`${heading.line}-${heading.text}`}
                                                type="button"
                                                onClick={() => void jumpToHeading(heading)}
                                                className="min-h-7 truncate rounded-[7px] px-2 text-left text-[12px] text-[var(--ui-text)] transition-colors [@media(hover:hover)]:hover:bg-[rgba(25,25,22,0.05)]"
                                                style={{ paddingLeft: `${Math.min(heading.level - 1, 3) * 10 + 8}px` }}
                                            >
                                                {heading.text}
                                            </button>
                                        ))}
                                    </div>
                                )}
                            </div>
                        ) : null}
                    </div>
                </Panel>

                <Panel
                    title="Document"
                    actions={
                        <SegmentedControl
                            ariaLabel="Markdown editor view"
                            value={viewMode}
                            onChange={(value) => void updateViewMode(value as EditorViewMode)}
                            options={[
                                { value: "write", label: "Write" },
                                { value: "source", label: "Source" },
                                { value: "split", label: "Split" }
                            ]}
                        />
                    }
                    className="min-h-[520px]"
                >
                    <div className={`grid gap-3 ${markdownThemeClass(themeId)}`} onPaste={handlePaste} onDrop={handleDrop} onDragOver={(event) => event.preventDefault()}>
                        <StatusStrip>
                            {document ? `${document.name} · ${saveStateLabel} · ${status}` : `${saveStateLabel} · ${status}`}
                        </StatusStrip>
                        {viewMode === "write" ? (
                            <div className="markdown-editor-surface" role="textbox" aria-label="Markdown draft">
                                <MilkdownMarkdownEditor key={`${document?.path ?? "draft"}:${editorRevision}:${enabledPlugins.join(",")}`} value={draft} enabledPlugins={enabledPlugins} onChange={setDraft} />
                            </div>
                        ) : null}
                        {viewMode === "source" ? <SourceMarkdownEditor value={draft} scrollTarget={outlineTarget} onChange={setDraft} /> : null}
                        {viewMode === "split" ? (
                            <div className="grid min-h-[390px] gap-3 xl:grid-cols-2">
                                <SourceMarkdownEditor value={draft} scrollTarget={outlineTarget} onChange={setDraft} />
                                <RenderedMarkdownPreview value={draft} enabledPlugins={enabledPlugins} sourceDirectory={document?.directory} />
                            </div>
                        ) : null}
                    </div>
                </Panel>
            </div>
        </ToolLayout>
    );
}

function extractMarkdownOutline(markdown: string): MarkdownHeading[] {
    const headings: MarkdownHeading[] = [];
    let inFence = false;
    const lines = markdown.split(/\r?\n/);
    lines.forEach((line, index) => {
        if (/^\s*```/.test(line) || /^\s*~~~/.test(line)) {
            inFence = !inFence;
            return;
        }
        if (inFence) return;
        const match = /^(#{1,6})\s+(.+?)\s*#*\s*$/.exec(line);
        if (!match) return;
        headings.push({
            line: index + 1,
            level: match[1].length,
            text: cleanHeadingText(match[2])
        });
    });
    return headings;
}

function cleanHeadingText(text: string): string {
    return text
        .replace(/[`*_~\[\]]/g, "")
        .replace(/\(([^)]+)\)/g, "")
        .trim();
}
