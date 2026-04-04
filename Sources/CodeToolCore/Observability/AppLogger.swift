import CodeToolFoundation
import Foundation

public struct LoggedDiagnosticError: LocalizedError {
    public let referenceID: String
    public let userMessage: String
    public let category: AppLogCategory
    public let stage: String
    public let underlyingError: Error

    public var errorDescription: String? {
        var parts = [userMessage]

        if let detail = userFacingDetail {
            parts.append(detail)
        }

        parts.append("Reference ID: \(referenceID)")
        return parts.joined(separator: " ")
    }

    private var userFacingDetail: String? {
        if let userFacingError = underlyingError as? UserFacingError,
           let description = userFacingError.userFacingDescription {
            return description
        }

        if category == .aimusic,
           let urlError = underlyingError as? URLError,
           urlError.code == .networkConnectionLost {
            return "The connection dropped before MiniMax returned any music data. This usually means the upstream request sat idle for about 60 seconds. Try shorter lyrics or retry with 32kHz and 128k settings."
        }

        let detail = underlyingError.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !detail.isEmpty, detail != userMessage else {
            return nil
        }

        return detail
    }
}

private actor AppFileLogSink {
    private enum StoreError: Error {
        case invalidDirectory
    }

    private let fileManager = FileManager.default
    private let encoder = JSONEncoder()
    private let dayFormatter: DateFormatter
    private let retentionExecutor = AppLogRetentionExecutor()
    private let retentionPolicy = AppLogRetentionPolicy()
    private let maxFileSizeBytes: UInt64 = 1_048_576
    private var overrideDirectoryURL: URL?

    init() {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        self.dayFormatter = formatter
    }

    func setOverrideDirectoryURL(_ url: URL?) {
        overrideDirectoryURL = url
    }

    func write(entry: AppLogEntry) async throws {
        let directoryURL = try resolveDirectoryURL()
        let fileURL = try resolveLogFileURL(in: directoryURL, category: entry.category)
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
        try await retentionExecutor.prune(directoryURL: directoryURL, policy: retentionPolicy)
    }

    func logFileURLs(for category: AppLogCategory) -> [URL] {
        guard let directoryURL = try? resolveDirectoryURL(),
              let urls = try? fileManager.contentsOfDirectory(
                at: directoryURL,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
              ) else {
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

private actor AppLoggerPipeline {
    private let unifiedSink = AppUnifiedLogSink()
    private let fileSink = AppFileLogSink()
    private var isReportingInternalFailure = false

    func emit(_ entry: AppLogEntry) async {
        do {
            try await unifiedSink.write(entry: entry)
        } catch {
            await reportInternalFailure(sink: "unified", error: error, entry: entry)
        }

        do {
            try await fileSink.write(entry: entry)
        } catch {
            await reportInternalFailure(sink: "file", error: error, entry: entry)
        }

        do {
            try await DiagnosticsStore.shared.record(entry: entry)
        } catch {
            await reportInternalFailure(sink: "diagnostics", error: error, entry: entry)
        }
    }

    func setDirectoryURLForTesting(_ url: URL?) async {
        await fileSink.setOverrideDirectoryURL(url)
    }

    func logFileURLs(for category: AppLogCategory) async -> [URL] {
        await fileSink.logFileURLs(for: category)
    }

    private func reportInternalFailure(sink: String, error: Error, entry: AppLogEntry) async {
        guard !isReportingInternalFailure else {
            return
        }

        isReportingInternalFailure = true
        defer { isReportingInternalFailure = false }

        await SinkFailureWarningSource.shared.record(
            referenceID: entry.referenceID,
            sink: sink,
            errorDescription: error.localizedDescription
        )

        let internalEntry = AppLogEntry(
            timestamp: AppLogger.makeTimestamp(),
            level: .fault,
            subsystem: AppLogger.subsystem,
            category: .observability,
            event: "observability_sink_failed",
            referenceID: entry.referenceID,
            message: "Observability sink failed.",
            durationMs: nil,
            metadata: [
                "sink": sink,
                "originalCategory": entry.category.rawValue,
                "originalEvent": entry.event,
                "errorDescription": error.localizedDescription
            ],
            stackTrace: nil
        )

        try? await unifiedSink.write(entry: internalEntry)
        try? await fileSink.write(entry: internalEntry)
    }
}

public final class AppLogger {
    public static let subsystem = "com.codetool.app"
    public static let shared = AppLogger()

    private let pipeline = AppLoggerPipeline()

    private init() {}

    public static func makeReferenceID() -> String {
        UUID().uuidString.lowercased()
    }

    private static let timestampFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static func makeTimestamp(date: Date = Date()) -> String {
        timestampFormatter.string(from: date)
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

    public func log(
        level: AppLogLevel,
        category: AppLogCategory,
        event: String,
        referenceID: String? = nil,
        message: String? = nil,
        metadata: [String: String] = [:],
        durationMs: Int? = nil,
        stackTrace: [String]? = nil
    ) async {
        let entry = AppLogEntry(
            timestamp: Self.makeTimestamp(),
            level: level,
            subsystem: Self.subsystem,
            category: category,
            event: event,
            referenceID: referenceID,
            message: message,
            durationMs: durationMs,
            metadata: metadata,
            stackTrace: stackTrace
        )

        await pipeline.emit(entry)
    }

    public func info(
        category: AppLogCategory,
        event: String,
        referenceID: String? = nil,
        message: String? = nil,
        metadata: [String: String] = [:]
    ) async {
        await log(
            level: .info,
            category: category,
            event: event,
            referenceID: referenceID,
            message: message,
            metadata: metadata
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

        await log(
            level: .error,
            category: category,
            event: event,
            referenceID: resolvedReferenceID,
            message: message,
            metadata: enrichedMetadata,
            stackTrace: stackTrace
        )

        return resolvedReferenceID
    }

    func setDirectoryURLForTesting(_ url: URL?) async {
        await pipeline.setDirectoryURLForTesting(url)
    }

    func logFileURLs(for category: AppLogCategory) async -> [URL] {
        await pipeline.logFileURLs(for: category)
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
