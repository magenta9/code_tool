import Foundation

/// Port implemented by provider adapters (MiniMax, Claude, etc.).
///
/// Contract:
/// - Call `emit` with progress events during work (`.started`, `.delta`, `.artifact`, `.progress`).
/// - Return `AIExecutionResult` on success. Throw on failure.
/// - Events are progress-only. The terminal outcome is the return/throw.
/// - Implementations must support cooperative cancellation via `Task.checkCancellation()`.
public protocol AIExecutionProviding: Sendable {
    func execute(
        request: AIExecutionRequest,
        emit: @escaping @Sendable (AIExecutionEvent) async -> Void
    ) async throws -> AIExecutionResult
}
