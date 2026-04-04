# Refactor Plan: Tool Catalog Routing

## Problem

Tool identity, metadata, and routing are currently split across several maintenance points.

- [Sources/CodeToolFoundation/Tool.swift](Sources/CodeToolFoundation/Tool.swift) already owns `ToolRegistry.defaults`, which is the closest thing to a canonical tool catalog.
- [Sources/CodeToolCore/Views/ContentView.swift](Sources/CodeToolCore/Views/ContentView.swift) still routes tool detail views by comparing display names in `ToolDetailView` and derives `navigationTag` from those same names.
- [README.md](README.md) and [Tests/CodeToolTests/CodeToolTests.swift](Tests/CodeToolTests/CodeToolTests.swift) duplicate tool count and membership knowledge.

This makes the tool system fragile. Display text acts as internal identity, so a rename can silently become a routing change, a documentation drift, and a test failure.

## Proposed Interface

Introduce a stable tool identity in Foundation and a single destination registry in Core.

- `ToolID`
  - Stable internal identity, independent from display text.
- `ToolCatalogEntry`
  - Catalog metadata including title, description, icon, category, order, and optional legacy route aliases.
- `ToolCatalog`
  - Single source of truth for bundled tools.
- `ToolDestinationRegistry`
  - Core-only mapping from `ToolID` to a detail view factory.
- `ToolRouteSlug`
  - Explicit presentation-facing route label used for chips or deep links, not derived from `name`.

Interface sketch:

```swift
public enum ToolID: String, CaseIterable, Codable {
    case jsonTool
    case imageConverter
    case jsonDiff
    case timestampConverter
    case jwtTool
    case wordCloud
    case aiChat
    case aiSpeech
    case aiImage
    case aiMusic
}

public struct ToolCatalogEntry: Identifiable, Hashable {
    public let id: ToolID
    public let title: String
    public let description: String
    public let systemImage: String
    public let category: ToolCategory
    public let routeSlug: String
}
```

Usage sketch:

```swift
let entry = ToolCatalog.bundled.first { $0.id == selectedToolID }
let destination = ToolDestinationRegistry.makeView(for: selectedToolID)
```

What this hides internally:

- display-name-to-destination matching
- route-slug derivation rules
- catalog ordering and membership decisions
- alias handling for future renames

## Dependency Strategy

- **Primary category**: In-process
  - This is a pure metadata and routing boundary with no external I/O.
- Foundation should own stable identities and catalog metadata.
- Core should own view construction and routing, depending on Foundation but not the reverse.
- README and tests should validate catalog output rather than maintain a second catalog.

## Testing Strategy

- **New boundary tests to write**
  - Every catalog entry has a unique stable `ToolID` and route slug.
  - Every bundled catalog entry resolves to exactly one destination.
  - Catalog order and category counts match the landing page grouping.
  - Legacy aliases, if introduced, resolve to the intended current tool.
- **Old tests to delete or collapse**
  - Replace [Tests/CodeToolTests/CodeToolTests.swift#L274](Tests/CodeToolTests/CodeToolTests.swift#L274) with catalog completeness and destination-coverage tests.
  - Replace [Tests/CodeToolTests/CodeToolTests.swift#L278](Tests/CodeToolTests/CodeToolTests.swift#L278) and [Tests/CodeToolTests/CodeToolTests.swift#L284](Tests/CodeToolTests/CodeToolTests.swift#L284) with uniqueness and exact-membership tests keyed by `ToolID` instead of display names.
  - Keep lightweight smoke coverage for `Tool` initialization, but move routing verification away from string matching.
- **Test environment needs**
  - Pure in-process tests only; no filesystem or external services needed.
  - Optional README consistency check if documentation keeps a generated or validated tool list.

## Implementation Phases

### Phase 1: Add Stable Tool Identity in Foundation
- [x] Introduce `ToolID` and enrich the catalog model in [Sources/CodeToolFoundation/Tool.swift](Sources/CodeToolFoundation/Tool.swift).
- [x] Preserve current titles, descriptions, icons, categories, and order.
- [ ] Verification criteria: `swift build` succeeds; all bundled tools have unique IDs and route slugs.

### Phase 2: Introduce a Core Destination Registry
- [x] Replace name-based routing in [Sources/CodeToolCore/Views/ContentView.swift](Sources/CodeToolCore/Views/ContentView.swift) with `ToolID`-based destination lookup.
- [x] Move route-slug display logic away from `switch name` and into explicit catalog metadata.
- [ ] Verification criteria: every catalog entry resolves to one detail view without using display-name comparisons.

### Phase 3: Derive UI Counts and Labels from the Catalog
- [x] Update landing-page counts and grouped sections to derive from the catalog rather than hard-coded expectations.
- [x] Keep user-visible copy stable while changing the source of truth.
- [ ] Verification criteria: the UI still shows the same tool titles and counts, but no count is duplicated as a magic constant.

### Phase 4: Align Tests and Documentation with the Boundary
- [x] Update [Tests/CodeToolTests/CodeToolTests.swift](Tests/CodeToolTests/CodeToolTests.swift) to validate catalog and destination boundaries rather than raw counts or names.
- [x] Update [README.md](README.md) so tool membership references align with the catalog boundary.
- [ ] Verification criteria: catalog tests fail when a tool is added without routing, and routing tests fail when a destination exists without a catalog entry.

## Current Status

- `ToolID`, `ToolCatalogEntry`, and `ToolCatalog` now form the canonical bundled catalog in Foundation, and `ToolRegistry.defaults` is derived from that catalog instead of duplicating the source of truth.
- `ToolDestinationRegistry` now owns `ToolID` to view construction in Core, and `ContentView` no longer routes by matching display names.
- Catalog completeness, route-slug uniqueness, and destination coverage are now enforced in tests, so this refactor is effectively complete aside from keeping future tool additions wired through the same boundary.

## Architectural Guidance

- Display text is not identity. Keep user-facing labels separate from internal routing keys.
- Foundation should answer "what tools exist". Core should answer "how to present one tool".
- The landing page, sidebar, tests, and documentation should all consume the same catalog model.
- Adding a tool should become a bounded change: one catalog entry and one destination registration, plus explicit documentation updates if needed.
- Avoid deriving route metadata from names in the future; make route slugs explicit and stable.
