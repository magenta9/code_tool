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

// MARK: - HistoryCategory

public enum HistoryCategory: String, CaseIterable {
    case chat
    case speech
    case image
    case music
}

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

    private func loadRecords<T: HistoryRecord>(category: HistoryCategory) throws -> [T] {
        let dir = try categoryURL(category)
        let urls = try fileManager.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }

        var records: [T] = []
        for url in urls {
            let data = try Data(contentsOf: url)
            let record = try decoder.decode(T.self, from: data)
            records.append(record)
        }

        return records.sorted { $0.createdAt > $1.createdAt }
    }

    /// Load binary data (audio / image) for a given category and filename.
    public func loadData(category: HistoryCategory, fileName: String) throws -> Data {
        let dir = try categoryURL(category)
        return try Data(contentsOf: dir.appendingPathComponent(fileName))
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
