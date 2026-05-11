# Markdown Editor Implementation Plan

Date: 2026-05-11

## Target

Add a new `markdownEditor` dev tool to CodeTool. The tool should behave like a lightweight Typora-style Markdown editor with directory access, recent directories, theme compatibility, built-in Markdown plugins, image assets, autosave, and HTML/PDF export.

## Architecture

### Renderer

Create `packages/renderer/src/tools/markdown-editor/` with a page component and focused subcomponents:

1. `markdown-editor.tsx`: tool page shell, state orchestration, file/directory actions.
2. `editor/MilkdownEditor.tsx`: WYSIWYG editor adapter.
3. `editor/SourceEditor.tsx`: CodeMirror 6 source mode adapter.
4. `components/DirectorySidebar.tsx`: open directory tree, recent directories, file selection.
5. `components/EditorToolbar.tsx`: view mode, save/export/theme/plugin controls.
6. `components/OutlinePanel.tsx`: heading outline from Markdown/frontmatter metadata.
7. `themes/`: scoped content theme CSS and compatibility mappings.

The renderer should not read or write filesystem paths directly. It should call typed preload APIs.

### Main Process

Add a Markdown-specific IPC handler, likely `packages/main/src/ipc/markdown.ts`, for file and export operations:

1. Open Markdown file through `dialog.showOpenDialog`.
2. Save current file through main-process write.
3. Save As through `dialog.showSaveDialog`.
4. Open directory through `dialog.showOpenDialog({ properties: ["openDirectory"] })`.
5. List Markdown directory entries and relevant asset folders.
6. Read selected Markdown file content.
7. Write pasted/dropped image assets to sibling `assets/` directory.
8. Export HTML through `dialog.showSaveDialog` and `fs.writeFile`.
9. Export PDF through Electron print rendering or a hidden export window.

Add methods to `packages/shared/src/ipc-contract.ts`, `packages/shared/src/ipc-channels.ts`, `packages/preload/src/api.ts`, and bind them in `packages/main/src/ipc/register.ts`.

### Shared Types

Add `packages/shared/src/tools/markdown-editor.ts` with types such as:

1. `MarkdownDocumentHandle`
2. `MarkdownDirectoryEntry`
3. `MarkdownEditorSettings`
4. `MarkdownOpenFileResult`
5. `MarkdownSaveInput`
6. `MarkdownExportInput`
7. `MarkdownThemeManifest`
8. `MarkdownPluginId`

Extend `ToolId` with `markdownEditor`, add a catalog entry in `packages/shared/src/tool-catalog.ts`, and add the renderer route in `packages/renderer/src/App.tsx`.

## Product Scope

### First Version

1. WYSIWYG Markdown editing with Milkdown.
2. Source mode with CodeMirror 6.
3. Split preview mode.
4. New file, open file, save, save as.
5. Open directory and recent directories.
6. Directory sidebar for Markdown files.
7. Default autosave with debounce.
8. Pasted/dropped image asset saving to sibling `assets/` directory.
9. HTML export with current theme.
10. PDF export with current theme.
11. Built-in plugin toggles: GFM, math, Mermaid, code highlighting, frontmatter, TOC, outline.
12. Best-effort Typora/Obsidian CSS theme import/compatibility.

### Explicitly Out of Scope for First Version

1. Arbitrary user JavaScript plugins.
2. Full vault features such as backlinks, graph view, tags, sync, and full-text index.
3. Collaboration.
4. Publishing.
5. App-level version snapshots, unless the autosave risk is revisited.
6. Strict pixel-perfect Typora/Obsidian theme compatibility.

## Implementation Steps

1. Add dependencies for Milkdown, CodeMirror 6, Markdown parsing/rendering helpers, math, Mermaid, and syntax highlighting.
2. Register the tool in shared catalog, `ToolId`, renderer routes, tests, and README.
3. Add shared Markdown IPC types and channels.
4. Implement main-process Markdown file handlers using Electron dialogs and Node filesystem APIs.
5. Implement renderer page skeleton with toolbar, side directory panel, editor area, and status strip.
6. Integrate Milkdown WYSIWYG mode and ensure Markdown text remains the canonical state.
7. Integrate CodeMirror 6 source mode and split preview mode.
8. Add autosave debounce and visible save/error state.
9. Add directory listing and recent directory persistence through settings.
10. Add image paste/drop handling and sibling `assets/` writes through main IPC.
11. Add built-in plugin toggles and renderer error boundaries for math/Mermaid blocks.
12. Add theme loading, scoped CSS application, and best-effort Typora/Obsidian compatibility mapping.
13. Add HTML export using current Markdown content and current theme CSS.
14. Add PDF export using current rendered HTML and print CSS.
15. Add smoke tests for route registration, basic editor UI, IPC contract coverage, and file handler validation.
16. Run `pnpm build` as the minimum verification; run `pnpm test` if implementation touches shared contracts and renderer behavior broadly.

## Executable Task Breakdown

### Task 1: Register Empty Tool Shell

Scope:

1. Add `markdownEditor` to `ToolId`.
2. Add a catalog entry in `packages/shared/src/tool-catalog.ts`.
3. Add a renderer route in `packages/renderer/src/App.tsx`.
4. Add `packages/renderer/src/tools/markdown-editor/markdown-editor.tsx` with a placeholder `ToolLayout`.
5. Update README feature list and route smoke tests.

Verification:

1. `pnpm build`
2. Existing catalog and renderer smoke tests should pass or be updated intentionally.

### Task 2: Add Markdown IPC Contract Skeleton

Scope:

1. Add shared Markdown editor types under `packages/shared/src/tools/markdown-editor.ts`.
2. Add Markdown channels in `packages/shared/src/ipc-channels.ts`.
3. Extend `IpcContract` in `packages/shared/src/ipc-contract.ts`.
4. Add preload API forwarding in `packages/preload/src/api.ts`.
5. Add a stub `MarkdownHandlers` class and bind it in `packages/main/src/ipc/register.ts`.

Verification:

1. `pnpm typecheck`
2. IPC contract tests updated and passing.

### Task 3: Implement File Open/Save

Scope:

1. Implement `openMarkdownFile` through `dialog.showOpenDialog`.
2. Implement `saveMarkdownFile` for the currently authorized file handle/path.
3. Implement `saveMarkdownFileAs` through `dialog.showSaveDialog`.
4. Limit dialog filters to Markdown-compatible extensions by default.
5. Return document metadata: display name, absolute path only if acceptable for UI, file directory, modified time, and content.

Verification:

1. Unit test handler validation where feasible.
2. Manual smoke test in Electron dev mode once UI hooks exist.

### Task 4: Add Directory And Recent Directory Support

Scope:

1. Implement `openMarkdownDirectory` through directory dialog.
2. Implement `listMarkdownDirectory` in main process.
3. Include `.md` and `.markdown` files plus folders.
4. Persist recent directories in `AppSettings`.
5. Add `DirectorySidebar` with file tree and recent directory list.

Verification:

1. `pnpm typecheck`
2. Renderer smoke test for sidebar states with mocked preload API.

### Task 5: Integrate Milkdown WYSIWYG Mode

Scope:

1. Add Milkdown dependencies.
2. Create `MilkdownEditor` adapter.
3. Load Markdown content into Milkdown.
4. Emit Markdown text changes back to the page state.
5. Keep Markdown text as canonical state.

Verification:

1. `pnpm build`
2. Fixture test for common Markdown round-trip if practical in the test environment.

### Task 6: Integrate Source And Split Modes

Scope:

1. Add CodeMirror 6 dependencies.
2. Create `SourceEditor` adapter.
3. Add view mode control: WYSIWYG, source, split.
4. Ensure source edits update canonical Markdown state.
5. Add preview rendering for split mode using the same Markdown pipeline as export where possible.

Verification:

1. Renderer smoke test for mode switching.
2. `pnpm build`

### Task 7: Add Autosave

Scope:

1. Add default-on autosave with debounce.
2. Show save status: saved, saving, unsaved, failed.
3. Save only when the current document has an authorized path.
4. For unsaved documents, prompt Save As before autosave can write.
5. Keep explicit Save action available.

Verification:

1. Unit test debounce logic if extracted.
2. Manual smoke test for save status transitions.

### Task 8: Add Image Paste/Drop Assets

Scope:

1. Capture pasted and dropped image files in renderer.
2. Send image bytes to main through Markdown IPC.
3. Save files to sibling `assets/` directory next to the current Markdown file.
4. Insert relative Markdown image syntax.
5. Block image asset writes for unsaved documents until the `.md` file is saved.

Verification:

1. Handler test for filename sanitization and relative path generation.
2. Manual paste/drop smoke test.

### Task 9: Add Built-In Markdown Enhancements

Scope:

1. Add toggles for GFM, math, Mermaid, code highlighting, frontmatter, TOC, and outline.
2. Store toggle settings in `AppSettings` or Markdown-specific settings.
3. Render invalid math/Mermaid blocks as local block errors instead of failing the whole document.
4. Add outline generation from headings.

Verification:

1. Fixture tests for heading extraction and frontmatter handling.
2. Manual smoke tests for Mermaid/math error handling.

### Task 10: Add Theme Compatibility

Scope:

1. Add scoped Markdown content theme layer.
2. Add built-in default themes.
3. Add best-effort Typora/Obsidian CSS import or registration path.
4. Apply compatibility class/token mappings where practical.
5. Ensure imported CSS does not affect the app chrome outside the editor/export scope.

Verification:

1. CSS scope smoke test where feasible.
2. Manual test with representative Typora/Obsidian CSS themes.

### Task 11: Add HTML Export

Scope:

1. Generate export HTML from canonical Markdown and current theme CSS.
2. Inline required CSS for portability.
3. Resolve relative image paths safely.
4. Save through main-process save dialog.

Verification:

1. Handler test for export path and HTML shape.
2. Manual open exported HTML file.

### Task 12: Add PDF Export

Scope:

1. Render export HTML in an Electron-controlled print context.
2. Apply current content theme and print CSS.
3. Save PDF through main-process save dialog.
4. Surface export failures in the renderer status area.

Verification:

1. Manual PDF export smoke test.
2. `pnpm build`

### Task 13: Stabilize UX And Tests

Scope:

1. Add keyboard shortcuts for save, save as, open file, open directory, export, and mode switching.
2. Add unsaved/failed-save status affordances.
3. Add route and contract tests.
4. Update README with the final first-version feature list.
5. Confirm app layout works with the existing Workbench shell and hidden title bar.

Verification:

1. `pnpm build`
2. `pnpm test`
3. Manual Electron smoke test for open, edit, autosave, image paste, theme switch, HTML export, and PDF export.

## Test Strategy

1. Shared catalog tests should cover the new `markdownEditor` route and tool id.
2. IPC contract tests should cover newly added Markdown methods.
3. Main handler unit tests should cover path sanitization, extension filtering, directory listing, autosave writes, image asset path generation, and export input validation.
4. Renderer smoke tests should confirm route rendering, toolbar actions, mode switching, and sidebar states.
5. Markdown round-trip fixtures should verify that common Markdown syntax is not destroyed by editor interactions.
6. Export tests should verify that HTML output includes scoped content CSS and that PDF export is invoked through main-process logic.

## Open Concerns

1. Autosave without snapshots is risky. If users edit arbitrary filesystem files, recovery depends on external tools.
2. Theme compatibility must be marketed as best-effort, not exact compatibility.
3. Mermaid and math should fail locally per block, not globally per document.
4. User plugin support should wait until there is a sandbox, permissions manifest, disable mechanism, and crash isolation plan.
