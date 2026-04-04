import Foundation

/// Identifies which AI tool an execution request targets.
public enum AIExecutionTool: String, Codable, Sendable {
    case chat
    case speech
    case image
    case music
    case claudeChat
}

/// A Sendable error snapshot capturing the essential details of a failure.
public struct AIExecutionFailure: Error, Codable, Sendable, Equatable, CustomStringConvertible {
    public let message: String
    public let code: Int?
    public let domain: String?

    public init(message: String, code: Int? = nil, domain: String? = nil) {
        self.message = message
        self.code = code
        self.domain = domain
    }

    public init(from error: Error) {
        let nsError = error as NSError
        self.message = error.localizedDescription
        self.code = nsError.code
        self.domain = nsError.domain
    }

    public var description: String { message }
    public var localizedDescription: String { message }
}

/// Terminal state of an execution session.
public enum AIExecutionState: Sendable, Equatable {
    case idle
    case running
    case completed
    case failed(AIExecutionFailure)
    case cancelled

    public var isTerminal: Bool {
        switch self {
        case .idle, .running:
            return false
        case .completed, .failed, .cancelled:
            return true
        }
    }
}

/// Progress events emitted during execution. These are non-terminal;
/// terminal outcome is determined by the provider returning or throwing.
public enum AIExecutionEvent: Sendable {
    case started
    case delta(String)
    case artifact(Data, label: String)
    case progress(message: String)
}

/// Normalized result produced after execution completes.
public struct AIExecutionResult: Sendable {
    public let referenceID: String
    public let tool: AIExecutionTool
    public let startedAt: Date
    public let completedAt: Date
    public let metadata: [String: String]

    public init(
        referenceID: String,
        tool: AIExecutionTool,
        startedAt: Date,
        completedAt: Date,
        metadata: [String: String] = [:]
    ) {
        self.referenceID = referenceID
        self.tool = tool
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.metadata = metadata
    }
}
