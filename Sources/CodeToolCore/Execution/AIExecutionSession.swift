import Foundation

/// Orchestrates the lifecycle of a single AI operation.
///
/// Owns `referenceID`, manages state transitions, coordinates the provider
/// and side-effect sinks. Terminal states are entered exactly once.
public actor AIExecutionSession {
    public nonisolated let referenceID: String
    public let request: AIExecutionRequest

    public private(set) var state: AIExecutionState = .idle
    public private(set) var latestResult: AIExecutionResult?

    private let provider: AIExecutionProviding
    private let historySink: AIExecutionHistorySink?
    private let diagnosticsSink: AIExecutionDiagnosticsSink?
    private let eventSink: (@Sendable (AIExecutionEvent) async -> Void)?
    private var executionTask: Task<Void, Never>?

    public init(
        request: AIExecutionRequest,
        provider: AIExecutionProviding,
        historySink: AIExecutionHistorySink? = nil,
        diagnosticsSink: AIExecutionDiagnosticsSink? = nil,
        eventSink: (@Sendable (AIExecutionEvent) async -> Void)? = nil
    ) {
        self.request = request
        self.referenceID = request.referenceID
        self.provider = provider
        self.historySink = historySink
        self.diagnosticsSink = diagnosticsSink
        self.eventSink = eventSink
    }

    /// Start the execution. No-op if already started or in a terminal state.
    public func start() async {
        guard state == .idle else { return }
        state = .running

        executionTask = Task { [weak self] in
            guard let self else { return }
            await self.run()
        }

        await executionTask?.value
    }

    /// Request cancellation of the running execution.
    public func cancel() {
        guard state == .running else { return }
        executionTask?.cancel()
    }

    private func run() async {
        await eventSink?(.started)
        await diagnosticsSink?.record(
            event: .started,
            referenceID: referenceID,
            tool: request.tool
        )

        do {
            try Task.checkCancellation()

            let result = try await provider.execute(request: request) { [weak self] event in
                guard let self else { return }
                let currentState = await self.state
                guard !currentState.isTerminal else { return }
                await self.eventSink?(event)
                await self.diagnosticsSink?.record(
                    event: event,
                    referenceID: self.referenceID,
                    tool: self.request.tool
                )
            }

            let currentState = self.state
            guard !currentState.isTerminal else { return }
            state = .completed
            latestResult = result

            await diagnosticsSink?.recordCompletion(result: result)
            await historySink?.record(result: result, request: request)
        } catch is CancellationError {
            let currentState = self.state
            guard !currentState.isTerminal else { return }
            state = .cancelled
            await diagnosticsSink?.recordCancellation(
                referenceID: referenceID,
                tool: request.tool
            )
        } catch {
            let currentState = self.state
            guard !currentState.isTerminal else { return }
            let failure = AIExecutionFailure(from: error)
            state = .failed(failure)
            await diagnosticsSink?.recordFailure(
                failure: failure,
                referenceID: referenceID,
                tool: request.tool
            )
        }
    }
}
