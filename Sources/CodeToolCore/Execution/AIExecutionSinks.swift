import Foundation

/// Port for persisting execution outcomes (history store adapter).
public protocol AIExecutionHistorySink: Sendable {
    func record(result: AIExecutionResult, request: AIExecutionRequest) async
}

/// Port for recording execution lifecycle events (diagnostics/logging adapter).
public protocol AIExecutionDiagnosticsSink: Sendable {
    func record(event: AIExecutionEvent, referenceID: String, tool: AIExecutionTool) async
    func recordCompletion(result: AIExecutionResult) async
    func recordFailure(failure: AIExecutionFailure, referenceID: String, tool: AIExecutionTool) async
    func recordCancellation(referenceID: String, tool: AIExecutionTool) async
}
