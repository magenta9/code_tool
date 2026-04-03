# CodeTool

A macOS developer toolkit built with Swift and SwiftUI, providing a collection of everyday coding utilities in a native Mac application.

## Features

- **JSON Tool** – Format, validate, minify, and analyze JSON data
- **Image Converter** – Convert images between Base64 strings and files
- **JSON Diff** – Compare two JSON objects and find differences
- **Timestamp Converter** – Convert between timestamps and human-readable dates
- **JWT Tool** – Encode and decode JWT tokens
- **Word Cloud** – Generate word cloud visualizations from text

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
│   │   ├── CodeToolApp.swift            # @main SwiftUI App struct
│   │   └── AppDelegate.swift            # NSApplicationDelegate
│   └── CodeToolCore/                    # Reusable core library
│       ├── Tool.swift                   # Tool model & registry
│       ├── ContentView.swift            # Main SwiftUI view hierarchy
│       ├── JSONToolView.swift           # JSON formatter/validator/minifier
│       ├── ImageConverterView.swift     # Image ↔ Base64 converter
│       ├── JSONDiffView.swift           # JSON comparison tool
│       ├── TimestampConverterView.swift # Timestamp ↔ date converter
│       ├── JWTToolView.swift            # JWT encoder/decoder
│       └── WordCloudView.swift          # Word cloud generator
└── Tests/
    └── CodeToolTests/
        └── CodeToolTests.swift          # Unit tests for CodeToolCore
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

The project is split into two targets:

- **`CodeToolCore`** – A reusable library that contains the data models, view hierarchy, and business logic. This can be imported and tested independently.
- **`CodeToolApp`** – The executable entry point that wires up the SwiftUI `App` lifecycle and `AppDelegate`.
