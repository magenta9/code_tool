# CodeTool

A macOS developer toolkit built with Swift and SwiftUI, providing a collection of everyday coding utilities in a native Mac application.

## Features

- **JSON Tool** – Format, validate, minify, and analyze JSON data
- **Image Converter** – Convert images between Base64 strings and files
- **JSON Diff** – Compare two JSON objects and find differences
- **Timestamp Converter** – Convert between timestamps and human-readable dates
- **JWT Tool** – Encode and decode JWT tokens
- **Word Cloud** – Generate word cloud visualizations from text
- **AI Chat** – Minimal streaming text chat powered by MiniMax
- **AI Speech** – Stream text-to-speech with MiniMax Speech 2.8
- **AI Image** – Generate images with MiniMax image-01 using text alone or reference images via drag-and-drop, file selection, or paste
- **AI Music** – Generate music with MiniMax Music-2.5

## Requirements

| Requirement | Version |
|-------------|---------|
| macOS | 13.0 (Ventura) or later |
| Xcode | 15.0 or later |
| Swift | 5.9 or later |

## Project Structure

```
CodeTool/
├── Package.swift                        # Swift Package Manager manifest
├── Sources/
│   ├── CodeToolApp/                     # App entry point & lifecycle
│   ├── CodeToolCore/                    # Providers, views, persistence, observability
│   │   ├── Execution/
│   │   ├── Observability/
│   │   ├── Persistence/
│   │   ├── Providers/
│   │   │   └── MiniMax/
│   │   └── Views/
│   ├── CodeToolFoundation/              # Shared models, settings, tool catalog
│   └── CodeToolUI/                      # Shared SwiftUI shell and styling
└── Tests/
    └── CodeToolTests/
        └── CodeToolTests.swift          # Core regression coverage
```

## Getting Started

### Clone and open in Xcode

```bash
git clone https://github.com/magenta9/code_tool.git
cd code_tool
open Package.swift
```

Xcode will resolve the Swift package and you can run the app with ⌘R.

### Build from the command line (macOS only)

```bash
swift build
```

### Run tests

```bash
make test
```

If your shell is pointed at Command Line Tools instead of full Xcode, direct `swift test`
may fail with `no such module 'XCTest'`. In that case, either use `make test` or run:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
```

## Architecture

The project is split into four targets:

- **`CodeToolApp`** – The macOS executable entry point that wires up the SwiftUI app lifecycle.
- **`CodeToolCore`** – Feature views, provider integrations, persistence, and observability.
- **`CodeToolFoundation`** – Shared models, settings wrappers, tool metadata, and user-facing error types.
- **`CodeToolUI`** – Shared styling, layout shells, and reusable UI primitives.

### Tool Catalog Routing

Every bundled tool has a stable `ToolID` enum case (defined in `CodeToolFoundation/Tool.swift`).
`ToolRegistry.defaults` is the single source of truth for tool metadata — titles, descriptions,
icons, categories, and route slugs are all derived from the catalog.

Detail-view routing in `ContentView.swift` switches on `ToolID` rather than display names,
so renaming a tool's title never silently breaks routing. The `ToolViewCache` also keys
retained views by `ToolID`. Landing-page counts and category sections are computed from
the catalog at runtime.

## AI Image Workflow

The **AI Image** tool now supports a reference-driven workbench:

- Stage one or more reference images with **drag-and-drop**, **Add Images…**, or **Cmd+V paste**
- Mix references with a prompt for MiniMax `image-01`
- Choose either an **aspect-ratio preset** or a **custom width/height**
- Tune **image count**, **seed**, and **prompt optimizer**
- Restore prior prompts, parameters, references, and outputs from local history
