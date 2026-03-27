# CodeTool

A macOS developer toolkit built with Swift and SwiftUI, providing a collection of everyday coding utilities in a native Mac application.

## Features

- **JSON Formatter** – Format and validate JSON documents
- **Base64 Encoder** – Encode and decode Base64 strings
- **UUID Generator** – Generate random UUIDs
- **Hash Calculator** – Compute MD5, SHA-1, and SHA-256 hashes

## Requirements

| Requirement | Version |
|-------------|---------|
| macOS | 13.0 (Ventura) or later |
| Xcode | 15.0 or later |
| Swift | 5.9 or later |

## Project Structure

```
CodeTool/
├── Package.swift                  # Swift Package Manager manifest
├── Sources/
│   ├── CodeToolApp/               # App entry point & lifecycle
│   │   ├── CodeToolApp.swift      # @main SwiftUI App struct
│   │   └── AppDelegate.swift      # NSApplicationDelegate
│   └── CodeToolCore/              # Reusable core library
│       ├── Tool.swift             # Tool model & registry
│       └── ContentView.swift      # Main SwiftUI view hierarchy
└── Tests/
    └── CodeToolTests/
        └── CodeToolTests.swift    # Unit tests for CodeToolCore
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
swift test
```

## Architecture

The project is split into two targets:

- **`CodeToolCore`** – A reusable library that contains the data models, view hierarchy, and business logic. This can be imported and tested independently.
- **`CodeToolApp`** – The executable entry point that wires up the SwiftUI `App` lifecycle and `AppDelegate`.
