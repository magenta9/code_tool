# Refactor Plan: AI Execution Session

## Problem

The AI tool views currently own orchestration that should belong to a deeper module.

- [Sources/CodeToolCore/Views/AITools/AIChatView.swift](Sources/CodeToolCore/Views/AITools/AIChatView.swift), [Sources/CodeToolCore/Views/AITools/AISpeechView.swift](Sources/CodeToolCore/Views/AITools/AISpeechView.swift), [Sources/CodeToolCore/Views/AITools/AIImageView.swift](Sources/CodeToolCore/Views/AITools/AIImageView.swift), and [Sources/CodeToolCore/Views/AITools/ClaudeChatView.swift](Sources/CodeToolCore/Views/AITools/ClaudeChatView.swift) each generate or carry `referenceID`, start work, manage streaming state, log failures, and persist history.
- Observability and persistence are coupled back into those views through [Sources/CodeToolCore/Observability/AppLogger.swift](Sources/CodeToolCore/Observability/AppLogger.swift), [Sources/CodeToolCore/Observability/Diagnostics.swift](Sources/CodeToolCore/Observability/Diagnostics.swift), and [Sources/CodeToolCore/Persistence/HistoryStore.swift](Sources/CodeToolCore/Persistence/HistoryStore.swift).
- Integration risk lives in the seams between request lifecycle, logging, diagnostics, and history. The same behavioral contract is repeated four times with slightly different error and cancellation paths.
- The codebase is harder to navigate because understanding a single AI action requires bouncing across view state, provider calls, logging, history writes, and diagnostics export.

## Proposed Interface

Introduce a deep module in `Sources/CodeToolCore/Execution/` that owns the lifecycle of one AI operation.

- `AIExecutionRequest`
  - Normalized input for chat, speech, image, music, and Claude CLI requests.
- `AIExecutionSession`
  - Starts work, tracks state, owns `referenceID`, and coordinates side effects.
- `AIExecutionEvent`
  - Normalized stream of lifecycle events such as `started`, `delta`, `artifact`, `completed`, `failed`, and `cancelled`.
- `AIExecutionResult`
  - Final normalized output used by history, diagnostics, and UI.
- `AIExecutionProvider`
  - Port implemented by MiniMax and Claude adapters.
- `AIExecutionHistorySink` and `AIExecutionDiagnosticsSink`
  - Ports for persistence and observability side effects.

Interface sketch:

```swift
public struct AIExecutionRequest: Sendable {
    public let tool: AIExecutionTool
    public let payload: AIExecutionPayload
}

public protocol AIExecutionProvider: Sendable {
    func execute(
        request: AIExecutionRequest,
        referenceID: String,
        emit: @escaping @Sendable (AIExecutionEvent) async -> Void
    ) async throws -> AIExecutionResult
}

public protocol AIExecutionSessioning: Sendable {
    var state: AIExecutionState { get async }
    var referenceID: String { get }
    func start() async
    func cancel() async
}
```

Usage sketch:

```swift
let session = AIExecutionSession(
    request: request,
    provider: provider,
    historySink: historySink,
    diagnosticsSink: diagnosticsSink
)

await session.start()
```

What this hides internally:

- `referenceID` creation and propagation
- streaming aggregation rules
- cancellation and finalize semantics
- logging and diagnostics event emission
- history persistence timing
- error normalization for UI consumption

## Dependency Strategy

- **Primary category**: Mock
  - MiniMax HTTP calls and Claude CLI process execution are true external dependencies.
  - The deep module should depend on provider ports, with mock or fake adapters in tests.
- **Secondary category**: Local-substitutable
  - History and diagnostics sinks can use temporary directories or in-memory test doubles.
- The execution module should not depend on SwiftUI types.
- View code should depend on session state and request construction only.

## Testing Strategy

- **New boundary tests to write**
  - A session emits stable lifecycle events for success, failure, and cancellation.
  - A single `referenceID` is used consistently across provider execution, diagnostics, and history.
  - Finalization is exactly-once for completed, failed, and cancelled sessions.
  - Streaming sessions append deltas correctly without leaking provider-specific event shapes to the UI.
  - Provider errors are normalized into user-facing failures without losing diagnostic detail.
- **Old tests to delete or collapse**
  - Replace [Tests/CodeToolTests/CodeToolTests.swift#L811](Tests/CodeToolTests/CodeToolTests.swift#L811) with execution-boundary tests that validate the same contract through one public surface.
  - Replace [Tests/CodeToolTests/CodeToolTests.swift#L858](Tests/CodeToolTests/CodeToolTests.swift#L858) with case-level export tests rooted in execution output rather than manual cross-store setup.
  - Collapse repeated view-level checks that only prove history or diagnostics were written after one specific tool action.
- **Test environment needs**
  - Mock provider adapters for MiniMax and Claude.
  - Temporary-directory or in-memory doubles for history and diagnostics sinks.
  - Keep provider payload tests that validate request JSON or CLI command composition; do not move those into execution tests.

## Implementation Phases

### Phase 1: Freeze Current Lifecycle Contract
- [ ] Inventory how each AI tool starts work, streams results, handles cancellation, persists history, and logs failures.
- [ ] Document shared invariants and tool-specific differences before moving code.
- [ ] Verification criteria: current lifecycle coverage is mapped for chat, speech, image, music, and Claude; no hidden dependency remains unclassified.

### Phase 2: Introduce Execution Domain Types
- [x] Add `AIExecutionRequest`, `AIExecutionEvent`, `AIExecutionResult`, and `AIExecutionState` under `Sources/CodeToolCore/Execution/`.
- [x] Add `AIExecutionProvider` and sink protocols without wiring any existing view to them yet.
- [ ] Verification criteria: `swift build` succeeds and new unit tests cover the execution state machine without calling real providers.

### Phase 3: Move Side Effects Behind Sinks
- [x] Implement diagnostics and history sinks that translate execution events into [Sources/CodeToolCore/Observability/AppLogger.swift](Sources/CodeToolCore/Observability/AppLogger.swift), [Sources/CodeToolCore/Observability/Diagnostics.swift](Sources/CodeToolCore/Observability/Diagnostics.swift), and [Sources/CodeToolCore/Persistence/HistoryStore.swift](Sources/CodeToolCore/Persistence/HistoryStore.swift).
- [x] Ensure finalize semantics are centralized in the execution layer.
- [ ] Verification criteria: boundary tests prove success, failure, and cancellation all produce stable sink behavior.

### Phase 4: Migrate One MiniMax Tool and Claude Chat
- [x] Migrate [Sources/CodeToolCore/Views/AITools/AIChatView.swift](Sources/CodeToolCore/Views/AITools/AIChatView.swift) first as the baseline MiniMax integration.
- [ ] Migrate [Sources/CodeToolCore/Views/AITools/ClaudeChatView.swift](Sources/CodeToolCore/Views/AITools/ClaudeChatView.swift) next to validate provider diversity.
- [ ] Verification criteria: both views compile against the new session API and retain existing user-visible behavior.

### Phase 5: Migrate Remaining AI Tools and Remove Duplicated Orchestration
- [ ] Migrate speech, image, and music to the session boundary.
- [ ] Delete duplicated `referenceID`, logging, and history orchestration from views.
- [ ] Verification criteria: `swift build` passes; targeted tests cover all migrated flows; duplicated orchestration code is removed rather than left as dead branches.

## Current Status

- `Sources/CodeToolCore/Execution/` now contains the execution request/state/event/result types, `AIExecutionSession`, and boundary tests for success, failure, cancellation, event forwarding, and provider aggregation.
- Production sinks/adapters now exist for the first MiniMax chat path: `AppLoggerDiagnosticsSink`, `MiniMaxChatExecutionProvider`, and `ChatHistoryExecutionSink`.
- `AIChatView` now runs through `AIExecutionSession`, but `ClaudeChatView`, `AISpeechView`, `AIImageView`, and `AIMusicView` still own their orchestration directly.

## Architectural Guidance

- The execution module should own lifecycle semantics, not UI state layout.
- Provider adapters should translate transport-specific behavior into execution events and nothing more.
- History and diagnostics are observers of a session, not responsibilities of a view.
- `referenceID` is execution identity. It should be created once per session and flow through all side effects.
- Views should migrate to thin request-building surfaces that bind to execution state.
- Keep request-shape tests close to provider adapters; keep lifecycle tests at the execution boundary.
