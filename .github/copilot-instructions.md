# Copilot Instructions for CodeTool

## Build and test commands

- Build the package from the terminal with `swift build`.
- Run the full test target with `swift test`.
- Run a single test with `swift test --filter CodeToolTests/testRegistryContainsElevenTools`.
- In this repo, treat `swift build` as the minimum CLI verification. `swift test` currently fails in this environment with `no such module XCTest`, so do not claim tests passed unless you actually got `swift test` or Xcode tests green.

## High-level architecture

- `Package.swift` defines two targets: `CodeToolApp` is the macOS executable entry point, and `CodeToolCore` contains the app’s shared models, views, API client, and reusable UI building blocks.
- `Sources/CodeToolApp/CodeToolApp.swift` is thin. It launches `ContentView`, so most product behavior lives under `Sources/CodeToolCore/`.
- `ToolRegistry.defaults` in `Sources/CodeToolCore/Tool.swift` is the canonical tool catalog. `ContentView.swift` renders the sidebar from that registry and routes each tool name to its screen in `ToolDetailView`.
- The AI feature set is centralized around MiniMax: `MiniMaxProvider.swift` stores API credentials and model choices in `UserDefaults`, `MiniMaxSettingsView.swift` is the configuration surface, and `MiniMaxAPIClient.swift` owns the shared request/response handling for chat, speech, image, and music.
- The current UI shell is shared. `ToolWorkbench.swift` provides the standard header/layout, `Theme.swift` defines color/spacing/radius tokens, and `StyledComponents.swift` contains the reusable controls used across tool screens.

## Key conventions

- When adding, removing, or renaming a tool, treat tool wiring as a cross-file change. Update `ToolRegistry.defaults` in `Tool.swift`, the `ToolDetailView` switch in `ContentView.swift`, the `Tool.navigationTag` mapping in `ContentView.swift`, the tool-count and user-facing copy in `ContentView.swift`, `Tests/CodeToolTests/CodeToolTests.swift`, and `README.md`. History shows agents often touch only part of this path; `ToolRegistry.defaults` is the source of truth when other surfaces drift.
- New or refactored tool screens should be built from the shared shell (`ToolWorkbench`, `StyledPanel`, `StyledButton`, `StyledTextEditor`, `ToolMessageBanner`, `AppTheme`) instead of introducing a one-off top-level layout.
- Keep terminal builds SwiftPM-safe. This codebase already moved away from bare `#Preview {}` usage because it breaks command-line builds; prefer `PreviewProvider` wrapped in `#if DEBUG` for preview code.
- MiniMax changes need contract-level validation, not just a successful compile. When changing any AI tool, inspect `MiniMaxProvider.swift`, `MiniMaxAPIClient.swift`, the relevant `AI*View.swift`, and the mocked request tests in `Tests/CodeToolTests/CodeToolTests.swift`. Speech and music endpoints have already needed follow-up fixes after the initial feature landing.
