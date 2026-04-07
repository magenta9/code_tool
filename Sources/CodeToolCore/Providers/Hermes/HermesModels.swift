import Foundation

public enum HermesOutputMode: String, Codable, Sendable {
    case finalTextOnly
    case humanStreaming
    case structured
}

public struct HermesCapabilityMatrix: Sendable, Codable, Equatable {
    public let binaryPath: String
    public let versionString: String?
    public let supportsChatQuery: Bool
    public let supportsQuietOutput: Bool
    public let supportsResumeFlag: Bool
    public let supportsContinueFlag: Bool
    public let supportsSessionsList: Bool
    public let supportsModelFlag: Bool
    public let supportsProfileFlag: Bool
    public let supportsContextReferences: Bool
    public let outputMode: HermesOutputMode

    public init(
        binaryPath: String,
        versionString: String?,
        supportsChatQuery: Bool,
        supportsQuietOutput: Bool,
        supportsResumeFlag: Bool,
        supportsContinueFlag: Bool,
        supportsSessionsList: Bool,
        supportsModelFlag: Bool,
        supportsProfileFlag: Bool,
        supportsContextReferences: Bool,
        outputMode: HermesOutputMode
    ) {
        self.binaryPath = binaryPath
        self.versionString = versionString
        self.supportsChatQuery = supportsChatQuery
        self.supportsQuietOutput = supportsQuietOutput
        self.supportsResumeFlag = supportsResumeFlag
        self.supportsContinueFlag = supportsContinueFlag
        self.supportsSessionsList = supportsSessionsList
        self.supportsModelFlag = supportsModelFlag
        self.supportsProfileFlag = supportsProfileFlag
        self.supportsContextReferences = supportsContextReferences
        self.outputMode = outputMode
    }
}

public struct HermesCLIHelpSnapshot: Sendable, Equatable {
    public let versionOutput: String?
    public let rootHelpOutput: String
    public let chatHelpOutput: String
    public let sessionsHelpOutput: String
    public let sessionsListHelpOutput: String?

    public init(
        versionOutput: String?,
        rootHelpOutput: String,
        chatHelpOutput: String,
        sessionsHelpOutput: String,
        sessionsListHelpOutput: String?
    ) {
        self.versionOutput = versionOutput
        self.rootHelpOutput = rootHelpOutput
        self.chatHelpOutput = chatHelpOutput
        self.sessionsHelpOutput = sessionsHelpOutput
        self.sessionsListHelpOutput = sessionsListHelpOutput
    }
}

public struct HermesAttachmentReference: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let fileURL: URL
    public let displayName: String
    public let kindDescription: String
    public let sizeBytes: Int64?

    public init(
        id: UUID = UUID(),
        fileURL: URL,
        displayName: String,
        kindDescription: String,
        sizeBytes: Int64?
    ) {
        self.id = id
        self.fileURL = fileURL
        self.displayName = displayName
        self.kindDescription = kindDescription
        self.sizeBytes = sizeBytes
    }
}

public enum HermesPhase: String, Codable, Sendable {
    case capabilityProbe
    case preparingAttachments
    case launchingProcess
    case waitingForResponse
    case resolvingSessionMetadata
    case completed
    case cancelled
    case failed

    public var label: String {
        switch self {
        case .capabilityProbe:
            return "Capability Probe"
        case .preparingAttachments:
            return "Preparing Attachments"
        case .launchingProcess:
            return "Launching Process"
        case .waitingForResponse:
            return "Waiting for Response"
        case .resolvingSessionMetadata:
            return "Resolving Session Metadata"
        case .completed:
            return "Completed"
        case .cancelled:
            return "Cancelled"
        case .failed:
            return "Failed"
        }
    }
}

public enum HermesTimelineStatus: String, Codable, Sendable {
    case running
    case completed
    case cancelled
    case failed
    case warning
}

public struct HermesTimelineEntry: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let timestamp: Date
    public let phase: HermesPhase
    public let status: HermesTimelineStatus
    public let detail: String

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        phase: HermesPhase,
        status: HermesTimelineStatus,
        detail: String
    ) {
        self.id = id
        self.timestamp = timestamp
        self.phase = phase
        self.status = status
        self.detail = detail
    }
}

public enum HermesChatMessageRole: String, Codable, Sendable {
    case user
    case assistant
}

public struct HermesChatMessage: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let role: HermesChatMessageRole
    public let content: String
    public let attachments: [HermesAttachmentReference]

    public init(
        id: UUID = UUID(),
        role: HermesChatMessageRole,
        content: String,
        attachments: [HermesAttachmentReference] = []
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.attachments = attachments
    }

    public static func user(
        _ content: String,
        attachments: [HermesAttachmentReference] = []
    ) -> HermesChatMessage {
        HermesChatMessage(role: .user, content: content, attachments: attachments)
    }

    public static func assistant(_ content: String) -> HermesChatMessage {
        HermesChatMessage(role: .assistant, content: content)
    }
}

public struct HermesAgentViewState: Equatable, Sendable {
    public var messages: [HermesChatMessage]
    public var timelineEntries: [HermesTimelineEntry]
    public var attachments: [HermesAttachmentReference]
    public var draftText: String
    public var isRunning: Bool
    public var activeReferenceID: String
    public var activeSessionID: String?
    public var errorBanner: String

    public init(
        messages: [HermesChatMessage] = [],
        timelineEntries: [HermesTimelineEntry] = [],
        attachments: [HermesAttachmentReference] = [],
        draftText: String = "",
        isRunning: Bool = false,
        activeReferenceID: String = "",
        activeSessionID: String? = nil,
        errorBanner: String = ""
    ) {
        self.messages = messages
        self.timelineEntries = timelineEntries
        self.attachments = attachments
        self.draftText = draftText
        self.isRunning = isRunning
        self.activeReferenceID = activeReferenceID
        self.activeSessionID = activeSessionID
        self.errorBanner = errorBanner
    }

    public mutating func resetForNewChat() {
        messages = []
        timelineEntries = []
        attachments = []
        draftText = ""
        isRunning = false
        activeReferenceID = ""
        activeSessionID = nil
        errorBanner = ""
    }

    public static func sendDisabled(
        draftText: String,
        attachments: [HermesAttachmentReference],
        isRunning: Bool,
        isAvailable: Bool
    ) -> Bool {
        let hasText = !draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return (!hasText && attachments.isEmpty) || isRunning || !isAvailable
    }
}

public struct HermesSessionSummary: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String?
    public let preview: String
    public let updatedAtText: String
    public let source: String?

    public init(
        id: String,
        title: String?,
        preview: String,
        updatedAtText: String,
        source: String? = nil
    ) {
        self.id = id
        self.title = title
        self.preview = preview
        self.updatedAtText = updatedAtText
        self.source = source
    }
}

public enum HermesTurnStatus: String, Codable, Sendable {
    case completed
    case cancelled
}

public struct HermesTurnRequest: Sendable, Equatable {
    public let prompt: String
    public let resumeSessionID: String?
    public let referenceID: String
    public let modelOrProfile: String?
    public let extraArguments: [String]

    public init(
        prompt: String,
        resumeSessionID: String?,
        referenceID: String,
        modelOrProfile: String?,
        extraArguments: [String]
    ) {
        self.prompt = prompt
        self.resumeSessionID = resumeSessionID
        self.referenceID = referenceID
        self.modelOrProfile = modelOrProfile
        self.extraArguments = extraArguments
    }
}

public struct HermesTurnResult: Sendable, Equatable {
    public let output: String
    public let sessionID: String?
    public let exitCode: Int32
    public let durationMs: Int?
    public let status: HermesTurnStatus

    public init(
        output: String,
        sessionID: String?,
        exitCode: Int32,
        durationMs: Int?,
        status: HermesTurnStatus
    ) {
        self.output = output
        self.sessionID = sessionID
        self.exitCode = exitCode
        self.durationMs = durationMs
        self.status = status
    }
}

public enum HermesAgentEvent: Sendable {
    case phaseChanged(HermesPhase)
    case outputDelta(String)
    case completed(HermesTurnResult)
    case warning(String)
    case failed(String)
}

public struct HermesCommand: Equatable, Sendable {
    public let executablePath: String
    public let arguments: [String]

    public init(executablePath: String, arguments: [String]) {
        self.executablePath = executablePath
        self.arguments = arguments
    }
}