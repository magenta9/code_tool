# Markdown Editor GitHub Research

Date: 2026-05-11

## Goal

Add a new CodeTool Markdown editor tool inspired by Typora, with directory support, theme compatibility, export, and a staged plugin model.

## Compared Projects

| Project | Repository | License | Fit | Notes |
| --- | --- | --- | --- | --- |
| Milkdown | https://github.com/Milkdown/milkdown | MIT | Best core fit | Typora-inspired WYSIWYG Markdown editor, plugin-driven, React/TypeScript friendly, built on ProseMirror and remark. |
| CodeMirror 6 | https://github.com/codemirror/dev | MIT | Best source mode | Excellent Markdown source editor, extension/theme API, smaller and more focused than Monaco for this use case. |
| Vditor | https://github.com/Vanessa219/vditor | MIT | Fast MVP option | Full-featured Markdown editor with WYSIWYG/IR/split modes, but more monolithic and less aligned with a custom CodeTool plugin architecture. |
| Cherry Markdown | https://github.com/Tencent/cherry-markdown | Apache-2.0 | Strong reference | Rich Markdown feature set and useful AI/streaming Markdown references, but also more all-in-one than desired. |
| ByteMD | https://github.com/pd4d10/bytemd | MIT | Split editor only | Good remark/rehype plugin model, but not Typora-like enough and maintenance is weaker. |
| TOAST UI Editor | https://github.com/nhn/tui.editor | MIT | Mature but risky | Mature WYSIWYG/Markdown switching, but release cadence appears weaker for a new long-term core dependency. |
| Tiptap | https://github.com/ueberdosis/tiptap | MIT core | Useful but not primary | Already used by CodeTool Kanban. Strong rich-text toolkit, but Markdown round-trip fidelity would need more custom work. |
| MarkText | https://github.com/marktext/marktext | MIT | Product reference | Electron Typora-like app. Useful UX reference, not a library to embed. |
| Zettlr | https://github.com/Zettlr/Zettlr | GPL-3.0 | Architecture reference only | Active Electron Markdown workspace. GPL-3.0 makes direct code reuse unsuitable for CodeTool. |
| Obsidian API | https://github.com/obsidianmd/obsidian-api | MIT API typings | Plugin model reference | Good reference for manifest, lifecycle, commands, settings, and permission concepts; do not depend on proprietary app behavior. |
| Monaco Editor | https://github.com/microsoft/monaco-editor | MIT | Not recommended as main editor | Excellent code editor, but too heavy and code-centric for a Typora-like Markdown writing experience. |

## Recommendation

Use Milkdown as the primary Typora-like editor core and CodeMirror 6 as source mode.

Reasons:

1. Milkdown matches the product goal most directly: WYSIWYG Markdown editing, plugin-driven architecture, and Markdown-first design.
2. CodeMirror 6 provides a robust source editor without pulling in the weight and IDE assumptions of Monaco.
3. Both are compatible with a React/Electron/TypeScript renderer and permissive licensing.
4. The app can keep Markdown text as the canonical source while using editor state only as the interactive view.
5. Theme and plugin capabilities can be layered through CodeTool-owned APIs instead of exposing raw third-party internals.

## Decisions Confirmed

1. Editor core: Milkdown + CodeMirror 6.
2. Document model: file-first editor with directory and recent directory support.
3. File permissions: arbitrary file locations are allowed only through system open/save dialogs; no direct arbitrary path API for renderer or plugins.
4. Directory behavior: user can open directories and recent directories; implementation should still keep file operations in the main process.
5. Theme/plugin phase: first version supports theme compatibility plus built-in plugin toggles, not arbitrary user JavaScript plugins.
6. Export: first version includes HTML and PDF export using the current theme.
7. Save behavior: automatic save is enabled by default; no version snapshot in first version.
8. Image assets: pasted or dropped images are saved to an `assets/` directory next to the current Markdown file, and Markdown uses relative paths.
9. Theme compatibility: support Typora/Obsidian CSS on a best-effort basis through scoped CSS and compatibility mappings; do not promise strict pixel-perfect compatibility.
10. Built-in Markdown features: GFM, math, Mermaid, code highlighting, frontmatter, TOC, and outline.
11. Data source of truth: Markdown text is canonical, not HTML or editor JSON.
12. Default view: Typora-like WYSIWYG view; source and split preview are available as view modes.
13. Directory sidebar: visible when a directory is open, collapsed for single-file mode, with user preference remembered later if needed.

## Risks

1. Default autosave without local snapshots can overwrite user files with no app-level recovery path.
2. Best-effort Typora/Obsidian CSS compatibility will not perfectly reproduce all third-party themes because editor DOM structures differ.
3. Mermaid and math rendering need isolation/error handling so invalid blocks do not break the document.
4. PDF export fidelity depends on print CSS and Electron rendering behavior.
5. Future user plugin support must be sandboxed and permissioned; it should not be added as unrestricted renderer JavaScript.
