# Copilot Instructions for CodeTool

## Build and test commands

- Build the Electron workspace from the terminal with `pnpm build`.
- Run type checking with `pnpm typecheck`.
- Run the full test suite with `pnpm test`.
- In this repo, treat `pnpm build` as the minimum CLI verification. Do not claim tests passed unless `pnpm test` actually succeeded.

## High-level architecture

- `packages/shared` contains the bundled tool catalog, shared IPC channel definitions, IPC contract types, shared domain models, and pure utility logic.
- `packages/main` is the Electron main process. It owns SQLite setup, asset persistence, diagnostics logging, MiniMax credential storage, MiniMax HTTP clients, task runners, and IPC registration.
- `packages/preload` exposes the typed API surface to the renderer through `contextBridge`.
- `packages/renderer` contains the React workbench shell, routes, and per-tool UI.
- `packages/shared/src/tool-catalog.ts` is the canonical tool catalog. `packages/renderer/src/App.tsx` and `packages/renderer/src/components/workbench.tsx` should stay aligned with it.

## Key conventions

- When adding, removing, or renaming a tool, treat tool wiring as a cross-file change. Update `packages/shared/src/tool-catalog.ts`, the renderer routes in `packages/renderer/src/App.tsx`, any affected navigation UI in `packages/renderer/src/components/workbench.tsx`, relevant tests, and `README.md`.
- Keep privileged work in the main process. Secrets, file system access, SQLite writes, and external provider requests should not move into the renderer.
- Treat AI changes as end-to-end integration work. When changing AI Chat, Speech, Image, or Music, inspect `packages/main/src/providers/minimax/`, `packages/main/src/ipc/register.ts`, the shared AI types and IPC contract under `packages/shared/src/`, the renderer tool page under `packages/renderer/src/tools/`, and the related Vitest coverage.
- If an AI request/response shape, asset format, or task event schema changes, update persistence and diagnostics in the same change. Check the history repository, asset store, logger, IPC types, and renderer task handling together so saved records and tool output remain consistent.
