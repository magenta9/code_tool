# Copilot Instructions for CodeTool

## Build and test commands

- Build the package from the terminal with `swift build`.
- Run the full test target with `make test`. The Makefile routes tests through `/Applications/Xcode.app/Contents/Developer` when available and uses an isolated scratch path, which avoids the recurring `no such module XCTest` / mixed-toolchain failures from raw `swift test`.
- Run a single test with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter CodeToolTests/testRegistryContainsElevenTools`.
- In this repo, treat `swift build` as the minimum CLI verification. Do not claim tests passed unless `make test`, Xcode tests, or an equivalent `swift test` run with the full Xcode toolchain actually succeeded.

## High-level architecture

- `Package.swift` currently defines four targets: `CodeToolApp` is the macOS executable entry point, `CodeToolCore` contains feature views/providers/persistence, `CodeToolFoundation` holds shared models/settings/tool metadata, and `CodeToolUI` contains the shared theme and UI shell.
- `Sources/CodeToolApp/CodeToolApp.swift` is thin. It launches `ContentView`, so most product behavior lives under `Sources/CodeToolCore/Views/`.
- `ToolRegistry.defaults` lives in `Sources/CodeToolFoundation/Tool.swift` and is the canonical tool catalog. `Sources/CodeToolCore/Views/ContentView.swift` renders the sidebar from that registry and routes each tool name to its screen.
- Shared UI primitives live in `Sources/CodeToolUI/`. `ToolWorkbench.swift` provides the standard header/layout, `Theme.swift` defines color/spacing/radius tokens, and `StyledComponents.swift` contains the reusable controls used across tool screens.
- AI features span more than one provider surface: MiniMax configuration/client code lives under `Sources/CodeToolCore/Providers/MiniMax/`, Claude CLI integration lives under `Sources/CodeToolCore/Providers/Claude/`, and persistence/restore behavior for AI tools lives under `Sources/CodeToolCore/Persistence/`.

## Key conventions

- When the agent needs clarification or a user decision, prefer the `ask_user` tool instead of asking in plain text. Keep clarification requests scoped to real blocking ambiguities so the user is not peppered with conversational follow-up questions.
- When adding, removing, or renaming a tool, treat tool wiring as a cross-file change. Update `ToolRegistry.defaults` in `Tool.swift`, the `ToolDetailView` switch in `ContentView.swift`, the `Tool.navigationTag` mapping in `ContentView.swift`, the tool-count and user-facing copy in `ContentView.swift`, `Tests/CodeToolTests/CodeToolTests.swift`, and `README.md`. History shows agents often touch only part of this path; `ToolRegistry.defaults` is the source of truth when other surfaces drift.
- New or refactored tool screens should be built from the shared shell (`ToolWorkbench`, `StyledPanel`, `StyledButton`, `StyledTextEditor`, `ToolMessageBanner`, `AppTheme`) instead of introducing a one-off top-level layout.
- Keep terminal builds SwiftPM-safe. This codebase already moved away from bare `#Preview {}` usage because it breaks command-line builds; prefer `PreviewProvider` wrapped in `#if DEBUG` for preview code.
- Treat AI changes as end-to-end integration work, not isolated view tweaks. When changing AI Chat / Speech / Image / Music, inspect the relevant settings store/provider, the transport client (`MiniMaxAPIClient.swift` or `ClaudeCLIClient.swift`), the `AI*View.swift` surface, any shared chat/composer helpers, and the mocked request or streaming tests in `Tests/CodeToolTests/CodeToolTests.swift`. Recent fixes repeatedly required coordinated updates across settings, transport parsing, UI state, and rendered tool output.
- If an AI request/response shape, streaming behavior, or output format changes, update persistence and restore paths in the same change. Check `HistoryStore.swift`, `HistoryDrawer.swift`, and any AI view restore logic so new records save correctly and older records remain readable after the schema/API shift.
