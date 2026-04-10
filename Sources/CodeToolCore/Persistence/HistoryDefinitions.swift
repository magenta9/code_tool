import Foundation

// MARK: - History Payload Codec Protocol

/// Encodes a concrete record type into a `HistoryEntry` envelope and decodes it back.
///
/// Each codec knows how to:
/// - Produce a `HistoryEntrySummary` (title, subtitle, icon) for drawer display
/// - Extract diagnostics info for observability queries (nil for dev tools)
/// - Extract the reference ID used by diagnostics trace correlation
/// - List asset file names that must be cleaned up on delete
/// - Determine where assets live (same directory as JSON, or a separate directory)
public protocol HistoryPayloadCodec: Sendable {
    associatedtype Payload: Codable & Identifiable & Sendable where Payload.ID == UUID

    /// The tool identity this codec handles.
    var toolID: HistoryToolID { get }

    /// Produce a display summary from a decoded payload.
    func summary(for payload: Payload) -> HistoryEntrySummary

    /// Produce diagnostics info from a decoded payload, if applicable.
    func diagnosticsInfo(for payload: Payload) -> HistoryDiagnosticsInfo?

    /// Extract a reference ID from the payload, if present.
    func referenceID(for payload: Payload) -> String?

    /// Extract a session ID for diagnostics trace correlation (typically from Claude chat).
    func sessionID(for payload: Payload) -> String?

    /// List asset file names that belong to this record.
    func assetFileNames(for payload: Payload) -> [String]

    /// Timestamp for the payload.
    func createdAt(for payload: Payload) -> Date
}

extension HistoryPayloadCodec {
    /// Default: no session ID.
    public func sessionID(for payload: Payload) -> String? { nil }

    /// Build a `HistoryEntry` from a concrete payload and its raw JSON data.
    public func entry(for payload: Payload, data: Data) -> HistoryEntry {
        HistoryEntry(
            id: payload.id,
            toolID: toolID,
            createdAt: createdAt(for: payload),
            summary: summary(for: payload),
            referenceID: referenceID(for: payload),
            sessionID: sessionID(for: payload),
            assetFileNames: assetFileNames(for: payload),
            diagnosticsInfo: diagnosticsInfo(for: payload),
            payloadData: data
        )
    }
}

// MARK: - Concrete Codecs

public struct ChatHistoryCodec: HistoryPayloadCodec, Sendable {
    public typealias Payload = ChatHistoryRecord
    public let toolID = HistoryToolID.chat

    public init() {}

    public func summary(for r: ChatHistoryRecord) -> HistoryEntrySummary {
        let title = r.messages.last(where: { $0.role == "user" })?.content ?? "Chat session"
        return HistoryEntrySummary(
            title: String(title.prefix(60)),
            subtitle: "\(r.messages.count) messages · ~\(r.totalTokens) tokens",
            icon: "bubble.left.and.bubble.right"
        )
    }

    public func diagnosticsInfo(for r: ChatHistoryRecord) -> HistoryDiagnosticsInfo? {
        HistoryDiagnosticsInfo(
            title: "AI Chat",
            detail: "model=\(r.model), messages=\(r.messages.count)"
        )
    }

    public func referenceID(for r: ChatHistoryRecord) -> String? { r.referenceID }
    public func assetFileNames(for r: ChatHistoryRecord) -> [String] { [] }
    public func createdAt(for r: ChatHistoryRecord) -> Date { r.createdAt }
}

public struct ClaudeChatHistoryCodec: HistoryPayloadCodec, Sendable {
    public typealias Payload = ClaudeChatHistoryRecord
    public let toolID = HistoryToolID.claudeChat

    public func summary(for r: ClaudeChatHistoryRecord) -> HistoryEntrySummary {
        let title = r.messages.last(where: { $0.role == "user" })?.content ?? "Chat session"
        let costStr = r.totalCostUSD.map { String(format: "$%.4f", $0) } ?? ""
        let tokStr = [r.inputTokens.map { "↑\($0)" }, r.outputTokens.map { "↓\($0)" }]
            .compactMap { $0 }.joined(separator: " ")
        let attachmentCount = r.messages.reduce(0) { $0 + ($1.attachments?.count ?? 0) }
        let attachStr = attachmentCount > 0 ? "\(attachmentCount) 📎" : ""
        let subtitle = ["\(r.messages.count) msgs", attachStr, costStr, tokStr]
            .filter { !$0.isEmpty }.joined(separator: " · ")

        return HistoryEntrySummary(
            title: String(title.prefix(60)),
            subtitle: subtitle,
            icon: "bubble.left.and.bubble.right"
        )
    }

    public func diagnosticsInfo(for r: ClaudeChatHistoryRecord) -> HistoryDiagnosticsInfo? {
        HistoryDiagnosticsInfo(
            title: "Claude Chat",
            detail: "model=\(r.model), messages=\(r.messages.count)",
            sessionID: r.sessionId
        )
    }

    public func referenceID(for r: ClaudeChatHistoryRecord) -> String? { r.referenceID }

    public func sessionID(for r: ClaudeChatHistoryRecord) -> String? { r.sessionId }

    public func assetFileNames(for r: ClaudeChatHistoryRecord) -> [String] {
        r.messages.flatMap { $0.attachments ?? [] }.map(\.fileName)
    }

    public func createdAt(for r: ClaudeChatHistoryRecord) -> Date { r.createdAt }
}

public struct SpeechHistoryCodec: HistoryPayloadCodec, Sendable {
    public typealias Payload = SpeechHistoryRecord
    public let toolID = HistoryToolID.speech

    public func summary(for r: SpeechHistoryRecord) -> HistoryEntrySummary {
        HistoryEntrySummary(
            title: String(r.inputText.prefix(60)),
            subtitle: "\(r.voice) · \(r.outputFormat) · \(r.durationMs / 1000)s",
            icon: "waveform"
        )
    }

    public func diagnosticsInfo(for r: SpeechHistoryRecord) -> HistoryDiagnosticsInfo? {
        HistoryDiagnosticsInfo(
            title: "AI Speech",
            detail: "voice=\(r.voice), durationMs=\(r.durationMs), format=\(r.outputFormat)"
        )
    }

    public func referenceID(for r: SpeechHistoryRecord) -> String? { r.referenceID }
    public func assetFileNames(for r: SpeechHistoryRecord) -> [String] { [r.audioFileName] }
    public func createdAt(for r: SpeechHistoryRecord) -> Date { r.createdAt }
}

public struct ImageHistoryCodec: HistoryPayloadCodec, Sendable {
    public typealias Payload = ImageHistoryRecord
    public let toolID = HistoryToolID.image

    public func summary(for r: ImageHistoryRecord) -> HistoryEntrySummary {
        HistoryEntrySummary(
            title: String(r.prompt.prefix(60)),
            subtitle: "\(r.referenceImages.count) ref\(r.referenceImages.count == 1 ? "" : "s") · \(r.sizeSummary) · \(r.imageCount) output\(r.imageCount == 1 ? "" : "s")",
            icon: "photo.artframe"
        )
    }

    public func diagnosticsInfo(for r: ImageHistoryRecord) -> HistoryDiagnosticsInfo? {
        HistoryDiagnosticsInfo(
            title: "AI Image",
            detail: "model=\(r.model), refs=\(r.referenceImages.count), outputs=\(r.imageCount), size=\(r.sizeSummary)"
        )
    }

    public func referenceID(for r: ImageHistoryRecord) -> String? { r.referenceID }
    public func assetFileNames(for r: ImageHistoryRecord) -> [String] { r.persistedFileNames }
    public func createdAt(for r: ImageHistoryRecord) -> Date { r.createdAt }
}

public struct MusicHistoryCodec: HistoryPayloadCodec, Sendable {
    public typealias Payload = MusicHistoryRecord
    public let toolID = HistoryToolID.music

    public func summary(for r: MusicHistoryRecord) -> HistoryEntrySummary {
        HistoryEntrySummary(
            title: String(r.prompt.prefix(60)),
            subtitle: "\(r.isInstrumental ? "Instrumental" : "Vocal") · \(r.outputFormat)",
            icon: "music.note"
        )
    }

    public func diagnosticsInfo(for r: MusicHistoryRecord) -> HistoryDiagnosticsInfo? {
        HistoryDiagnosticsInfo(
            title: "AI Music",
            detail: "model=\(r.model), format=\(r.outputFormat), sampleRate=\(r.sampleRate)"
        )
    }

    public func referenceID(for r: MusicHistoryRecord) -> String? { r.referenceID }
    public func assetFileNames(for r: MusicHistoryRecord) -> [String] {
        r.audioFileName.map { [$0] } ?? []
    }
    public func createdAt(for r: MusicHistoryRecord) -> Date { r.createdAt }
}

public struct JSONToolHistoryCodec: HistoryPayloadCodec, Sendable {
    public typealias Payload = JSONToolHistoryRecord
    public let toolID = HistoryToolID.jsonTool

    public func summary(for r: JSONToolHistoryRecord) -> HistoryEntrySummary {
        HistoryEntrySummary(
            title: String(r.inputText.prefix(60)),
            subtitle: "\(r.operation) · \(r.stats)",
            icon: "curlybraces"
        )
    }

    public func diagnosticsInfo(for r: JSONToolHistoryRecord) -> HistoryDiagnosticsInfo? { nil }
    public func referenceID(for r: JSONToolHistoryRecord) -> String? { nil }
    public func assetFileNames(for r: JSONToolHistoryRecord) -> [String] { [] }
    public func createdAt(for r: JSONToolHistoryRecord) -> Date { r.createdAt }
}

public struct ImageConverterHistoryCodec: HistoryPayloadCodec, Sendable {
    public typealias Payload = ImageConverterHistoryRecord
    public let toolID = HistoryToolID.imageConverter

    public func summary(for r: ImageConverterHistoryRecord) -> HistoryEntrySummary {
        HistoryEntrySummary(
            title: r.imageInfo.isEmpty ? "Base64 conversion" : String(r.imageInfo.prefix(60)),
            subtitle: r.mode == "imageToBase64" ? "Image → Base64" : "Base64 → Image",
            icon: "photo"
        )
    }

    public func diagnosticsInfo(for r: ImageConverterHistoryRecord) -> HistoryDiagnosticsInfo? { nil }
    public func referenceID(for r: ImageConverterHistoryRecord) -> String? { nil }
    public func assetFileNames(for r: ImageConverterHistoryRecord) -> [String] {
        r.imageFileName.map { [$0] } ?? []
    }
    public func createdAt(for r: ImageConverterHistoryRecord) -> Date { r.createdAt }
}

public struct JSONDiffHistoryCodec: HistoryPayloadCodec, Sendable {
    public typealias Payload = JSONDiffHistoryRecord
    public let toolID = HistoryToolID.jsonDiff

    public func summary(for r: JSONDiffHistoryRecord) -> HistoryEntrySummary {
        HistoryEntrySummary(
            title: "Diff: \(r.totalDiffs) difference\(r.totalDiffs == 1 ? "" : "s")",
            subtitle: "+\(r.addedCount) −\(r.removedCount) ≠\(r.modifiedCount)",
            icon: "arrow.left.arrow.right"
        )
    }

    public func diagnosticsInfo(for r: JSONDiffHistoryRecord) -> HistoryDiagnosticsInfo? { nil }
    public func referenceID(for r: JSONDiffHistoryRecord) -> String? { nil }
    public func assetFileNames(for r: JSONDiffHistoryRecord) -> [String] { [] }
    public func createdAt(for r: JSONDiffHistoryRecord) -> Date { r.createdAt }
}

public struct TimestampHistoryCodec: HistoryPayloadCodec, Sendable {
    public typealias Payload = TimestampHistoryRecord
    public let toolID = HistoryToolID.timestampConverter

    public func summary(for r: TimestampHistoryRecord) -> HistoryEntrySummary {
        HistoryEntrySummary(
            title: String(r.inputValue.prefix(60)),
            subtitle: "\(r.direction == "timestampToDate" ? "Timestamp → Date" : "Date → Timestamp") → \(r.resultISO8601)",
            icon: "clock"
        )
    }

    public func diagnosticsInfo(for r: TimestampHistoryRecord) -> HistoryDiagnosticsInfo? { nil }
    public func referenceID(for r: TimestampHistoryRecord) -> String? { nil }
    public func assetFileNames(for r: TimestampHistoryRecord) -> [String] { [] }
    public func createdAt(for r: TimestampHistoryRecord) -> Date { r.createdAt }
}

public struct JWTHistoryCodec: HistoryPayloadCodec, Sendable {
    public typealias Payload = JWTHistoryRecord
    public let toolID = HistoryToolID.jwtTool

    public func summary(for r: JWTHistoryRecord) -> HistoryEntrySummary {
        HistoryEntrySummary(
            title: String(r.payloadJSON.prefix(60)),
            subtitle: "\(r.mode) · \(r.expirationInfo)",
            icon: "key"
        )
    }

    public func diagnosticsInfo(for r: JWTHistoryRecord) -> HistoryDiagnosticsInfo? { nil }
    public func referenceID(for r: JWTHistoryRecord) -> String? { nil }
    public func assetFileNames(for r: JWTHistoryRecord) -> [String] { [] }
    public func createdAt(for r: JWTHistoryRecord) -> Date { r.createdAt }
}

public struct WordCloudHistoryCodec: HistoryPayloadCodec, Sendable {
    public typealias Payload = WordCloudHistoryRecord
    public let toolID = HistoryToolID.wordCloud

    public func summary(for r: WordCloudHistoryRecord) -> HistoryEntrySummary {
        let firstWord = r.topWords.split(separator: ",").first.map(String.init) ?? ""
        return HistoryEntrySummary(
            title: String(r.inputPreview.prefix(60)),
            subtitle: "\(firstWord) · \(r.maxWords) words max",
            icon: "cloud"
        )
    }

    public func diagnosticsInfo(for r: WordCloudHistoryRecord) -> HistoryDiagnosticsInfo? { nil }
    public func referenceID(for r: WordCloudHistoryRecord) -> String? { nil }
    public func assetFileNames(for r: WordCloudHistoryRecord) -> [String] { [] }
    public func createdAt(for r: WordCloudHistoryRecord) -> Date { r.createdAt }
}

// MARK: - Tool History Definition

/// Bundles a codec with a type-erased load function for a specific tool.
/// Enables the repository to load entries generically without knowing the payload type.
public struct ToolHistoryDefinition: Sendable {
    public let toolID: HistoryToolID

    /// Decode raw JSON data into a `HistoryEntry` using the tool's codec.
    public let loadEntry: @Sendable (Data) throws -> HistoryEntry

    /// Produce a `DiagnosticsHistoryMatch` from a `HistoryEntry`, if applicable.
    public let diagnosticsMatch: @Sendable (HistoryEntry, String) -> DiagnosticsHistoryMatch?

    public init<C: HistoryPayloadCodec>(codec: C) {
        self.toolID = codec.toolID
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        self.loadEntry = { data in
            let payload = try decoder.decode(C.Payload.self, from: data)
            return codec.entry(for: payload, data: data)
        }

        self.diagnosticsMatch = { entry, refID in
            guard entry.referenceID == refID, let info = entry.diagnosticsInfo else { return nil }
            return DiagnosticsHistoryMatch(
                category: entry.toolID.rawValue,
                createdAt: entry.createdAt,
                referenceID: refID,
                title: info.title,
                detail: info.detail,
                sessionID: info.sessionID
            )
        }
    }
}

// MARK: - History Definition Registry

/// Central registry mapping tool IDs to their history definitions.
public struct HistoryDefinitionRegistry: Sendable {
    public static let shared = HistoryDefinitionRegistry()

    private let definitions: [HistoryToolID: ToolHistoryDefinition]

    public init() {
        let all: [ToolHistoryDefinition] = [
            ToolHistoryDefinition(codec: ChatHistoryCodec()),
            ToolHistoryDefinition(codec: ClaudeChatHistoryCodec()),
            ToolHistoryDefinition(codec: SpeechHistoryCodec()),
            ToolHistoryDefinition(codec: ImageHistoryCodec()),
            ToolHistoryDefinition(codec: MusicHistoryCodec()),
            ToolHistoryDefinition(codec: JSONToolHistoryCodec()),
            ToolHistoryDefinition(codec: ImageConverterHistoryCodec()),
            ToolHistoryDefinition(codec: JSONDiffHistoryCodec()),
            ToolHistoryDefinition(codec: TimestampHistoryCodec()),
            ToolHistoryDefinition(codec: JWTHistoryCodec()),
            ToolHistoryDefinition(codec: WordCloudHistoryCodec()),
        ]
        var map: [HistoryToolID: ToolHistoryDefinition] = [:]
        for def in all {
            map[def.toolID] = def
        }
        self.definitions = map
    }

    public func definition(for toolID: HistoryToolID) -> ToolHistoryDefinition? {
        definitions[toolID]
    }

    /// All registered tool IDs.
    public var allToolIDs: [HistoryToolID] {
        Array(definitions.keys)
    }
}
