import Foundation

public enum AppLogLevel: String, Codable {
    case info
    case error
}

public enum AppLogCategory: String, Codable {
    case aimusic
    case aispeech
    case aiimage
    case aichat
}

public struct LoggedDiagnosticError: LocalizedError {
    public let referenceID: String
    public let userMessage: String
    public let category: AppLogCategory
    public let stage: String
    public let underlyingError: Error

    public var errorDescription: String? {
        "\(userMessage) Reference ID: \(referenceID)"
    }
}

private struct AppLogEntry: Codable {
    let timestamp: String
    let level: AppLogLevel
    let category: AppLogCategory
    let event: String
    let referenceID: String?
    let message: String?
    let metadata: [String: String]
    let stackTrace: [String]?
}

private actor AppLogStore {
    private enum StoreError: Error {
        case invalidDirectory
    }

    private let fileManager = FileManager.default
    private let encoder = JSONEncoder()
    private let dayFormatter: DateFormatter
    private let timestampFormatter: ISO8601DateFormatter
    private let maxFileSizeBytes: UInt64 = 1_048_576
    private var overrideDirectoryURL: URL?

    init() {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        self.dayFormatter = formatter

        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        self.timestampFormatter = isoFormatter
    }

    func setOverrideDirectoryURL(_ url: URL?) {
        overrideDirectoryURL = url
    }

    func write(
        level: AppLogLevel,
        category: AppLogCategory,
        event: String,
        referenceID: String?,
        message: String?,
        metadata: [String: String],
        stackTrace: [String]?
    ) async {
        let entry = AppLogEntry(
            timestamp: timestampFormatter.string(from: Date()),
            level: level,
            category: category,
            event: event,
            referenceID: referenceID,
            message: message,
            metadata: metadata,
            stackTrace: stackTrace
        )

        do {
            let directoryURL = try resolveDirectoryURL()
            let fileURL = try resolveLogFileURL(in: directoryURL, category: category)
            var data = try encoder.encode(entry)
            data.append(0x0A)

            if !fileManager.fileExists(atPath: fileURL.path) {
                fileManager.createFile(atPath: fileURL.path, contents: nil)
            }

            let handle = try FileHandle(forWritingTo: fileURL)
            defer {
                try? handle.close()
            }
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        } catch {
            assertionFailure("Failed to write log entry: \(error.localizedDescription)")
        }
    }

    func logFileURLs(for category: AppLogCategory) -> [URL] {
        guard let directoryURL = try? resolveDirectoryURL(),
              let urls = try? fileManager.contentsOfDirectory(at: directoryURL, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles]) else {
            return []
        }

        return urls
            .filter { $0.lastPathComponent.hasPrefix(category.rawValue + "-") }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private func resolveDirectoryURL() throws -> URL {
        if let overrideDirectoryURL {
            try fileManager.createDirectory(at: overrideDirectoryURL, withIntermediateDirectories: true)
            return overrideDirectoryURL
        }

        guard let baseURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw StoreError.invalidDirectory
        }

        let directoryURL = baseURL
            .appendingPathComponent("CodeTool", isDirectory: true)
            .appendingPathComponent("logs", isDirectory: true)

        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        return directoryURL
    }

    private func resolveLogFileURL(in directoryURL: URL, category: AppLogCategory) throws -> URL {
        let datePart = dayFormatter.string(from: Date())
        let baseName = "\(category.rawValue)-\(datePart)"
        var index = 0

        while true {
            let suffix = index == 0 ? "" : "-\(index)"
            let fileURL = directoryURL.appendingPathComponent(baseName + suffix + ".log")

            guard fileManager.fileExists(atPath: fileURL.path) else {
                return fileURL
            }

            let attributes = try fileManager.attributesOfItem(atPath: fileURL.path)
            let fileSize = attributes[.size] as? UInt64 ?? 0
            if fileSize < maxFileSizeBytes {
                return fileURL
            }

            index += 1
        }
    }
}

public final class AppLogger {
    public static let shared = AppLogger()

    private let store = AppLogStore()

    private init() {}

    public static func makeReferenceID() -> String {
        UUID().uuidString.lowercased()
    }

    public static func summarize(text: String?, limit: Int = 180) -> String {
        guard let text else {
            return ""
        }

        let compact = text
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !compact.isEmpty else {
            return ""
        }

        if compact.count <= limit {
            return compact
        }

        let endIndex = compact.index(compact.startIndex, offsetBy: limit)
        return String(compact[..<endIndex]) + "…"
    }

    public func info(
        category: AppLogCategory,
        event: String,
        referenceID: String? = nil,
        message: String? = nil,
        metadata: [String: String] = [:]
    ) async {
        await store.write(
            level: .info,
            category: category,
            event: event,
            referenceID: referenceID,
            message: message,
            metadata: metadata,
            stackTrace: nil
        )
    }

    @discardableResult
    public func error(
        category: AppLogCategory,
        event: String,
        referenceID: String? = nil,
        message: String,
        metadata: [String: String] = [:],
        error: Error,
        stackTrace: [String] = Thread.callStackSymbols
    ) async -> String {
        let resolvedReferenceID = referenceID ?? Self.makeReferenceID()
        var enrichedMetadata = metadata
        enrich(metadata: &enrichedMetadata, with: error)

        await store.write(
            level: .error,
            category: category,
            event: event,
            referenceID: resolvedReferenceID,
            message: message,
            metadata: enrichedMetadata,
            stackTrace: stackTrace,
        )

        return resolvedReferenceID
    }

    func setDirectoryURLForTesting(_ url: URL?) async {
        await store.setOverrideDirectoryURL(url)
    }

    func logFileURLs(for category: AppLogCategory) async -> [URL] {
        await store.logFileURLs(for: category)
    }

    private func enrich(metadata: inout [String: String], with error: Error) {
        let nsError = error as NSError
        metadata["errorDomain"] = nsError.domain
        metadata["errorCode"] = String(nsError.code)
        metadata["errorDescription"] = nsError.localizedDescription

        if let failureReason = nsError.localizedFailureReason, !failureReason.isEmpty {
            metadata["failureReason"] = failureReason
        }
        if let recoverySuggestion = nsError.localizedRecoverySuggestion, !recoverySuggestion.isEmpty {
            metadata["recoverySuggestion"] = recoverySuggestion
        }

        var underlyingSummaries: [String] = []
        var nextUnderlyingError = nsError.userInfo[NSUnderlyingErrorKey] as? NSError

        while let currentError = nextUnderlyingError {
            underlyingSummaries.append("\(currentError.domain)#\(currentError.code): \(currentError.localizedDescription)")
            nextUnderlyingError = currentError.userInfo[NSUnderlyingErrorKey] as? NSError
        }

        if !underlyingSummaries.isEmpty {
            metadata["underlyingErrors"] = underlyingSummaries.joined(separator: " | ")
        }
    }
}