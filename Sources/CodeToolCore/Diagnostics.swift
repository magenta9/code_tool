import Foundation

#if canImport(MetricKit)
    import MetricKit
#endif

extension AppLogEntry: Identifiable {
    var id: String {
        [
            timestamp,
            category.rawValue,
            event,
            referenceID ?? "no-reference"
        ].joined(separator: "|")
    }

    var timestampDate: Date {
        DiagnosticsStore.timestampFormatter.date(from: timestamp) ?? .distantPast
    }
}

public struct DiagnosticsTraceSummary: Codable, Sendable {
    public let referenceID: String
    public let startedAt: Date
    public let lastUpdatedAt: Date
    public let category: String
    public let eventCount: Int
    public let stages: [String]
    public let totalDurationMs: Int?
}

public struct DiagnosticsMetricSummary: Codable, Identifiable, Sendable {
    public let id: UUID
    public let createdAt: Date
    public let kind: String
    public let metadata: [String: String]

    public init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        kind: String,
        metadata: [String: String]
    ) {
        self.id = id
        self.createdAt = createdAt
        self.kind = kind
        self.metadata = metadata
    }
}

public struct DiagnosticsHistoryMatch: Codable, Identifiable, Sendable {
    public let id: String
    public let category: String
    public let createdAt: Date
    public let referenceID: String
    public let title: String
    public let detail: String
    public let sessionID: String?

    public init(
        category: String,
        createdAt: Date,
        referenceID: String,
        title: String,
        detail: String,
        sessionID: String? = nil
    ) {
        self.id = "\(category)|\(referenceID)|\(createdAt.timeIntervalSince1970)"
        self.category = category
        self.createdAt = createdAt
        self.referenceID = referenceID
        self.title = title
        self.detail = detail
        self.sessionID = sessionID
    }
}

private struct DiagnosticsExportPackage: Codable {
    struct AppMetadata: Codable {
        let appName: String
        let version: String
        let build: String
        let buildType: String
        let systemVersion: String
    }

    let exportedAt: Date
    let focusReferenceID: String?
    let app: AppMetadata
    let recentIssues: [AppLogEntry]
    let relatedEvents: [AppLogEntry]
    let traceSummary: DiagnosticsTraceSummary?
    let historyMatches: [DiagnosticsHistoryMatch]
    let metricSummaries: [DiagnosticsMetricSummary]
}

public actor DiagnosticsStore {
    public static let shared = DiagnosticsStore()

    static let timestampFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let safeFilenameCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))

    private let fileManager = FileManager.default
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()
    private let lineEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()
    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
    private let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
    private let retentionExecutor = AppLogRetentionExecutor()
    private let eventRetention = AppLogRetentionPolicy(
        maxFileAge: 14 * 24 * 60 * 60,
        maxDirectorySizeBytes: 200 * 1_024 * 1_024
    )
    private let metricRetention = AppLogRetentionPolicy(
        maxFileAge: 7 * 24 * 60 * 60,
        maxDirectorySizeBytes: 500 * 1_024 * 1_024
    )
    private var overrideBaseURL: URL?

    public func setBaseURLForTesting(_ url: URL?) {
        overrideBaseURL = url
    }

    func record(entry: AppLogEntry) async throws {
        let directoryURL = try eventsDirectoryURL()
        let fileURL = directoryURL.appendingPathComponent("events-\(dayFormatter.string(from: entry.timestampDate)).jsonl")
        try appendJSONLine(entry, to: fileURL)
        try await retentionExecutor.prune(directoryURL: directoryURL, policy: eventRetention)
    }

    public func recordMetricSummary(_ summary: DiagnosticsMetricSummary) async throws {
        let directoryURL = try metricsDirectoryURL()
        let fileURL = directoryURL.appendingPathComponent("metrics-\(dayFormatter.string(from: summary.createdAt)).jsonl")
        try appendJSONLine(summary, to: fileURL)
        try await retentionExecutor.prune(directoryURL: directoryURL, policy: metricRetention)
    }

    func recentIssues(limit: Int = 20) async throws -> [AppLogEntry] {
        try loadEventEntries()
            .filter { $0.level == .fault || $0.level == .error }
            .sorted { $0.timestampDate > $1.timestampDate }
            .prefix(limit)
            .map { $0 }
    }

    func recentEvents(limit: Int = 50) async throws -> [AppLogEntry] {
        try loadEventEntries()
            .sorted { $0.timestampDate > $1.timestampDate }
            .prefix(limit)
            .map { $0 }
    }

    func events(referenceID: String) async throws -> [AppLogEntry] {
        try loadEventEntries()
            .filter { $0.referenceID == referenceID }
            .sorted { $0.timestampDate < $1.timestampDate }
    }

    func traceSummary(referenceID: String) async throws -> DiagnosticsTraceSummary? {
        let relatedEvents = try await events(referenceID: referenceID)
        guard let firstEvent = relatedEvents.first, let lastEvent = relatedEvents.last else {
            return nil
        }

        let stages = Array(
            Set(
                relatedEvents.compactMap { entry in
                    entry.metadata["stage"]?.trimmingCharacters(in: .whitespacesAndNewlines)
                }.filter { !$0.isEmpty }
            )
        ).sorted()

        let durationCandidates = relatedEvents.compactMap { entry -> Int? in
            if let duration = entry.durationMs {
                return duration
            }

            return entry.metadata["durationMs"].flatMap(Int.init)
        }

        return DiagnosticsTraceSummary(
            referenceID: referenceID,
            startedAt: firstEvent.timestampDate,
            lastUpdatedAt: lastEvent.timestampDate,
            category: firstEvent.category.rawValue,
            eventCount: relatedEvents.count,
            stages: stages,
            totalDurationMs: durationCandidates.max()
        )
    }

    public func recentMetricSummaries(limit: Int = 10) async throws -> [DiagnosticsMetricSummary] {
        try loadMetricEntries()
            .sorted { $0.createdAt > $1.createdAt }
            .prefix(limit)
            .map { $0 }
    }

    public func exportPackage(referenceID: String?) async throws -> URL {
        let relatedEvents: [AppLogEntry]
        let resolvedTraceSummary: DiagnosticsTraceSummary?
        let historyMatches: [DiagnosticsHistoryMatch]

        if let referenceID, !referenceID.isEmpty {
            relatedEvents = try await events(referenceID: referenceID)
            resolvedTraceSummary = try await traceSummary(referenceID: referenceID)
            historyMatches = try await HistoryStore.shared.diagnosticsMatches(referenceID: referenceID)
        } else {
            relatedEvents = []
            resolvedTraceSummary = nil
            historyMatches = []
        }

        let package = DiagnosticsExportPackage(
            exportedAt: Date(),
            focusReferenceID: referenceID,
            app: .init(
                appName: Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "CodeTool",
                version: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
                build: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown",
                buildType: {
                    #if DEBUG
                        "DEBUG"
                    #else
                        "RELEASE"
                    #endif
                }(),
                systemVersion: ProcessInfo.processInfo.operatingSystemVersionString
            ),
            recentIssues: try await recentIssues(limit: 20),
            relatedEvents: relatedEvents,
            traceSummary: resolvedTraceSummary,
            historyMatches: historyMatches,
            metricSummaries: try await recentMetricSummaries(limit: 10)
        )

        let safeRefID = sanitizeFilenameComponent(referenceID ?? "recent")
        let exportURL = fileManager.temporaryDirectory
            .appendingPathComponent("CodeTool-Diagnostics-\(safeRefID)-\(UUID().uuidString).json")
        let data = try encoder.encode(package)
        try data.write(to: exportURL, options: .atomic)
        return exportURL
    }

    nonisolated internal func sanitizeFilenameComponent(_ input: String) -> String {
        String(input.unicodeScalars.map { Self.safeFilenameCharacters.contains($0) ? Character($0) : "_" })
    }

    private func appendJSONLine<T: Encodable>(_ value: T, to fileURL: URL) throws {
        let data = try lineEncoder.encode(value)
        var line = data
        line.append(0x0A)

        if !fileManager.fileExists(atPath: fileURL.path) {
            fileManager.createFile(atPath: fileURL.path, contents: nil)
        }

        let handle = try FileHandle(forWritingTo: fileURL)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: line)
    }

    private func loadEventEntries() throws -> [AppLogEntry] {
        try loadJSONLines(in: eventsDirectoryURL(), as: AppLogEntry.self)
    }

    private func loadMetricEntries() throws -> [DiagnosticsMetricSummary] {
        try loadJSONLines(in: metricsDirectoryURL(), as: DiagnosticsMetricSummary.self)
    }

    private func loadJSONLines<T: Decodable>(in directoryURL: URL, as type: T.Type) throws -> [T] {
        let urls = try fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ).filter { $0.pathExtension == "jsonl" }

        var values: [T] = []
        for url in urls {
            let data = try Data(contentsOf: url)
            guard let content = String(data: data, encoding: .utf8) else { continue }
            for line in content.split(whereSeparator: \.isNewline) {
                do {
                    values.append(try decoder.decode(type, from: Data(line.utf8)))
                } catch {
                    continue
                }
            }
        }
        return values
    }

    private func baseURL() throws -> URL {
        if let overrideBaseURL {
            try fileManager.createDirectory(at: overrideBaseURL, withIntermediateDirectories: true)
            return overrideBaseURL
        }

        guard let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw HistoryStoreError.storageUnavailable
        }

        let baseURL = appSupport
            .appendingPathComponent("CodeTool", isDirectory: true)
            .appendingPathComponent("diagnostics", isDirectory: true)
        try fileManager.createDirectory(at: baseURL, withIntermediateDirectories: true)
        return baseURL
    }

    private func eventsDirectoryURL() throws -> URL {
        let url = try baseURL().appendingPathComponent("events", isDirectory: true)
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func metricsDirectoryURL() throws -> URL {
        let url = try baseURL().appendingPathComponent("metrics", isDirectory: true)
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

public final class ObservabilitySystem: NSObject {
    public static let shared = ObservabilitySystem()

    private let lock = NSLock()
    private let launchStartedAt = Date()
    private var isBootstrapped = false
    private var isRootViewReady = false

    public func bootstrap() {
        lock.lock()
        let shouldBootstrap = !isBootstrapped
        if shouldBootstrap {
            isBootstrapped = true
        }
        lock.unlock()

        guard shouldBootstrap else { return }

        #if canImport(MetricKit)
            MXMetricManager.shared.add(self)
        #endif

        Task {
            let metadata = self.appMetadataFields()
            await AppLogger.shared.info(
                category: .observability,
                event: "app_launch_started",
                message: "Application launch started.",
                metadata: metadata
            )

            await AppLogger.shared.log(
                level: .info,
                category: .observability,
                event: "app_launch_finished",
                message: "Application launch finished.",
                metadata: metadata,
                durationMs: Int(Date().timeIntervalSince(self.launchStartedAt) * 1000)
            )
        }
    }

    public func rootViewReady() {
        lock.lock()
        let shouldFire = !isRootViewReady
        if shouldFire {
            isRootViewReady = true
        }
        lock.unlock()

        guard shouldFire else { return }

        Task {
            await AppLogger.shared.log(
                level: .info,
                category: .observability,
                event: "root_view_ready",
                message: "Root view became ready.",
                metadata: appMetadataFields(),
                durationMs: Int(Date().timeIntervalSince(launchStartedAt) * 1000)
            )
        }
    }

    public func applicationWillTerminate() {
        Task {
            await AppLogger.shared.info(
                category: .observability,
                event: "app_terminate",
                message: "Application will terminate.",
                metadata: appMetadataFields()
            )
        }
    }

    private func appMetadataFields() -> [String: String] {
        [
            "appName": Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "CodeTool",
            "appVersion": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
            "appBuild": Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown",
            "buildType": {
                #if DEBUG
                    "DEBUG"
                #else
                    "RELEASE"
                #endif
            }(),
            "systemVersion": ProcessInfo.processInfo.operatingSystemVersionString
        ]
    }
}

#if canImport(MetricKit)
    extension ObservabilitySystem: MXMetricManagerSubscriber {
        public func didReceive(_ payloads: [MXMetricPayload]) {
            Task {
                for payload in payloads {
                    let summary = DiagnosticsMetricSummary(
                        kind: "metrickit_payload",
                        metadata: [
                            "timeRangeStart": DiagnosticsStore.timestampFormatter.string(from: payload.timeStampBegin),
                            "timeRangeEnd": DiagnosticsStore.timestampFormatter.string(from: payload.timeStampEnd),
                            "includesMultipleApplicationVersions": String(payload.includesMultipleApplicationVersions)
                        ]
                    )
                    try? await DiagnosticsStore.shared.recordMetricSummary(summary)
                }

                await AppLogger.shared.info(
                    category: .observability,
                    event: "metrickit_payload_received",
                    message: "Received MetricKit payloads.",
                    metadata: ["payloadCount": String(payloads.count)]
                )
            }
        }
    }
#endif
