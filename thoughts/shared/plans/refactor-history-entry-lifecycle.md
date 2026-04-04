# Refactor Plan: History Entry Lifecycle

## Problem

The history subsystem is organized around record types instead of around the lifecycle of one history entry.

- [Sources/CodeToolCore/Persistence/HistoryStore.swift](Sources/CodeToolCore/Persistence/HistoryStore.swift) defines many concrete record types and exposes a wide surface of type-specific `save`, `list`, and `delete` methods.
- [Sources/CodeToolCore/Persistence/HistoryDrawer.swift](Sources/CodeToolCore/Persistence/HistoryDrawer.swift) repeats per-record display logic for titles, subtitles, icons, and timestamps.
- Tool views construct and restore concrete record types directly, which spreads type knowledge across persistence, UI, and feature code.
- `diagnosticsMatches` in [Sources/CodeToolCore/Persistence/HistoryStore.swift](Sources/CodeToolCore/Persistence/HistoryStore.swift) shows the storage layer also owns cross-record query semantics, which further widens the seam.

This makes the codebase shallow: adding or changing a history shape requires synchronized edits across record definitions, storage APIs, drawer adapters, restore logic, and tests.

## Proposed Interface

Introduce a unified history entry model with pluggable codecs and presenters.

- `HistoryEntry`
  - A single stored history envelope with stable identity, tool identity, timestamp, summary fields, payload kind, and version.
- `HistoryPayloadCodec`
  - Encodes and decodes feature-specific payloads.
- `HistoryEntryPresenter`
  - Produces drawer title, subtitle, icon, preview, and restore metadata.
- `HistoryRepository`
  - Unified append, list, delete, load-asset, and query APIs.
- `ToolHistoryDefinition`
  - Registers codec, presenter, and restore behavior per tool.

Interface sketch:

```swift
public struct HistoryEntry: Codable, Identifiable, Sendable {
    public let id: UUID
    public let toolID: ToolHistoryID
    public let createdAt: Date
    public let schemaVersion: Int
    public let summary: HistoryEntrySummary
    public let payload: Data
}

public protocol HistoryPayloadCodec: Sendable {
    associatedtype Payload: Sendable
    func encode(_ payload: Payload) throws -> HistoryEntry
    func decode(_ entry: HistoryEntry) throws -> Payload
}

public protocol HistoryRepository: Sendable {
    func append(_ entry: HistoryEntry, assets: [HistoryAsset]) async throws
    func list(_ query: HistoryQuery) async throws -> [HistoryEntry]
    func delete(id: UUID) async throws
}
```

Usage sketch:

```swift
let entry = try imageHistoryDefinition.codec.makeEntry(from: completedGeneration)
try await historyRepository.append(entry, assets: completedGeneration.assets)
```

What this hides internally:

- concrete JSON file layout
- schema versioning and backward compatibility
- asset naming and deletion rules
- drawer summary generation
- cross-tool history queries

## Dependency Strategy

- **Primary category**: Local-substitutable
  - The core dependency is local filesystem persistence, which is already testable with temporary directories.
- **Secondary category**: In-process
  - Summary generation, codec registration, and presenter logic are in-process domain concerns.
- The unified repository should not depend on SwiftUI views.
- History drawer UI should consume presenter output rather than concrete record types.

## Testing Strategy

- **New boundary tests to write**
  - Unified append/list/delete behavior for a generic `HistoryEntry`.
  - Legacy record JSON decodes into new entry shapes through compatibility codecs.
  - Asset files are written and removed exactly as declared by the entry.
  - Presenter output remains stable for drawer rendering and restore flows.
  - Cross-tool queries such as diagnostics lookups use entry summaries, not record-type branching.
- **Old tests to delete or collapse**
  - Collapse record-specific CRUD tests into repository contract tests.
  - Replace [Tests/CodeToolTests/CodeToolTests.swift#L1157](Tests/CodeToolTests/CodeToolTests.swift#L1157) with entry-plus-assets deletion tests rooted in declared asset metadata.
  - Rework [Tests/CodeToolTests/CodeToolTests.swift#L1514](Tests/CodeToolTests/CodeToolTests.swift#L1514) to validate stable conversation identity through the unified history definition rather than a concrete record API.
  - Keep payload compatibility tests such as [Tests/CodeToolTests/CodeToolTests.swift#L1098](Tests/CodeToolTests/CodeToolTests.swift#L1098) and [Tests/CodeToolTests/CodeToolTests.swift#L1134](Tests/CodeToolTests/CodeToolTests.swift#L1134), but move them under codec compatibility coverage.
- **Test environment needs**
  - Temporary directories for storage.
  - Fixture JSON for legacy schemas.
  - Entry-definition registration for at least one AI tool and one DevTool.

## Implementation Phases

### Phase 1: Inventory Current Record Shapes
- [x] Enumerate all history record types, stored assets, drawer metadata rules, and restore paths.
- [x] Define which fields are required for summary, restore, diagnostics, and deletion.
- [ ] Verification criteria: every existing record type has a mapped compatibility shape and asset policy.

### Phase 2: Introduce Unified Entry Model and Repository API
- [x] Add `HistoryEntry`, `HistoryQuery`, `HistoryAsset`, and `HistoryRepository` under `Sources/CodeToolCore/Persistence/`.
- [x] Keep existing concrete records temporarily as compatibility payloads behind codecs.
- [ ] Verification criteria: `swift build` succeeds and repository contract tests pass against a temporary directory.

### Phase 3: Add Codecs and Presenter Definitions
- [x] Create per-tool history definitions that encode payloads, expose summaries, and restore feature state.
- [ ] Move drawer title, subtitle, and icon generation out of [Sources/CodeToolCore/Persistence/HistoryDrawer.swift](Sources/CodeToolCore/Persistence/HistoryDrawer.swift) type extensions into presenters.
- [ ] Verification criteria: drawer UI renders via presenter output without importing concrete record types.

### Phase 4: Migrate Feature Call Sites
- [ ] Update AI tools and DevTools to append unified entries instead of calling type-specific store methods.
- [ ] Update restore flows to decode through tool history definitions.
- [ ] Verification criteria: one AI tool and one DevTool are fully migrated end to end with no direct use of type-specific APIs.

### Phase 5: Remove Legacy Store Surface and Tighten Queries
- [ ] Replace `diagnosticsMatches` branching with entry-summary-based matching or pluggable query helpers.
- [ ] Delete obsolete type-specific storage APIs after all callers migrate.
- [ ] Verification criteria: no feature code depends on record-specific `save`, `list`, or `delete` methods; compatibility decoding remains covered.

## Current Status

- The unified boundary is in place: `HistoryEntry`, `HistoryQuery`, `HistoryAsset`, `HistoryRepository`, per-tool codecs/definitions, and repository contract tests all exist.
- `AIChatView` and `JSONToolView` now use codec-backed `upsert`, `payloads`, `delete`, and `clear` helpers, which proves the migration path for one AI surface and one DevTool surface.
- The remaining work is the broader caller migration and the final drawer cleanup; `HistoryDrawer.swift` still carries legacy item conformances, and many feature restore/save paths still use typed `HistoryStore` APIs.

## Architectural Guidance

- Treat history as one lifecycle boundary: create entry, store assets, list entries, restore from entry, delete by entry identity.
- Keep payload-specific knowledge behind codecs and presenters.
- The repository should own filesystem layout and asset cleanup policy.
- The drawer should render view models, not concrete persistence types.
- Compatibility should be explicit. Prefer dual-read, single-write migration until all old records are safely readable.
- Diagnostics queries should consume summaries or registered query adapters, not reopen the type explosion in the repository.
