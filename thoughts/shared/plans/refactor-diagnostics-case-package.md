# Refactor Plan: Diagnostics Case Package

## Problem

Diagnostics export is currently assembled across multiple modules instead of being owned by one deep boundary.

- [Sources/CodeToolCore/Observability/AppLogger.swift](Sources/CodeToolCore/Observability/AppLogger.swift) writes to unified logging, file logging, and diagnostics recording sinks.
- [Sources/CodeToolCore/Observability/Diagnostics.swift](Sources/CodeToolCore/Observability/Diagnostics.swift) stores events, builds trace summaries, and exports packages.
- [Sources/CodeToolCore/Persistence/HistoryStore.swift](Sources/CodeToolCore/Persistence/HistoryStore.swift) is called during diagnostics export to enrich a package with history matches.
- [Sources/CodeToolCore/Observability/DiagnosticsView.swift](Sources/CodeToolCore/Observability/DiagnosticsView.swift) triggers export and therefore depends on the current shape of that multi-store assembly.

The missing deep module is a single owner for a diagnostics case package: one snapshot that contains related events, trace summary, history matches, export metadata, and sink-failure information.

## Proposed Interface

Introduce a diagnostics case package module that owns aggregation and export.

- `DiagnosticsCaseID`
  - Stable identifier rooted in `referenceID` or another exported-case key.
- `DiagnosticsCaseSnapshot`
  - Immutable snapshot of all data that belongs to one case.
- `DiagnosticsCaseService`
  - Single entry point for building and exporting snapshots.
- `DiagnosticsEventStorePort`
  - Reads diagnostics events and metrics.
- `DiagnosticsHistoryLookupPort`
  - Reads related history matches without leaking `HistoryStore` details upward.
- `DiagnosticsExportWriter`
  - Serializes a snapshot to disk.

Interface sketch:

```swift
public struct DiagnosticsCaseSnapshot: Codable, Sendable {
    public let caseID: DiagnosticsCaseID
    public let relatedEvents: [AppLogEntry]
    public let traceSummary: DiagnosticsTraceSummary?
    public let historyMatches: [DiagnosticsHistoryMatch]
    public let metricSummaries: [DiagnosticsMetricSummary]
    public let warnings: [DiagnosticsCaseWarning]
}

public protocol DiagnosticsCaseServicing: Sendable {
    func snapshot(referenceID: String?) async throws -> DiagnosticsCaseSnapshot
    func export(referenceID: String?) async throws -> URL
}
```

Usage sketch:

```swift
let exportURL = try await diagnosticsCaseService.export(referenceID: selectedReferenceID)
```

What this hides internally:

- event aggregation and sorting
- history enrichment rules
- sink-failure and missing-data warnings
- export manifest shape
- snapshot consistency rules during export

## Dependency Strategy

- **Primary category**: Local-substitutable
  - Diagnostics events, metrics, and history enrichment all use local storage and are testable with temporary directories.
- **Secondary category**: In-process
  - Case aggregation rules and warning policies are pure domain logic.
- AppLogger should remain a producer of log entries, not the owner of export semantics.
- The case service should depend on ports for events, history lookup, and export writing.

## Testing Strategy

- **New boundary tests to write**
  - A case snapshot contains stable, ordered related events, trace summary, history matches, and metrics for one `referenceID`.
  - Export uses one snapshot and does not mix pre- and mid-export writes.
  - Sink failures or missing data become explicit warnings instead of silent omissions.
  - Nil or empty `referenceID` exports a recent-issues package without history enrichment.
- **Old tests to delete or collapse**
  - Replace [Tests/CodeToolTests/CodeToolTests.swift#L811](Tests/CodeToolTests/CodeToolTests.swift#L811) with case-service snapshot tests.
  - Replace [Tests/CodeToolTests/CodeToolTests.swift#L858](Tests/CodeToolTests/CodeToolTests.swift#L858) with export tests rooted in one public case-service entry point.
  - Reduce UI-driven export tests so [Sources/CodeToolCore/Observability/DiagnosticsView.swift](Sources/CodeToolCore/Observability/DiagnosticsView.swift) only needs trigger and state coverage.
- **Test environment needs**
  - Temporary directories for logs, diagnostics, and history.
  - Fixture entries for sink-failure and missing-history scenarios.
  - Snapshot-based assertions for export payload structure.

## Implementation Phases

### Phase 1: Define Case Snapshot Domain
- [x] Add `DiagnosticsCaseID`, `DiagnosticsCaseSnapshot`, `DiagnosticsCaseWarning`, and case-service protocols under `Sources/CodeToolCore/Observability/`.
- [x] Capture current export payload requirements in one explicit model.
- [ ] Verification criteria: snapshot model fully represents current export needs, including warnings and optional sections.

### Phase 2: Move Aggregation Behind a Case Service
- [x] Introduce a case service that builds snapshots from diagnostics events, metrics, and history lookup ports.
- [x] Update [Sources/CodeToolCore/Observability/Diagnostics.swift](Sources/CodeToolCore/Observability/Diagnostics.swift) so export delegates to that service.
- [ ] Verification criteria: export behavior remains unchanged from the caller perspective while aggregation moves behind one API.

### Phase 3: Narrow History Enrichment and Reference Matching
- [x] Replace direct export-time dependence on `HistoryStore.diagnosticsMatches` with a narrower lookup port.
- [ ] Define explicit matching rules for empty, duplicated, or conflicting `referenceID` cases.
- [ ] Verification criteria: case snapshot tests cover success, missing history, duplicate IDs, and empty IDs.

### Phase 4: Decouple AppLogger from Case Semantics
- [x] Keep [Sources/CodeToolCore/Observability/AppLogger.swift](Sources/CodeToolCore/Observability/AppLogger.swift) focused on emitting entries and reporting sink failures.
- [x] Route any sink-failure information into case warnings rather than implicit export gaps.
- [ ] Verification criteria: sink failure in one path does not prevent case export, and warnings surface in the exported payload.

### Phase 5: Simplify UI and Reduce Cross-Store Tests
- [x] Update [Sources/CodeToolCore/Observability/DiagnosticsView.swift](Sources/CodeToolCore/Observability/DiagnosticsView.swift) to depend on one export entry point.
- [ ] Replace multi-singleton integration tests with case-service boundary tests and a minimal end-to-end export path.
- [ ] Verification criteria: UI trigger tests stay small; export correctness is covered at the case boundary.

## Current Status

- `DiagnosticsCaseID`, `DiagnosticsCaseSnapshot`, `DiagnosticsCaseWarning`, `DiagnosticsCaseService`, `DiagnosticsCaseServicing`, and `DiagnosticsExportWriter` are all in place under `Sources/CodeToolCore/Observability/`.
- `Diagnostics.swift` and `DiagnosticsView.swift` now delegate snapshot/export work through `DiagnosticsCaseService`, and sink-failure warnings are surfaced through the case snapshot/export payload.
- The remaining gap is mostly tightening reference-matching rules and shrinking the older cross-store integration coverage down to the new case-service boundary.

## Architectural Guidance

- A diagnostics case package is a product concept, not an accidental combination of stores.
- Export should operate on one immutable snapshot, not on live queries interleaved with serialization.
- History enrichment is part of case assembly and should not leak its storage details upward.
- Sink failures should be captured as explicit warnings so export remains truthful instead of falsely green.
- Keep UI thin: selecting a case and exporting it should not require knowledge of how data is assembled.
- Keep log writing, diagnostics storage, and export assembly as separate responsibilities connected through ports.
