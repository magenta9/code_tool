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
public struct ImageHistoryRecord: Codable, Identifiable {
    public let id: UUID
    public let createdAt: Date
    public let prompt: String
    public let aspectRatio: String
    public let imageCount: Int
    public let model: String
    public let imageFileNames: [String]
    public let referenceID: String
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
///   image/   – ImageHistoryRecord JSON files + image blobs
///   music/   – MusicHistoryRecord JSON files + audio blobs
/// ```
public actor HistoryStore {
    public static let shared = HistoryStore()

    private let fileManager = FileManager.default
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
        let dir = try categoryURL(.image)
        let data = try encoder.encode(record)
        try data.write(to: dir.appendingPathComponent("\(record.id.uuidString).json"))
        for (index, imageData) in images.enumerated() {
            guard index < record.imageFileNames.count else { break }
            try imageData.write(to: dir.appendingPathComponent(record.imageFileNames[index]))
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

    // MARK: - Query

    /// List all records for a category, newest first.
    public func listChat() throws -> [ChatHistoryRecord] {
        try loadRecords(category: .chat)
    }

    public func listSpeech() throws -> [SpeechHistoryRecord] {
        try loadRecords(category: .speech)
    }

    public func listImage() throws -> [ImageHistoryRecord] {
        try loadRecords(category: .image)
    }

    public func listMusic() throws -> [MusicHistoryRecord] {
        try loadRecords(category: .music)
    }

    // MARK: - Dev Tool List

    public func listClaudeChat() throws -> [ClaudeChatHistoryRecord] {
        try loadRecords(category: .claudeChat)
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

    private func loadRecords<T: HistoryRecord>(category: HistoryCategory) throws -> [T] {
        let dir = try categoryURL(category)
        let urls = try fileManager.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }

        var records: [T] = []
        for url in urls {
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

    /// Load binary data (audio / image) for a given category and filename.
    public func loadData(category: HistoryCategory, fileName: String) throws -> Data {
        let dir = try categoryURL(category)
        return try Data(contentsOf: dir.appendingPathComponent(fileName))
    }

    public func diagnosticsMatches(referenceID: String) throws -> [DiagnosticsHistoryMatch] {
        var matches: [DiagnosticsHistoryMatch] = []

        for record in try listChat() where record.referenceID == referenceID {
            matches.append(
                DiagnosticsHistoryMatch(
                    category: HistoryCategory.chat.rawValue,
                    createdAt: record.createdAt,
                    referenceID: record.referenceID,
                    title: "AI Chat",
                    detail: "model=\(record.model), messages=\(record.messages.count)"
                )
            )
        }

        for record in try listSpeech() where record.referenceID == referenceID {
            matches.append(
                DiagnosticsHistoryMatch(
                    category: HistoryCategory.speech.rawValue,
                    createdAt: record.createdAt,
                    referenceID: record.referenceID,
                    title: "AI Speech",
                    detail: "voice=\(record.voice), durationMs=\(record.durationMs), format=\(record.outputFormat)"
                )
            )
        }

        for record in try listImage() where record.referenceID == referenceID {
            matches.append(
                DiagnosticsHistoryMatch(
                    category: HistoryCategory.image.rawValue,
                    createdAt: record.createdAt,
                    referenceID: record.referenceID,
                    title: "AI Image",
                    detail: "model=\(record.model), images=\(record.imageCount), aspectRatio=\(record.aspectRatio)"
                )
            )
        }

        for record in try listMusic() where record.referenceID == referenceID {
            matches.append(
                DiagnosticsHistoryMatch(
                    category: HistoryCategory.music.rawValue,
                    createdAt: record.createdAt,
                    referenceID: record.referenceID,
                    title: "AI Music",
                    detail: "model=\(record.model), format=\(record.outputFormat), sampleRate=\(record.sampleRate)"
                )
            )
        }

        for record in try listClaudeChat() where record.referenceID == referenceID {
            let detail = "model=\(record.model), messages=\(record.messages.count)"
            matches.append(
                DiagnosticsHistoryMatch(
                    category: HistoryCategory.claudeChat.rawValue,
                    createdAt: record.createdAt,
                    referenceID: record.referenceID,
                    title: "Claude Chat",
                    detail: detail,
                    sessionID: record.sessionId
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
        removeFiles(in: dir, prefix: id.uuidString)
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

    public var errorDescription: String? {
        switch self {
        case .storageUnavailable:
            return "Unable to locate Application Support directory for history storage."
        }
    }
}
