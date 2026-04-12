import Foundation
import XCTest

@testable import CodeToolCore
@testable import CodeToolFoundation

// MARK: - Test Doubles

/// Thread-safe wrapper for shared mutable state in tests.
private final class ManagedCriticalState<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: Value
    init(_ value: Value) { _value = value }
    var value: Value {
        get { lock.withLock { _value } }
        set { lock.withLock { _value = newValue } }
    }
}

/// A mock provider that records calls and returns a configurable result.
private final class MockExecutionProvider: AIExecutionProviding, @unchecked Sendable {
    var executeHandler: (
        (AIExecutionRequest, @escaping @Sendable (AIExecutionEvent) async -> Void) async throws ->
            AIExecutionResult
    )?
    private(set) var executeCalls: [AIExecutionRequest] = []

    func execute(
        request: AIExecutionRequest,
        emit: @escaping @Sendable (AIExecutionEvent) async -> Void
    ) async throws -> AIExecutionResult {
        executeCalls.append(request)
        guard let handler = executeHandler else {
            return AIExecutionResult(
                referenceID: request.referenceID,
                tool: request.tool,
                startedAt: Date(),
                completedAt: Date()
            )
        }
        return try await handler(request, emit)
    }
}

/// A mock diagnostics sink that records all lifecycle events.
private actor MockDiagnosticsSink: AIExecutionDiagnosticsSink {
    private(set) var events: [(event: String, referenceID: String, tool: AIExecutionTool)] = []
    private(set) var completions: [AIExecutionResult] = []
    private(set) var failures: [(failure: AIExecutionFailure, referenceID: String)] = []
    private(set) var cancellations: [(referenceID: String, tool: AIExecutionTool)] = []

    func record(event: AIExecutionEvent, referenceID: String, tool: AIExecutionTool) async {
        let label: String
        switch event {
        case .started: label = "started"
        case .delta(let text): label = "delta:\(text)"
        case .artifact(_, let l): label = "artifact:\(l)"
        case .progress(let msg): label = "progress:\(msg)"
        }
        events.append((event: label, referenceID: referenceID, tool: tool))
    }

    func recordCompletion(result: AIExecutionResult) async {
        completions.append(result)
    }

    func recordFailure(failure: AIExecutionFailure, referenceID: String, tool: AIExecutionTool)
        async
    {
        failures.append((failure: failure, referenceID: referenceID))
    }

    func recordCancellation(referenceID: String, tool: AIExecutionTool) async {
        cancellations.append((referenceID: referenceID, tool: tool))
    }
}

/// A mock history sink that records results.
private actor MockHistorySink: AIExecutionHistorySink {
    private(set) var recorded: [(result: AIExecutionResult, request: AIExecutionRequest)] = []

    func record(result: AIExecutionResult, request: AIExecutionRequest) async {
        recorded.append((result: result, request: request))
    }
}

// MARK: - Tests

final class AIExecutionSessionTests: XCTestCase {

    // MARK: - Type Tests

    func testExecutionToolRawValues() {
        XCTAssertEqual(AIExecutionTool.chat.rawValue, "chat")
        XCTAssertEqual(AIExecutionTool.speech.rawValue, "speech")
        XCTAssertEqual(AIExecutionTool.image.rawValue, "image")
        XCTAssertEqual(AIExecutionTool.music.rawValue, "music")
    }

    func testExecutionStateIsTerminal() {
        XCTAssertFalse(AIExecutionState.idle.isTerminal)
        XCTAssertFalse(AIExecutionState.running.isTerminal)
        XCTAssertTrue(AIExecutionState.completed.isTerminal)
        XCTAssertTrue(AIExecutionState.cancelled.isTerminal)
        XCTAssertTrue(
            AIExecutionState.failed(AIExecutionFailure(message: "test")).isTerminal)
    }

    func testExecutionFailureFromError() {
        let nsError = NSError(domain: "TestDomain", code: 42, userInfo: [
            NSLocalizedDescriptionKey: "Something went wrong"
        ])
        let failure = AIExecutionFailure(from: nsError)
        XCTAssertEqual(failure.message, "Something went wrong")
        XCTAssertEqual(failure.code, 42)
        XCTAssertEqual(failure.domain, "TestDomain")
    }

    func testExecutionFailureEquatable() {
        let a = AIExecutionFailure(message: "error", code: 1, domain: "D")
        let b = AIExecutionFailure(message: "error", code: 1, domain: "D")
        let c = AIExecutionFailure(message: "other", code: 2, domain: "D")
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }

    func testRequestAutoGeneratesReferenceID() {
        let request = AIExecutionRequest(
            tool: .chat,
            payload: .chat(ChatExecutionPayload(messages: []))
        )
        XCTAssertFalse(request.referenceID.isEmpty)
    }

    func testRequestUsesProvidedReferenceID() {
        let request = AIExecutionRequest(
            tool: .chat,
            payload: .chat(ChatExecutionPayload(messages: [])),
            referenceID: "custom-ref-123"
        )
        XCTAssertEqual(request.referenceID, "custom-ref-123")
    }

    // MARK: - Session Lifecycle Tests

    func testSuccessfulExecution() async {
        let provider = MockExecutionProvider()
        let diagnostics = MockDiagnosticsSink()
        let history = MockHistorySink()

        let request = AIExecutionRequest(
            tool: .chat,
            payload: .chat(ChatExecutionPayload(messages: [("user", "hello")])),
            referenceID: "ref-success-001"
        )

        provider.executeHandler = { req, emit in
            await emit(.started)
            await emit(.delta("Hello"))
            await emit(.delta(" world"))
            return AIExecutionResult(
                referenceID: req.referenceID,
                tool: req.tool,
                startedAt: Date(),
                completedAt: Date(),
                metadata: ["responseLength": "11"]
            )
        }

        let session = AIExecutionSession(
            request: request,
            provider: provider,
            historySink: history,
            diagnosticsSink: diagnostics
        )

        let initialState = await session.state
        XCTAssertEqual(initialState, .idle)

        await session.start()

        let finalState = await session.state
        XCTAssertEqual(finalState, .completed)
        XCTAssertEqual(session.referenceID, "ref-success-001")

        // Verify diagnostics recorded events
        let events = await diagnostics.events
        // Session emits .started from run(), then provider emits .started + 2 deltas
        XCTAssertEqual(events.count, 4)
        XCTAssertEqual(events[0].event, "started")  // session-level
        XCTAssertEqual(events[1].event, "started")  // provider-level
        XCTAssertEqual(events[2].event, "delta:Hello")
        XCTAssertEqual(events[3].event, "delta: world")

        // Verify completion was recorded
        let completions = await diagnostics.completions
        XCTAssertEqual(completions.count, 1)
        XCTAssertEqual(completions[0].referenceID, "ref-success-001")

        // Verify history was saved
        let recorded = await history.recorded
        XCTAssertEqual(recorded.count, 1)
        XCTAssertEqual(recorded[0].result.referenceID, "ref-success-001")
    }

    func testFailedExecution() async {
        let provider = MockExecutionProvider()
        let diagnostics = MockDiagnosticsSink()

        let request = AIExecutionRequest(
            tool: .image,
            payload: .image(ImageExecutionPayload(prompt: "a cat")),
            referenceID: "ref-fail-001"
        )

        provider.executeHandler = { req, emit in
            await emit(.started)
            throw NSError(domain: "MiniMaxError", code: 500, userInfo: [
                NSLocalizedDescriptionKey: "Server error"
            ])
        }

        let session = AIExecutionSession(
            request: request,
            provider: provider,
            diagnosticsSink: diagnostics
        )

        await session.start()

        let finalState = await session.state
        if case .failed(let failure) = finalState {
            XCTAssertEqual(failure.message, "Server error")
            XCTAssertEqual(failure.code, 500)
            XCTAssertEqual(failure.domain, "MiniMaxError")
        } else {
            XCTFail("Expected .failed state, got \(finalState)")
        }

        // Verify failure was recorded
        let failures = await diagnostics.failures
        XCTAssertEqual(failures.count, 1)
        XCTAssertEqual(failures[0].failure.message, "Server error")
        XCTAssertEqual(failures[0].referenceID, "ref-fail-001")

        // No completions
        let completions = await diagnostics.completions
        XCTAssertTrue(completions.isEmpty)
    }

    func testCancelledExecution() async {
        let provider = MockExecutionProvider()
        let diagnostics = MockDiagnosticsSink()

        let request = AIExecutionRequest(
            tool: .speech,
            payload: .speech(SpeechExecutionPayload(text: "hello", voiceId: "v1")),
            referenceID: "ref-cancel-001"
        )

        // Use a continuation to synchronize: the provider will wait until cancelled.
        let providerStarted = ManagedCriticalState(false)
        provider.executeHandler = { req, emit in
            await emit(.started)
            providerStarted.value = true
            // Block until the task is cancelled
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000) // 1ms
            }
            try Task.checkCancellation()
            // Should never reach here
            return AIExecutionResult(
                referenceID: req.referenceID,
                tool: req.tool,
                startedAt: Date(),
                completedAt: Date()
            )
        }

        let session = AIExecutionSession(
            request: request,
            provider: provider,
            diagnosticsSink: diagnostics
        )

        // Start in a detached task so we can cancel
        let task = Task {
            await session.start()
        }

        // Wait for provider to actually start
        while !providerStarted.value {
            try? await Task.sleep(nanoseconds: 1_000_000)
        }

        await session.cancel()
        await task.value

        let finalState = await session.state
        XCTAssertEqual(finalState, .cancelled)

        let cancellations = await diagnostics.cancellations
        XCTAssertEqual(cancellations.count, 1)
        XCTAssertEqual(cancellations[0].referenceID, "ref-cancel-001")
    }

    func testReferenceIDConsistency() async {
        let provider = MockExecutionProvider()
        let diagnostics = MockDiagnosticsSink()
        let history = MockHistorySink()

        let request = AIExecutionRequest(
            tool: .music,
            payload: .music(MusicExecutionPayload(prompt: "jazz")),
            referenceID: "ref-consistency-001"
        )

        provider.executeHandler = { req, emit in
            await emit(.started)
            return AIExecutionResult(
                referenceID: req.referenceID,
                tool: req.tool,
                startedAt: Date(),
                completedAt: Date()
            )
        }

        let session = AIExecutionSession(
            request: request,
            provider: provider,
            historySink: history,
            diagnosticsSink: diagnostics
        )

        await session.start()

        // All references should match
        let sessionRef = session.referenceID
        XCTAssertEqual(sessionRef, "ref-consistency-001")

        let events = await diagnostics.events
        XCTAssertTrue(events.allSatisfy { $0.referenceID == "ref-consistency-001" })

        let completions = await diagnostics.completions
        XCTAssertEqual(completions[0].referenceID, "ref-consistency-001")

        let recorded = await history.recorded
        XCTAssertEqual(recorded[0].result.referenceID, "ref-consistency-001")
    }

    func testStartIsIdempotent() async {
        let provider = MockExecutionProvider()

        let request = AIExecutionRequest(
            tool: .chat,
            payload: .chat(ChatExecutionPayload(messages: []))
        )

        let session = AIExecutionSession(
            request: request,
            provider: provider
        )

        await session.start()
        await session.start() // Second start should be a no-op

        XCTAssertEqual(provider.executeCalls.count, 1)
    }

    func testNoEventsAfterTerminalState() async {
        let provider = MockExecutionProvider()
        let diagnostics = MockDiagnosticsSink()

        let request = AIExecutionRequest(
            tool: .chat,
            payload: .chat(ChatExecutionPayload(messages: []))
        )

        provider.executeHandler = { req, emit in
            await emit(.started)
            return AIExecutionResult(
                referenceID: req.referenceID,
                tool: req.tool,
                startedAt: Date(),
                completedAt: Date()
            )
        }

        let session = AIExecutionSession(
            request: request,
            provider: provider,
            diagnosticsSink: diagnostics
        )

        await session.start()

        let finalState = await session.state
        XCTAssertEqual(finalState, .completed)

        // One completion only
        let completions = await diagnostics.completions
        XCTAssertEqual(completions.count, 1)

        // No failures or cancellations
        let failures = await diagnostics.failures
        XCTAssertTrue(failures.isEmpty)
        let cancellations = await diagnostics.cancellations
        XCTAssertTrue(cancellations.isEmpty)
    }

    func testSinkFailureDoesNotCorruptState() async {
        // Provider succeeds — if sinks were to fail internally,
        // the session state should still be .completed
        let provider = MockExecutionProvider()

        let request = AIExecutionRequest(
            tool: .chat,
            payload: .chat(ChatExecutionPayload(messages: []))
        )

        provider.executeHandler = { req, emit in
            await emit(.started)
            return AIExecutionResult(
                referenceID: req.referenceID,
                tool: req.tool,
                startedAt: Date(),
                completedAt: Date()
            )
        }

        // No sinks at all — should still complete cleanly
        let session = AIExecutionSession(
            request: request,
            provider: provider
        )

        await session.start()
        let state = await session.state
        XCTAssertEqual(state, .completed)
    }

    func testSessionStoresLatestResultAndForwardsEventsToObserver() async {
        let provider = MockExecutionProvider()
        let observed = ManagedCriticalState<[String]>([])

        let request = AIExecutionRequest(
            tool: .chat,
            payload: .chat(ChatExecutionPayload(messages: [("user", "hello there")]))
        )

        provider.executeHandler = { req, emit in
            await emit(.delta("Hello"))
            await emit(.delta(" there"))
            return AIExecutionResult(
                referenceID: req.referenceID,
                tool: req.tool,
                startedAt: Date(),
                completedAt: Date(),
                metadata: ["assistantContent": "Hello there"]
            )
        }

        let session = AIExecutionSession(
            request: request,
            provider: provider,
            eventSink: { event in
                let label: String
                switch event {
                case .started: label = "started"
                case .delta(let text): label = "delta:\(text)"
                case .artifact(_, let labelValue): label = "artifact:\(labelValue)"
                case .progress(let message): label = "progress:\(message)"
                }
                observed.value = observed.value + [label]
            }
        )

        await session.start()

        XCTAssertEqual(observed.value, ["started", "delta:Hello", "delta: there"])
        let latestResult = await session.latestResult
        XCTAssertEqual(latestResult?.metadata["assistantContent"], "Hello there")
    }

    // MARK: - Payload Tests

    func testChatPayloadProperties() {
        let payload = ChatExecutionPayload(
            messages: [("user", "hi"), ("assistant", "hello")],
            systemPrompt: "Be helpful",
            temperature: 0.9,
            maxTokens: 4096
        )
        XCTAssertEqual(payload.messages.count, 2)
        XCTAssertEqual(payload.systemPrompt, "Be helpful")
        XCTAssertEqual(payload.temperature, 0.9)
        XCTAssertEqual(payload.maxTokens, 4096)
    }

    func testSpeechPayloadDefaults() {
        let payload = SpeechExecutionPayload(text: "hello", voiceId: "test")
        XCTAssertEqual(payload.speed, 1.0)
        XCTAssertEqual(payload.volume, 1.0)
        XCTAssertEqual(payload.pitch, 0)
        XCTAssertEqual(payload.format, "mp3")
    }

    func testImagePayloadDefaults() {
        let payload = ImageExecutionPayload(prompt: "a sunset")
        XCTAssertNil(payload.aspectRatio)
        XCTAssertNil(payload.width)
        XCTAssertNil(payload.height)
        XCTAssertEqual(payload.imageCount, 1)
        XCTAssertNil(payload.seed)
        XCTAssertFalse(payload.promptOptimizer)
        XCTAssertTrue(payload.referenceImageData.isEmpty)
    }

    func testMusicPayloadDefaults() {
        let payload = MusicExecutionPayload(prompt: "jazz")
        XCTAssertNil(payload.lyrics)
        XCTAssertFalse(payload.isInstrumental)
        XCTAssertEqual(payload.format, "mp3")
        XCTAssertEqual(payload.sampleRate, 44100)
        XCTAssertEqual(payload.bitrate, 256000)
    }

    // MARK: - AppLoggerDiagnosticsSink Tests

    func testAppLoggerSinkDoesNotCrash() async {
        // Verify the concrete sink can be instantiated and called without crashing.
        // We don't verify log output (that would require a test logger), but we verify
        // the code path doesn't throw or crash.
        let sink = AppLoggerDiagnosticsSink()

        await sink.record(event: .started, referenceID: "test-ref", tool: .chat)
        await sink.record(event: .delta("hello"), referenceID: "test-ref", tool: .chat)
        await sink.record(
            event: .artifact(Data([0x01]), label: "test"),
            referenceID: "test-ref", tool: .chat)
        await sink.record(
            event: .progress(message: "50%"), referenceID: "test-ref", tool: .chat)

        let result = AIExecutionResult(
            referenceID: "test-ref",
            tool: .chat,
            startedAt: Date(),
            completedAt: Date()
        )
        await sink.recordCompletion(result: result)

        let failure = AIExecutionFailure(message: "test error", code: 1, domain: "test")
        await sink.recordFailure(failure: failure, referenceID: "test-ref", tool: .image)
        await sink.recordCancellation(referenceID: "test-ref", tool: .speech)
    }

    func testMiniMaxChatExecutionProviderAggregatesDeltasIntoResultMetadata() async throws {
        let provider = MiniMaxChatExecutionProvider(
            streamChat: { messages, temperature, maxTokens, referenceID, onDelta in
                XCTAssertEqual(messages.map(\.role), ["system", "user"])
                XCTAssertEqual(temperature, 0.4)
                XCTAssertEqual(maxTokens, 512)
                XCTAssertEqual(referenceID, "chat-provider-ref")
                await onDelta("Hello")
                await onDelta(" world")
            },
            modelProvider: { "chat-model" }
        )

        let request = AIExecutionRequest(
            tool: .chat,
            payload: .chat(
                ChatExecutionPayload(
                    messages: [("user", "How are you today?")],
                    systemPrompt: "Be friendly",
                    temperature: 0.4,
                    maxTokens: 512
                )
            ),
            referenceID: "chat-provider-ref"
        )

        let observed = ManagedCriticalState<[String]>([])
        let result = try await provider.execute(request: request) { event in
            if case .delta(let text) = event {
                observed.value = observed.value + [text]
            }
        }

        XCTAssertEqual(observed.value, ["Hello", " world"])
        XCTAssertEqual(result.referenceID, "chat-provider-ref")
        XCTAssertEqual(result.metadata["assistantContent"], "Hello world")
        XCTAssertEqual(result.metadata["model"], "chat-model")
    }

    func testChatHistoryExecutionSinkBuildsHistoryRecordFromExecution() async {
        let captured = ManagedCriticalState<ChatHistoryRecord?>(nil)
        let sink = ChatHistoryExecutionSink(
            modelProvider: { "sink-model" },
            recordSaver: { record in
                captured.value = record
            }
        )

        let request = AIExecutionRequest(
            tool: .chat,
            payload: .chat(
                ChatExecutionPayload(
                    messages: [("user", "Hello from request")],
                    systemPrompt: "Stay brief"
                )
            ),
            referenceID: "chat-sink-ref"
        )

        let result = AIExecutionResult(
            referenceID: "chat-sink-ref",
            tool: .chat,
            startedAt: Date(timeIntervalSince1970: 10),
            completedAt: Date(timeIntervalSince1970: 20),
            metadata: [
                "assistantContent": "Hello from sink",
                "promptTokens": "11",
                "completionTokens": "4",
                "totalTokens": "15",
            ]
        )

        await sink.record(result: result, request: request)

        XCTAssertEqual(captured.value?.referenceID, "chat-sink-ref")
        XCTAssertEqual(captured.value?.systemPrompt, "Stay brief")
        XCTAssertEqual(captured.value?.model, "sink-model")
        XCTAssertEqual(captured.value?.messages.map(\.role), ["user", "assistant"])
        XCTAssertEqual(captured.value?.messages.last?.content, "Hello from sink")
        XCTAssertEqual(captured.value?.totalTokens, 15)
    }

    // MARK: - AIExecutionResult Tests

    func testExecutionResultMetadata() {
        let result = AIExecutionResult(
            referenceID: "ref-001",
            tool: .chat,
            startedAt: Date(),
            completedAt: Date(),
            metadata: ["key": "value"]
        )
        XCTAssertEqual(result.metadata["key"], "value")
        XCTAssertEqual(result.referenceID, "ref-001")
        XCTAssertEqual(result.tool, .chat)
    }
}
