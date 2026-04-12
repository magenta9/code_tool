import CodeToolFoundation
import Foundation

/// Diagnostics sink that forwards execution events to AppLogger.
public struct AppLoggerDiagnosticsSink: AIExecutionDiagnosticsSink {
    // AppLogger delegates all work to an internal actor pipeline, so shared access is safe.
    private nonisolated(unsafe) let logger: AppLogger

    public init(logger: AppLogger = .shared) {
        self.logger = logger
    }

    public func record(event: AIExecutionEvent, referenceID: String, tool: AIExecutionTool) async {
        let category = logCategory(for: tool)

        switch event {
        case .started:
            await logger.info(
                category: category,
                event: "execution_started",
                referenceID: referenceID,
                message: "AI execution started.",
                metadata: ["tool": tool.rawValue]
            )

        case .delta:
            break // Deltas are too frequent to log individually

        case .artifact(let data, let label):
            await logger.info(
                category: category,
                event: "execution_artifact",
                referenceID: referenceID,
                message: "Received artifact: \(label)",
                metadata: [
                    "tool": tool.rawValue,
                    "label": label,
                    "byteCount": String(data.count),
                ]
            )

        case .progress(let message):
            await logger.info(
                category: category,
                event: "execution_progress",
                referenceID: referenceID,
                message: message,
                metadata: ["tool": tool.rawValue]
            )
        }
    }

    public func recordCompletion(result: AIExecutionResult) async {
        let category = logCategory(for: result.tool)
        let durationMs = Int(result.completedAt.timeIntervalSince(result.startedAt) * 1000)

        await logger.log(
            level: .info,
            category: category,
            event: "execution_completed",
            referenceID: result.referenceID,
            message: "AI execution completed.",
            metadata: result.metadata.merging(["tool": result.tool.rawValue]) { _, new in new },
            durationMs: durationMs
        )
    }

    public func recordFailure(
        failure: AIExecutionFailure,
        referenceID: String,
        tool: AIExecutionTool
    ) async {
        let category = logCategory(for: tool)

        await logger.log(
            level: .error,
            category: category,
            event: "execution_failed",
            referenceID: referenceID,
            message: failure.message,
            metadata: [
                "tool": tool.rawValue,
                "errorDomain": failure.domain ?? "unknown",
                "errorCode": failure.code.map(String.init) ?? "none",
            ]
        )
    }

    public func recordCancellation(referenceID: String, tool: AIExecutionTool) async {
        let category = logCategory(for: tool)

        await logger.info(
            category: category,
            event: "execution_cancelled",
            referenceID: referenceID,
            message: "AI execution was cancelled.",
            metadata: ["tool": tool.rawValue]
        )
    }

    private func logCategory(for tool: AIExecutionTool) -> AppLogCategory {
        switch tool {
        case .chat: return .aichat
        case .speech: return .aispeech
        case .image: return .aiimage
        case .music: return .aimusic
        }
    }
}
