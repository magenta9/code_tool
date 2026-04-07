import Foundation

public struct HermesAgentDiagnosticsRecord: Codable, Identifiable, Sendable {
    public let id: UUID
    public let createdAt: Date
    public let sessionID: String?
    public let modelOrProfile: String?
    public let requestSummary: String
    public let outputSummary: String
    public let attachmentCount: Int
    public let durationMs: Int?
    public let status: String
    public let referenceID: String

    public init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        sessionID: String? = nil,
        modelOrProfile: String? = nil,
        requestSummary: String,
        outputSummary: String,
        attachmentCount: Int,
        durationMs: Int?,
        status: String,
        referenceID: String
    ) {
        self.id = id
        self.createdAt = createdAt
        self.sessionID = sessionID
        self.modelOrProfile = modelOrProfile
        self.requestSummary = requestSummary
        self.outputSummary = outputSummary
        self.attachmentCount = attachmentCount
        self.durationMs = durationMs
        self.status = status
        self.referenceID = referenceID
    }
}

extension HermesAgentDiagnosticsRecord: HistoryRecord {}