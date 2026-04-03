import CodeToolFoundation
import CryptoKit
import Foundation
import OSLog

public struct AppRedactedValue: Codable, Equatable, Sendable {
    public let summary: String
    public let length: Int
    public let sha256: String
    public let preview: String?
}

extension AppLogLevel {
    var osLogType: OSLogType {
        switch self {
        case .fault:
            return .fault
        case .error:
            return .error
        case .info:
            return .info
        case .debug, .trace:
            return .debug
        }
    }
}

public struct AppRedactionPolicy: Sendable {
    public static let standard = AppRedactionPolicy()

    public let includeSensitivePreview: Bool
    public let previewLimit: Int

    public init(includeSensitivePreview: Bool = false, previewLimit: Int = 24) {
        self.includeSensitivePreview = includeSensitivePreview
        self.previewLimit = max(0, previewLimit)
    }

    public func redact(text: String?) -> AppRedactedValue? {
        guard let normalized = normalize(text), !normalized.isEmpty else {
            return nil
        }

        let sha256 = SHA256.hash(data: Data(normalized.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        let preview = makePreview(for: normalized)

        var summary = "len=\(normalized.count), sha256=\(sha256.prefix(12))"
        if let preview {
            summary += ", preview=\(preview)"
        }

        return AppRedactedValue(
            summary: summary,
            length: normalized.count,
            sha256: sha256,
            preview: preview
        )
    }

    private func normalize(_ text: String?) -> String? {
        text?
            .replacingOccurrences(of: "\r", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func makePreview(for text: String) -> String? {
        guard includeSensitivePreview, previewLimit > 0 else {
            return nil
        }

        if text.count <= previewLimit {
            return text
        }

        let endIndex = text.index(text.startIndex, offsetBy: previewLimit)
        return String(text[..<endIndex]) + "…"
    }
}

struct AppLogEntry: Codable, Sendable {
    let timestamp: String
    let level: AppLogLevel
    let subsystem: String
    let category: AppLogCategory
    let event: String
    let referenceID: String?
    let message: String?
    let durationMs: Int?
    let metadata: [String: String]
    let stackTrace: [String]?
}

struct AppLogRetentionPolicy: Sendable {
    let maxFileAge: TimeInterval
    let maxDirectorySizeBytes: UInt64

    init(
        maxFileAge: TimeInterval = 14 * 24 * 60 * 60,
        maxDirectorySizeBytes: UInt64 = 200 * 1_024 * 1_024
    ) {
        self.maxFileAge = maxFileAge
        self.maxDirectorySizeBytes = maxDirectorySizeBytes
    }
}

actor AppLogRetentionExecutor {
    private struct FileRecord {
        let url: URL
        let modificationDate: Date
        let size: UInt64
    }

    private let fileManager = FileManager.default

    func prune(
        directoryURL: URL,
        policy: AppLogRetentionPolicy,
        now: Date = Date()
    ) async throws {
        var records = try fileRecords(in: directoryURL)

        let oldestAllowedDate = now.addingTimeInterval(-policy.maxFileAge)
        let expiredURLs = records
            .filter { $0.modificationDate < oldestAllowedDate }
            .map(\.url)

        for url in expiredURLs {
            try? fileManager.removeItem(at: url)
        }

        records = try fileRecords(in: directoryURL)
            .sorted { $0.modificationDate < $1.modificationDate }

        var totalSize = records.reduce(0) { $0 + $1.size }
        while totalSize > policy.maxDirectorySizeBytes, let record = records.first {
            try? fileManager.removeItem(at: record.url)
            totalSize -= record.size
            records.removeFirst()
        }
    }

    private func fileRecords(in directoryURL: URL) throws -> [FileRecord] {
        try fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ).compactMap { url in
            let values = try url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey])
            guard values.isRegularFile == true else {
                return nil
            }

            return FileRecord(
                url: url,
                modificationDate: values.contentModificationDate ?? .distantPast,
                size: UInt64(values.fileSize ?? 0)
            )
        }
    }
}

protocol AppLogSink: Sendable {
    func write(entry: AppLogEntry) async throws
}

protocol AppRemoteLogSink: AppLogSink {}

struct AppUnifiedLogSink: AppLogSink {
    func write(entry: AppLogEntry) async throws {
        let logger = Logger(subsystem: entry.subsystem, category: entry.category.rawValue)
        let payload = formattedMessage(for: entry)
        logger.log(level: entry.level.osLogType, "\(payload, privacy: .public)")
    }

    internal func formattedMessage(for entry: AppLogEntry) -> String {
        var components = ["event=\(sanitizeLogField(entry.event))"]

        if let referenceID = entry.referenceID, !referenceID.isEmpty {
            components.append("referenceID=\(sanitizeLogField(referenceID))")
        }

        if let message = entry.message, !message.isEmpty {
            components.append("message=\(sanitizeLogField(message))")
        }

        return components.joined(separator: " ")
    }

    private func sanitizeLogField(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
    }
}
