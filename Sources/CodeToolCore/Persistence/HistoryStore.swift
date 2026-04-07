import Foundation

// MARK: - History Record Models

/// A single message in a chat conversation.
public struct ChatMessageRecord: Codable {
    public let role: String
    public let content: String
}

/// History record for an AI Chat session.
public struct ChatHistoryRecord: Codable, Identifiable {
    public let id: UUID
    public let createdAt: Date
    public let systemPrompt: String
    public let messages: [ChatMessageRecord]
    public let model: String
    public let promptTokens: Int
    public let completionTokens: Int
    public let totalTokens: Int
    public let referenceID: String
}

/// History record for an AI Speech generation.
public struct SpeechHistoryRecord: Codable, Identifiable {
    public let id: UUID
    public let createdAt: Date
    public let inputText: String
    public let voice: String
    public let speed: Double
    public let volume: Double
    public let pitch: Double
    public let outputFormat: String
    public let model: String
    public let durationMs: Int
    public let audioFileName: String
    public let referenceID: String
}

/// History record for an AI Image generation.
public struct ImageReferenceRecord: Codable, Identifiable {
    public let id: UUID
    public let fileName: String
    public let mimeType: String
    public let sizeBytes: Int

    public init(
        id: UUID = UUID(),
        fileName: String,
        mimeType: String,
        sizeBytes: Int
    ) {
        self.id = id
        self.fileName = fileName
        self.mimeType = mimeType
        self.sizeBytes = sizeBytes
    }
}

public struct ImageHistoryRecord: Codable, Identifiable {
    public let id: UUID
    public let createdAt: Date
    public let prompt: String
    public let aspectRatio: String?
    public let width: Int?
    public let height: Int?
    public let imageCount: Int
    public let seed: Int?
    public let promptOptimizer: Bool
    public let model: String
    public let referenceImages: [ImageReferenceRecord]
    public let outputImageFileNames: [String]
    public let referenceID: String

    public init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        prompt: String,
        aspectRatio: String? = nil,
        width: Int? = nil,
        height: Int? = nil,
        imageCount: Int,
        seed: Int? = nil,
        promptOptimizer: Bool = false,
        model: String,
        referenceImages: [ImageReferenceRecord] = [],
        outputImageFileNames: [String],
        referenceID: String
    ) {
        self.id = id
        self.createdAt = createdAt
        self.prompt = prompt
        self.aspectRatio = aspectRatio
        self.width = width
        self.height = height
        self.imageCount = imageCount
        self.seed = seed
        self.promptOptimizer = promptOptimizer
        self.model = model
        self.referenceImages = referenceImages
        self.outputImageFileNames = outputImageFileNames
        self.referenceID = referenceID
    }

    public var imageFileNames: [String] {
        outputImageFileNames
    }

    public var persistedFileNames: [String] {
        referenceImages.map(\.fileName) + outputImageFileNames
    }

    public var sizeSummary: String {
        if let aspectRatio, !aspectRatio.isEmpty {
            return aspectRatio
        }

        if let width, let height {
            return "\(width)x\(height)"
        }

        return "Auto"
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case createdAt
        case prompt
        case aspectRatio
        case width
        case height
        case imageCount
        case seed
        case promptOptimizer
        case model
        case referenceImages
        case outputImageFileNames
        case legacyImageFileNames = "imageFileNames"
        case referenceID
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        prompt = try container.decode(String.self, forKey: .prompt)
        aspectRatio = try container.decodeIfPresent(String.self, forKey: .aspectRatio)
        width = try container.decodeIfPresent(Int.self, forKey: .width)
        height = try container.decodeIfPresent(Int.self, forKey: .height)
        imageCount = try container.decode(Int.self, forKey: .imageCount)
        seed = try container.decodeIfPresent(Int.self, forKey: .seed)
        promptOptimizer = try container.decodeIfPresent(Bool.self, forKey: .promptOptimizer) ?? false
        model = try container.decode(String.self, forKey: .model)
        referenceImages = try container.decodeIfPresent([ImageReferenceRecord].self, forKey: .referenceImages) ?? []
        outputImageFileNames =
            try container.decodeIfPresent([String].self, forKey: .outputImageFileNames)
            ?? container.decodeIfPresent([String].self, forKey: .legacyImageFileNames)
            ?? []
        referenceID = try container.decode(String.self, forKey: .referenceID)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(prompt, forKey: .prompt)
        try container.encode(imageCount, forKey: .imageCount)
        try container.encode(promptOptimizer, forKey: .promptOptimizer)
        try container.encode(model, forKey: .model)
        try container.encode(outputImageFileNames, forKey: .outputImageFileNames)
        try container.encode(referenceID, forKey: .referenceID)

        if let aspectRatio {
            try container.encode(aspectRatio, forKey: .aspectRatio)
        }

        if let width {
            try container.encode(width, forKey: .width)
        }

        if let height {
            try container.encode(height, forKey: .height)
        }

        if let seed {
            try container.encode(seed, forKey: .seed)
        }

        if !referenceImages.isEmpty {
            try container.encode(referenceImages, forKey: .referenceImages)
        }
    }
}

/// History record for an AI Music generation.
public struct MusicHistoryRecord: Codable, Identifiable {
    public let id: UUID
    public let createdAt: Date
    public let prompt: String
    public let lyrics: String
    public let isInstrumental: Bool
    public let outputFormat: String
    public let sampleRate: Int
    public let bitrate: Int
    public let model: String
    public let audioFileName: String?
    public let referenceID: String
}

// MARK: - HistoryRecord Protocol

public protocol HistoryRecord: Codable, Identifiable where ID == UUID {
    var id: UUID { get }
    var createdAt: Date { get }
}

extension ChatHistoryRecord: HistoryRecord {}
extension SpeechHistoryRecord: HistoryRecord {}
extension ImageHistoryRecord: HistoryRecord {}
extension MusicHistoryRecord: HistoryRecord {}

// MARK: - Claude Chat History Models

/// Metadata for a single attachment in a Claude chat message.
public struct ClaudeChatAttachmentRecord: Codable, Identifiable {
    public let id: UUID
    public let type: String   // "image"
    public let fileName: String
    public let mimeType: String
    public let sizeBytes: Int

    public init(
        id: UUID = UUID(),
        type: String = "image",
        fileName: String,
        mimeType: String,
        sizeBytes: Int
    ) {
        self.id = id
        self.type = type
        self.fileName = fileName
        self.mimeType = mimeType
        self.sizeBytes = sizeBytes
    }
}

/// A single message in a Claude chat conversation.
public struct ClaudeChatMessageRecord: Codable {
    public let role: String
    public let content: String
    public let thinkingContent: String?
    public let toolName: String?
    public let toolInput: String?
    public let attachments: [ClaudeChatAttachmentRecord]?

    public init(
        role: String,
        content: String,
        thinkingContent: String? = nil,
        toolName: String? = nil,
        toolInput: String? = nil,
        attachments: [ClaudeChatAttachmentRecord]? = nil
    ) {
        self.role = role
        self.content = content
        self.thinkingContent = thinkingContent
        self.toolName = toolName
        self.toolInput = toolInput
        self.attachments = attachments
    }
}

/// History record for a Claude CLI chat session.
public struct ClaudeChatHistoryRecord: Codable, Identifiable {
    public let id: UUID
    public let createdAt: Date
    public let systemPrompt: String?
    public let workingDirectory: String?
    public let messages: [ClaudeChatMessageRecord]
    public let model: String
    public let totalCostUSD: Double?
    public let inputTokens: Int?
    public let outputTokens: Int?
    public let durationMs: Int?
    public let sessionId: String?
    public let referenceID: String

    public init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        systemPrompt: String? = nil,
        workingDirectory: String? = nil,
        messages: [ClaudeChatMessageRecord],
        model: String,
        totalCostUSD: Double? = nil,
        inputTokens: Int? = nil,
        outputTokens: Int? = nil,
        durationMs: Int? = nil,
        sessionId: String? = nil,
        referenceID: String
    ) {
        self.id = id
        self.createdAt = createdAt
        self.systemPrompt = systemPrompt
        self.workingDirectory = workingDirectory
        self.messages = messages
        self.model = model
        self.totalCostUSD = totalCostUSD
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.durationMs = durationMs
        self.sessionId = sessionId
        self.referenceID = referenceID
    }
}

extension ClaudeChatHistoryRecord: HistoryRecord {}

// MARK: - HistoryCategory

public enum HistoryCategory: String, CaseIterable {
    case chat
    case claudeChat = "claude-chat"
    case hermesAgent = "hermes-agent"
    case speech
    case image
    case music
    // Dev tools
    case jsonTool
    case imageConverter
    case jsonDiff
    case timestampConverter
    case jwtTool
    case wordCloud
}

// MARK: - Dev Tool History Records

/// History record for JSON Tool operations.
public struct JSONToolHistoryRecord: Codable, Identifiable {
    public let id: UUID
    public let createdAt: Date
    public let operation: String
    public let inputText: String
    public let outputText: String
    public let stats: String
}

/// History record for Image Converter operations.
public struct ImageConverterHistoryRecord: Codable, Identifiable {
    public let id: UUID
    public let createdAt: Date
    public let mode: String
    public let base64Text: String
    public let base64Preview: String
    public let imageInfo: String
    public let imageFileName: String?
}

/// History record for JSON Diff operations.
public struct JSONDiffHistoryRecord: Codable, Identifiable {
    public let id: UUID
    public let createdAt: Date
    public let leftText: String
    public let rightText: String
    public let totalDiffs: Int
    public let addedCount: Int
    public let removedCount: Int
    public let modifiedCount: Int
}

/// History record for Timestamp Converter operations.
public struct TimestampHistoryRecord: Codable, Identifiable {
    public let id: UUID
    public let createdAt: Date
    public let inputValue: String
    public let direction: String
    public let selectedDateISO8601: String?
    public let resultISO8601: String
    public let resultLocal: String
    public let resultTimestamp: String
}

/// History record for JWT Tool operations.
public struct JWTHistoryRecord: Codable, Identifiable {
    public let id: UUID
    public let createdAt: Date
    public let mode: String
    public let jwtInput: String
    public let headerJSON: String
    public let payloadJSON: String
    public let expirationInfo: String
}

/// History record for Word Cloud operations.
public struct WordCloudHistoryRecord: Codable, Identifiable {
    public let id: UUID
    public let createdAt: Date
    public let inputText: String
    public let inputPreview: String
    public let topWords: String
    public let minWordLength: Int
    public let maxWords: Int
    public let ignoreStopWords: Bool
}

extension JSONToolHistoryRecord: HistoryRecord {}
extension ImageConverterHistoryRecord: HistoryRecord {}
extension JSONDiffHistoryRecord: HistoryRecord {}
extension TimestampHistoryRecord: HistoryRecord {}
extension JWTHistoryRecord: HistoryRecord {}
extension WordCloudHistoryRecord: HistoryRecord {}

// MARK: - HistoryStore

/// Persistent history storage backed by JSON files and binary data in Application Support.
///
/// Directory layout:
/// ```
/// Application Support/CodeTool/history/
///   chat/    – ChatHistoryRecord JSON files
///   speech/  – SpeechHistoryRecord JSON files + audio blobs
///   image/   – ImageHistoryRecord JSON files + reference/output image blobs
///   music/   – MusicHistoryRecord JSON files + audio blobs
/// ```
public actor HistoryStore: DiagnosticsHistoryLookupPort, HistoryRepository {
    public static let shared = HistoryStore()

    private let fileManager = FileManager.default
    private let registry = HistoryDefinitionRegistry.shared
    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    private var overrideBaseURL: URL?

    // MARK: - Directory Resolution

    private func baseURL() throws -> URL {
        if let override = overrideBaseURL {
            return override
        }
        guard
            let appSupport = fileManager.urls(
                for: .applicationSupportDirectory, in: .userDomainMask
            ).first
        else {
            throw HistoryStoreError.storageUnavailable
        }
        return
            appSupport
            .appendingPathComponent("CodeTool", isDirectory: true)
            .appendingPathComponent("history", isDirectory: true)
    }

    private func categoryURL(_ category: HistoryCategory) throws -> URL {
        let dir = try baseURL().appendingPathComponent(category.rawValue, isDirectory: true)
        if !fileManager.fileExists(atPath: dir.path) {
            try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    private func toolURL(_ toolID: HistoryToolID) throws -> URL {
        try categoryURL(toolID.category)
    }

    /// Override the base directory (for tests).
    public func setBaseURLForTesting(_ url: URL?) {
        overrideBaseURL = url
    }

    // MARK: - Static Attachment Helpers (non-actor, for synchronous use)

    private static func staticBaseURL() throws -> URL {
        guard
            let appSupport = FileManager.default.urls(
                for: .applicationSupportDirectory, in: .userDomainMask
            ).first
        else {
            throw HistoryStoreError.storageUnavailable
        }
        return
            appSupport
            .appendingPathComponent("CodeTool", isDirectory: true)
            .appendingPathComponent("history", isDirectory: true)
    }

    private static func staticClaudeChatAttachmentsURL() throws -> URL {
        let dir = try staticBaseURL().appendingPathComponent("claude-chat-attachments", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    /// Save an attachment file synchronously (non-actor). For use from main thread.
    public static func syncSaveClaudeChatAttachment(data: Data, fileName: String) throws -> String {
        let dir = try staticClaudeChatAttachmentsURL()
        try data.write(to: dir.appendingPathComponent(fileName))
        return fileName
    }

    /// Get the URL for a Claude chat attachment file synchronously (non-actor).
    public static func syncClaudeChatAttachmentURL(fileName: String) throws -> URL {
        let dir = try staticClaudeChatAttachmentsURL()
        return dir.appendingPathComponent(fileName)
    }

    // MARK: - Claude Chat Attachment Storage

    /// Directory for Claude chat attachment files.
    private func claudeChatAttachmentsURL() throws -> URL {
        let dir = try baseURL().appendingPathComponent("claude-chat-attachments", isDirectory: true)
        if !fileManager.fileExists(atPath: dir.path) {
            try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    /// Save an attachment file for Claude chat. Returns the persisted file name.
    public func saveClaudeChatAttachment(data: Data, fileName: String) throws -> String {
        let dir = try claudeChatAttachmentsURL()
        try data.write(to: dir.appendingPathComponent(fileName))
        return fileName
    }

    /// Load an attachment file for Claude chat.
    public func loadClaudeChatAttachment(fileName: String) throws -> Data {
        let dir = try claudeChatAttachmentsURL()
        return try Data(contentsOf: dir.appendingPathComponent(fileName))
    }

    /// URL for a Claude chat attachment file.
    public func claudeChatAttachmentURL(fileName: String) throws -> URL {
        let dir = try claudeChatAttachmentsURL()
        return dir.appendingPathComponent(fileName)
    }

    // MARK: - Save

    public func save(_ record: ChatHistoryRecord) throws {
        let dir = try categoryURL(.chat)
        let data = try encoder.encode(record)
        try data.write(to: dir.appendingPathComponent("\(record.id.uuidString).json"))
    }

    public func save(_ record: SpeechHistoryRecord, audioData: Data) throws {
        let dir = try categoryURL(.speech)
        let data = try encoder.encode(record)
        try data.write(to: dir.appendingPathComponent("\(record.id.uuidString).json"))
        try audioData.write(to: dir.appendingPathComponent(record.audioFileName))
    }

    public func save(_ record: ImageHistoryRecord, images: [Data]) throws {
        try save(record, outputImages: images)
    }

    public func save(
        _ record: ImageHistoryRecord,
        outputImages: [Data],
        referenceImageData: [Data] = []
    ) throws {
        guard referenceImageData.count == record.referenceImages.count else {
            throw HistoryStoreError.invalidImageDataCount(
                expected: record.referenceImages.count,
                actual: referenceImageData.count
            )
        }

        guard outputImages.count == record.outputImageFileNames.count else {
            throw HistoryStoreError.invalidImageDataCount(
                expected: record.outputImageFileNames.count,
                actual: outputImages.count
            )
        }

        let dir = try categoryURL(.image)

        for (index, imageData) in referenceImageData.enumerated() {
            let tempURL = dir.appendingPathComponent("\(record.id.uuidString)-ref-\(index).tmp")
            try imageData.write(to: tempURL)
        }

        for (index, imageData) in outputImages.enumerated() {
            let tempURL = dir.appendingPathComponent("\(record.id.uuidString)-out-\(index).tmp")
            try imageData.write(to: tempURL)
        }

        let data = try encoder.encode(record)
        try data.write(to: dir.appendingPathComponent("\(record.id.uuidString).json"))

        for (index, _) in referenceImageData.enumerated() {
            let tempURL = dir.appendingPathComponent("\(record.id.uuidString)-ref-\(index).tmp")
            let finalURL = dir.appendingPathComponent(record.referenceImages[index].fileName)
            try fileManager.moveItem(at: tempURL, to: finalURL)
        }

        for (index, _) in outputImages.enumerated() {
            let tempURL = dir.appendingPathComponent("\(record.id.uuidString)-out-\(index).tmp")
            let finalURL = dir.appendingPathComponent(record.outputImageFileNames[index])
            try fileManager.moveItem(at: tempURL, to: finalURL)
        }
    }

    public func save(_ record: MusicHistoryRecord, audioData: Data?) throws {
        let dir = try categoryURL(.music)
        let data = try encoder.encode(record)
        try data.write(to: dir.appendingPathComponent("\(record.id.uuidString).json"))
        if let audioData, let audioFileName = record.audioFileName {
            try audioData.write(to: dir.appendingPathComponent(audioFileName))
        }
    }

    // MARK: - Dev Tool Save

    public func save(_ record: ClaudeChatHistoryRecord) throws {
        let dir = try categoryURL(.claudeChat)
        let data = try encoder.encode(record)
        try data.write(to: dir.appendingPathComponent("\(record.id.uuidString).json"))
    }

    public func save(_ record: HermesAgentDiagnosticsRecord) throws {
        let dir = try categoryURL(.hermesAgent)
        let data = try encoder.encode(record)
        try data.write(to: dir.appendingPathComponent("\(record.id.uuidString).json"))
    }

    public func save(_ record: JSONToolHistoryRecord) throws {
        let dir = try categoryURL(.jsonTool)
        let data = try encoder.encode(record)
        try data.write(to: dir.appendingPathComponent("\(record.id.uuidString).json"))
    }

    public func save(_ record: ImageConverterHistoryRecord, imageData: Data?) throws {
        let dir = try categoryURL(.imageConverter)
        let data = try encoder.encode(record)
        try data.write(to: dir.appendingPathComponent("\(record.id.uuidString).json"))
        if let imageData, let imageFileName = record.imageFileName {
            try imageData.write(to: dir.appendingPathComponent(imageFileName))
        }
    }

    public func save(_ record: JSONDiffHistoryRecord) throws {
        let dir = try categoryURL(.jsonDiff)
        let data = try encoder.encode(record)
        try data.write(to: dir.appendingPathComponent("\(record.id.uuidString).json"))
    }

    public func save(_ record: TimestampHistoryRecord) throws {
        let dir = try categoryURL(.timestampConverter)
        let data = try encoder.encode(record)
        try data.write(to: dir.appendingPathComponent("\(record.id.uuidString).json"))
    }

    public func save(_ record: JWTHistoryRecord) throws {
        let dir = try categoryURL(.jwtTool)
        let data = try encoder.encode(record)
        try data.write(to: dir.appendingPathComponent("\(record.id.uuidString).json"))
    }

    public func save(_ record: WordCloudHistoryRecord) throws {
        let dir = try categoryURL(.wordCloud)
        let data = try encoder.encode(record)
        try data.write(to: dir.appendingPathComponent("\(record.id.uuidString).json"))
    }

    // MARK: - Unified Repository API (HistoryRepository)

    public func upsert(_ entry: HistoryEntry, assets: [HistoryAsset]) throws {
        let dir = try toolURL(entry.toolID)
        // Write assets first (temp → final if needed)
        for asset in assets {
            try asset.data.write(to: dir.appendingPathComponent(asset.fileName))
        }
        // Write or overwrite the JSON record (upsert by ID)
        try entry.payloadData.write(to: dir.appendingPathComponent("\(entry.id.uuidString).json"))
    }

    public func list(_ query: HistoryQuery) throws -> [HistoryEntry] {
        let toolIDs: [HistoryToolID]
        if let toolID = query.toolID {
            toolIDs = [toolID]
        } else {
            toolIDs = HistoryToolID.allCases
        }

        var entries: [HistoryEntry] = []
        for toolID in toolIDs {
            guard let def = registry.definition(for: toolID) else { continue }
            let dir: URL
            do {
                dir = try toolURL(toolID)
            } catch {
                continue
            }

            let urls: [URL]
            do {
                urls = try fileManager.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
                    .filter { $0.pathExtension == "json" }
            } catch {
                continue
            }

            for url in urls {
                do {
                    let data = try Data(contentsOf: url)
                    let entry = try def.loadEntry(data)
                    if let refFilter = query.referenceID, entry.referenceID != refFilter {
                        continue
                    }
                    entries.append(entry)
                } catch {
                    continue
                }
            }
        }

        entries.sort { $0.createdAt > $1.createdAt }

        if let limit = query.limit {
            return Array(entries.prefix(limit))
        }
        return entries
    }

    public func upsert<C: HistoryPayloadCodec>(
        _ payload: C.Payload,
        using codec: C,
        assets: [HistoryAsset] = []
    ) throws {
        let data = try encoder.encode(payload)
        let entry = codec.entry(for: payload, data: data)
        try upsert(entry, assets: assets)
    }

    public func payloads<C: HistoryPayloadCodec>(
        using codec: C,
        referenceID: String? = nil,
        limit: Int? = nil
    ) throws -> [C.Payload] {
        let entries = try list(
            HistoryQuery(
                toolID: codec.toolID,
                referenceID: referenceID,
                limit: limit
            )
        )

        return entries.compactMap { entry in
            try? decoder.decode(C.Payload.self, from: entry.payloadData)
        }
    }

    public func delete(toolID: HistoryToolID, id: UUID) throws {
        let dir = try toolURL(toolID)
        let jsonURL = dir.appendingPathComponent("\(id.uuidString).json")

        // Load the entry to find associated asset files
        if let data = try? Data(contentsOf: jsonURL),
           let def = registry.definition(for: toolID),
           let entry = try? def.loadEntry(data) {
            // Delete known asset files
            for assetName in entry.assetFileNames {
                if toolID == .claudeChat {
                    // Claude attachments live in a separate directory
                    if let attachDir = try? claudeChatAttachmentsURL() {
                        try? fileManager.removeItem(at: attachDir.appendingPathComponent(assetName))
                    }
                } else {
                    try? fileManager.removeItem(at: dir.appendingPathComponent(assetName))
                }
            }
        } else {
            // Fallback: remove all files with this UUID prefix
            removeFiles(in: dir, prefix: id.uuidString)
        }

        try? fileManager.removeItem(at: jsonURL)
    }

    public func loadAsset(toolID: HistoryToolID, fileName: String) throws -> Data {
        let dir = try toolURL(toolID)
        return try Data(contentsOf: dir.appendingPathComponent(fileName))
    }

    public func clear(toolID: HistoryToolID) throws {
        try clear(category: toolID.category)
    }

    public func count(toolID: HistoryToolID) throws -> Int {
        try count(category: toolID.category)
    }

    // MARK: - Query

    /// List all records for a category, newest first.
    public func listChat(limit: Int? = nil, offset: Int = 0) throws -> [ChatHistoryRecord] {
        try loadRecords(category: .chat, limit: limit, offset: offset)
    }

    public func listSpeech(limit: Int? = nil, offset: Int = 0) throws -> [SpeechHistoryRecord] {
        try loadRecords(category: .speech, limit: limit, offset: offset)
    }

    public func listImage(limit: Int? = nil, offset: Int = 0) throws -> [ImageHistoryRecord] {
        try loadRecords(category: .image, limit: limit, offset: offset)
    }

    public func listMusic(limit: Int? = nil, offset: Int = 0) throws -> [MusicHistoryRecord] {
        try loadRecords(category: .music, limit: limit, offset: offset)
    }

    // MARK: - Dev Tool List

    public func listClaudeChat(limit: Int? = nil, offset: Int = 0) throws -> [ClaudeChatHistoryRecord] {
        try loadRecords(category: .claudeChat, limit: limit, offset: offset)
    }

    public func listHermesAgent(limit: Int? = nil, offset: Int = 0) throws -> [HermesAgentDiagnosticsRecord] {
        try loadRecords(category: .hermesAgent, limit: limit, offset: offset)
    }

    public func listJSONTool() throws -> [JSONToolHistoryRecord] {
        try loadRecords(category: .jsonTool)
    }

    public func listImageConverter() throws -> [ImageConverterHistoryRecord] {
        try loadRecords(category: .imageConverter)
    }

    public func listJSONDiff() throws -> [JSONDiffHistoryRecord] {
        try loadRecords(category: .jsonDiff)
    }

    public func listTimestamp() throws -> [TimestampHistoryRecord] {
        try loadRecords(category: .timestampConverter)
    }

    public func listJWT() throws -> [JWTHistoryRecord] {
        try loadRecords(category: .jwtTool)
    }

    public func listWordCloud() throws -> [WordCloudHistoryRecord] {
        try loadRecords(category: .wordCloud)
    }

    private func loadRecords<T: HistoryRecord>(
        category: HistoryCategory,
        limit: Int? = nil,
        offset: Int = 0
    ) throws -> [T] {
        let urls = try sortedRecordURLs(category: category)
        let pagedURLs = Array(urls.dropFirst(offset).prefix(limit ?? Int.max))

        var records: [T] = []
        for url in pagedURLs {
            do {
                let data = try Data(contentsOf: url)
                let record = try decoder.decode(T.self, from: data)
                records.append(record)
            } catch {
                // Skip corrupted records — don't let one bad file block the whole list
                continue
            }
        }

        return records.sorted { $0.createdAt > $1.createdAt }
    }

    private func sortedRecordURLs(category: HistoryCategory) throws -> [URL] {
        let dir = try categoryURL(category)
        let urls = try fileManager.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )
        .filter { $0.pathExtension == "json" }

        return urls.sorted { lhs, rhs in
            let lhsDate = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let rhsDate = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast

            if lhsDate == rhsDate {
                return lhs.lastPathComponent > rhs.lastPathComponent
            }

            return lhsDate > rhsDate
        }
    }

    /// Load binary data (audio / image) for a given category and filename.
    public func loadData(category: HistoryCategory, fileName: String) throws -> Data {
        let dir = try categoryURL(category)
        return try Data(contentsOf: dir.appendingPathComponent(fileName))
    }

    public func diagnosticsMatches(referenceID: String) throws -> [DiagnosticsHistoryMatch] {
        let entries = try list(HistoryQuery(referenceID: referenceID))
        var matches: [DiagnosticsHistoryMatch] = []
        for entry in entries {
            guard let info = entry.diagnosticsInfo else { continue }
            matches.append(
                DiagnosticsHistoryMatch(
                    category: entry.toolID.rawValue,
                    createdAt: entry.createdAt,
                    referenceID: referenceID,
                    title: info.title,
                    detail: info.detail,
                    sessionID: info.sessionID
                )
            )
        }
        return matches.sorted { $0.createdAt > $1.createdAt }
    }

    // MARK: - Delete

    /// Delete a single record and its associated binary files.
    public func deleteChat(id: UUID) throws {
        let dir = try categoryURL(.chat)
        let jsonURL = dir.appendingPathComponent("\(id.uuidString).json")
        try? fileManager.removeItem(at: jsonURL)
    }

    public func deleteSpeech(id: UUID) throws {
        let dir = try categoryURL(.speech)
        removeFiles(in: dir, prefix: id.uuidString)
    }

    public func deleteImage(id: UUID) throws {
        let dir = try categoryURL(.image)
        let jsonURL = dir.appendingPathComponent("\(id.uuidString).json")

        var errors: [Error] = []

        if let data = try? Data(contentsOf: jsonURL),
           let record = try? decoder.decode(ImageHistoryRecord.self, from: data) {
            for fileName in record.persistedFileNames {
                do {
                    try fileManager.removeItem(at: dir.appendingPathComponent(fileName))
                } catch {
                    errors.append(error)
                }
            }
        } else {
            removeFiles(in: dir, prefix: id.uuidString)
        }

        do {
            try fileManager.removeItem(at: jsonURL)
        } catch {
            errors.append(error)
        }

        if let firstError = errors.first {
            throw firstError
        }
    }

    public func deleteMusic(id: UUID) throws {
        let dir = try categoryURL(.music)
        removeFiles(in: dir, prefix: id.uuidString)
    }

    // MARK: - Dev Tool Delete

    public func deleteClaudeChat(id: UUID) throws {
        let dir = try categoryURL(.claudeChat)
        let jsonURL = dir.appendingPathComponent("\(id.uuidString).json")

        // Clean up referenced attachment files
        if let data = try? Data(contentsOf: jsonURL),
           let record = try? decoder.decode(ClaudeChatHistoryRecord.self, from: data) {
            let attachmentDir = try? claudeChatAttachmentsURL()
            for message in record.messages {
                for attachment in message.attachments ?? [] {
                    if let attachmentDir {
                        try? fileManager.removeItem(
                            at: attachmentDir.appendingPathComponent(attachment.fileName))
                    }
                }
            }
        }

        try? fileManager.removeItem(at: jsonURL)
    }

    public func deleteHermesAgent(id: UUID) throws {
        let dir = try categoryURL(.hermesAgent)
        try? fileManager.removeItem(at: dir.appendingPathComponent("\(id.uuidString).json"))
    }

    public func deleteJSONTool(id: UUID) throws {
        let dir = try categoryURL(.jsonTool)
        try? fileManager.removeItem(at: dir.appendingPathComponent("\(id.uuidString).json"))
    }

    public func deleteImageConverter(id: UUID) throws {
        let dir = try categoryURL(.imageConverter)
        let jsonURL = dir.appendingPathComponent("\(id.uuidString).json")
        if let data = try? Data(contentsOf: jsonURL),
           let record = try? decoder.decode(ImageConverterHistoryRecord.self, from: data),
           let imageFileName = record.imageFileName {
            try? fileManager.removeItem(at: dir.appendingPathComponent(imageFileName))
        }
        try? fileManager.removeItem(at: jsonURL)
    }

    public func deleteJSONDiff(id: UUID) throws {
        let dir = try categoryURL(.jsonDiff)
        try? fileManager.removeItem(at: dir.appendingPathComponent("\(id.uuidString).json"))
    }

    public func deleteTimestamp(id: UUID) throws {
        let dir = try categoryURL(.timestampConverter)
        try? fileManager.removeItem(at: dir.appendingPathComponent("\(id.uuidString).json"))
    }

    public func deleteJWT(id: UUID) throws {
        let dir = try categoryURL(.jwtTool)
        try? fileManager.removeItem(at: dir.appendingPathComponent("\(id.uuidString).json"))
    }

    public func deleteWordCloud(id: UUID) throws {
        let dir = try categoryURL(.wordCloud)
        try? fileManager.removeItem(at: dir.appendingPathComponent("\(id.uuidString).json"))
    }

    private func removeFiles(in directory: URL, prefix: String) {
        guard
            let urls = try? fileManager.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: nil)
        else { return }
        for url in urls where url.lastPathComponent.hasPrefix(prefix) {
            try? fileManager.removeItem(at: url)
        }
    }

    // MARK: - Clear

    /// Clear all history for a specific category.
    public func clear(category: HistoryCategory) throws {
        let dir = try categoryURL(category)
        guard
            let urls = try? fileManager.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: nil)
        else { return }
        for url in urls {
            try fileManager.removeItem(at: url)
        }

        // Also clear claude-chat attachment files when clearing claude-chat history
        if category == .claudeChat {
            if let attachmentDir = try? claudeChatAttachmentsURL(),
               let attachmentURLs = try? fileManager.contentsOfDirectory(
                   at: attachmentDir, includingPropertiesForKeys: nil) {
                for url in attachmentURLs {
                    try? fileManager.removeItem(at: url)
                }
            }
        }
    }

    /// Clear all history across all categories.
    public func clearAll() throws {
        for category in HistoryCategory.allCases {
            try clear(category: category)
        }
    }

    // MARK: - Count

    public func count(category: HistoryCategory) throws -> Int {
        let dir = try categoryURL(category)
        let urls = try fileManager.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
        return urls.filter { $0.pathExtension == "json" }.count
    }
}

// MARK: - Errors

public enum HistoryStoreError: LocalizedError {
    case storageUnavailable
    case invalidImageDataCount(expected: Int, actual: Int)

    public var errorDescription: String? {
        switch self {
        case .storageUnavailable:
            return "Unable to locate Application Support directory for history storage."
        case .invalidImageDataCount(let expected, let actual):
            return "Image data count mismatch: expected \(expected) but got \(actual)."
        }
    }
}
