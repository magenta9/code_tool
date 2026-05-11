# CodeTool

CodeTool is a macOS Electron workbench for local-first developer utilities, MiniMax-powered generators, and Pi coding-agent sessions.

## Features

- **JSON Tool** – Format, validate, minify, and analyze JSON data
- **Image Converter** – Convert images between Base64 strings and files
- **JSON Diff** – Compare two JSON objects and find structural differences
- **Timestamp Converter** – Convert timestamps, ISO strings, and local dates
- **JWT Tool** – Encode and decode JWT headers, payloads, and expiry claims
- **Word Cloud** – Tokenize text and rank terms for deterministic word clouds
- **Kanban** – Plan local boards in List or Kanban view with rich task details
- **AI Chat** – Stream MiniMax chat responses with history and diagnostics
- **Pi Agent** – Run Pi coding-agent sessions with real tool calls, queue state, and workflow traces
- **AI Speech** – Generate speech audio with MiniMax and keep output history
- **AI Image** – Generate images with MiniMax prompts and aspect settings
- **AI Music** – Generate MiniMax music tasks with timeout diagnostics

## Requirements

| Requirement | Version |
|-------------|---------|
| macOS | 13.0 (Ventura) or later |
| Node.js | 20 or later |
| pnpm | 9.15 or later |

## Project Structure

```
CodeTool/
├── package.json
├── pnpm-workspace.yaml
├── electron-builder.yml
├── tsconfig.base.json
├── vitest.config.ts
├── packages/
│   ├── shared/                          # Tool catalog, IPC contract, shared types and pure logic
│   ├── main/                            # Electron main process, IPC, MiniMax provider, SQLite, assets, logs
│   ├── preload/                         # contextBridge API surface
│   └── renderer/                        # React + Vite + Tailwind workbench UI
└── thoughts/
    └── shared/
```

## Getting Started

Install dependencies once:

```bash
pnpm install
```

Start package watchers, the renderer dev server, and Electron:

```bash
make dev
```

Start only package watchers and the renderer dev server:

```bash
make dev-watch
```

`make dev-electron` remains available when you want to launch Electron against an already-running renderer server and current build output.

## Build and Test

Build all workspace packages:

```bash
pnpm build
```

Run type checking:

```bash
pnpm typecheck
```

Run Vitest suites:

```bash
pnpm test
```

If you prefer a single entry point for local workflows:

```bash
make verify
```

Package after verification:

```bash
make deploy
```

Package the macOS app:

```bash
pnpm package:mac
```

## Architecture

- `packages/shared` defines the bundled tool catalog, typed IPC contract, shared domain types, and pure utility logic.
- `packages/main` owns secrets, MiniMax HTTP calls, SQLite metadata, asset persistence, diagnostics logging, and IPC handlers.
- `packages/preload` exposes the shared contract to the renderer through `contextBridge`.
- `packages/renderer` implements the workbench shell, routes, and tool screens in React.

### Tool Catalog Routing

`packages/shared/src/tool-catalog.ts` is the canonical tool catalog. The renderer sidebar, routes, and catalog tests should stay aligned with that file rather than duplicating tool membership in multiple places.

### Data and Secrets

- MiniMax credentials are stored in the main process through macOS Keychain via `keytar`.
- History metadata is stored in SQLite under the app `userData` path.
- Generated image, speech, and music assets are written to the Electron asset store under the same `userData/electron` root.
- Diagnostics are written by the main process and exposed to the renderer through typed IPC.
