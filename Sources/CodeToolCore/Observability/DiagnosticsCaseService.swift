import Foundation
import CodeToolFoundation

// MARK: - Case Identity

public struct DiagnosticsCaseID: Codable, Sendable, Hashable {
    public let value: String
    public let isRecentIssuesPackage: Bool

    public init(referenceID: String?) {
        if let referenceID, !referenceID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            self.value = referenceID.trimmingCharacters(in: .whitespacesAndNewlines)
            self.isRecentIssuesPackage = false
        } else {
            self.value = "recent-issues"
            self.isRecentIssuesPackage = true
        }
    }
}

// MARK: - Case Warning

public struct DiagnosticsCaseWarning: Codable, Sendable, Identifiable {
    public let id: String
    public let timestamp: Date
    public let referenceID: String?
    public let sink: String
    public let errorDescription: String

    public init(
        timestamp: Date = Date(),
        referenceID: String?,
        sink: String,
        errorDescription: String
    ) {
        self.id = "\(sink)|\(referenceID ?? "nil")|\(timestamp.timeIntervalSince1970)"
        self.timestamp = timestamp
        self.referenceID = referenceID
        self.sink = sink
        self.errorDescription = errorDescription
    }
}

// MARK: - Case Snapshot

public struct DiagnosticsCaseSnapshot: Codable, Sendable {
    public let caseID: DiagnosticsCaseID
    let relatedEvents: [AppLogEntry]
    public let traceSummary: DiagnosticsTraceSummary?
    public let historyMatches: [DiagnosticsHistoryMatch]
    let recentIssues: [AppLogEntry]
    public let metricSummaries: [DiagnosticsMetricSummary]
    public let warnings: [DiagnosticsCaseWarning]
}

// MARK: - Ports

/// All data read from DiagnosticsStore for a single case, captured in one actor hop.
struct DiagnosticsEventStoreData: Sendable {
    let relatedEvents: [AppLogEntry]
    let trace: DiagnosticsTraceSummary?
    let recentIssues: [AppLogEntry]
    let metricSummaries: [DiagnosticsMetricSummary]
}

protocol DiagnosticsEventStorePort: Sendable {
    /// Single actor-isolated entry point — reads events, trace, issues, and metrics
    /// in one hop so they cannot disagree if logs arrive mid-assembly.
    func caseData(referenceID: String?, issuesLimit: Int, metricsLimit: Int) async throws -> DiagnosticsEventStoreData
}

protocol DiagnosticsHistoryLookupPort: Sendable {
    func diagnosticsMatches(referenceID: String) async throws -> [DiagnosticsHistoryMatch]
}

public protocol DiagnosticsCaseServicing: Sendable {
    func snapshot(referenceID: String?) async throws -> DiagnosticsCaseSnapshot
    func export(referenceID: String?) async throws -> URL
}

// MARK: - Sink Failure Warning Source

actor SinkFailureWarningSource {
    static let shared = SinkFailureWarningSource()

    private var warnings: [DiagnosticsCaseWarning] = []
    private let maxWarnings = 200

    func record(referenceID: String?, sink: String, errorDescription: String) {
        let warning = DiagnosticsCaseWarning(
            referenceID: referenceID,
            sink: sink,
            errorDescription: errorDescription
        )
        warnings.append(warning)
        if warnings.count > maxWarnings {
            warnings.removeFirst(warnings.count - maxWarnings)
        }
    }

    /// Returns warnings scoped to a referenceID, or all warnings if nil.
    func warnings(for referenceID: String?) -> [DiagnosticsCaseWarning] {
        if let referenceID, !referenceID.isEmpty {
            return warnings.filter { $0.referenceID == referenceID }
        }
        return warnings
    }

    /// Returns and removes warnings for a referenceID (or all if nil).
    func drain(referenceID: String?) -> [DiagnosticsCaseWarning] {
        let matched: [DiagnosticsCaseWarning]
        if let referenceID, !referenceID.isEmpty {
            matched = warnings.filter { $0.referenceID == referenceID }
            warnings.removeAll { $0.referenceID == referenceID }
        } else {
            matched = warnings
            warnings.removeAll()
        }
        return matched
    }

    func resetForTesting() {
        warnings.removeAll()
    }
}

// MARK: - Export Writer

struct DiagnosticsExportWriter: Sendable {
    private static let safeFilenameCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))

    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    func write(snapshot: DiagnosticsCaseSnapshot) throws -> URL {
        let package = DiagnosticsExportPackage(
            exportedAt: Date(),
            focusReferenceID: snapshot.caseID.isRecentIssuesPackage ? nil : snapshot.caseID.value,
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
            recentIssues: snapshot.recentIssues,
            relatedEvents: snapshot.relatedEvents,
            traceSummary: snapshot.traceSummary,
            historyMatches: snapshot.historyMatches,
            metricSummaries: snapshot.metricSummaries,
            warnings: snapshot.warnings
        )

        let safeRefID = Self.sanitize(snapshot.caseID.value)
        let exportURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodeTool-Diagnostics-\(safeRefID)-\(UUID().uuidString).json")
        let data = try encoder.encode(package)
        try data.write(to: exportURL, options: .atomic)
        return exportURL
    }

    private static func sanitize(_ input: String) -> String {
        String(input.unicodeScalars.map { safeFilenameCharacters.contains($0) ? Character($0) : "_" })
    }
}

// MARK: - Case Service

public actor DiagnosticsCaseService: DiagnosticsCaseServicing {
    public static let shared = DiagnosticsCaseService(
        eventStore: DiagnosticsStore.shared,
        historyLookup: HistoryStore.shared,
        warningSource: SinkFailureWarningSource.shared
    )

    private let eventStore: DiagnosticsEventStorePort
    private let historyLookup: DiagnosticsHistoryLookupPort
    private let warningSource: SinkFailureWarningSource
    private let exportWriter: DiagnosticsExportWriter

    init(
        eventStore: DiagnosticsEventStorePort,
        historyLookup: DiagnosticsHistoryLookupPort,
        warningSource: SinkFailureWarningSource,
        exportWriter: DiagnosticsExportWriter = DiagnosticsExportWriter()
    ) {
        self.eventStore = eventStore
        self.historyLookup = historyLookup
        self.warningSource = warningSource
        self.exportWriter = exportWriter
    }

    public func snapshot(referenceID: String?) async throws -> DiagnosticsCaseSnapshot {
        let caseID = DiagnosticsCaseID(referenceID: referenceID)

        // Single actor hop for all DiagnosticsStore data
        let storeData = try await eventStore.caseData(
            referenceID: caseID.isRecentIssuesPackage ? nil : caseID.value,
            issuesLimit: 20,
            metricsLimit: 10
        )

        let historyMatches: [DiagnosticsHistoryMatch]
        if !caseID.isRecentIssuesPackage {
            historyMatches = (try? await historyLookup.diagnosticsMatches(referenceID: caseID.value)) ?? []
        } else {
            historyMatches = []
        }

        let warnings = await warningSource.warnings(for: caseID.isRecentIssuesPackage ? nil : caseID.value)

        return DiagnosticsCaseSnapshot(
            caseID: caseID,
            relatedEvents: storeData.relatedEvents,
            traceSummary: storeData.trace,
            historyMatches: historyMatches,
            recentIssues: storeData.recentIssues,
            metricSummaries: storeData.metricSummaries,
            warnings: warnings
        )
    }

    public func export(referenceID: String?) async throws -> URL {
        let caseID = DiagnosticsCaseID(referenceID: referenceID)

        let storeData = try await eventStore.caseData(
            referenceID: caseID.isRecentIssuesPackage ? nil : caseID.value,
            issuesLimit: 20,
            metricsLimit: 10
        )

        let historyMatches: [DiagnosticsHistoryMatch]
        if !caseID.isRecentIssuesPackage {
            historyMatches = (try? await historyLookup.diagnosticsMatches(referenceID: caseID.value)) ?? []
        } else {
            historyMatches = []
        }

        // Drain warnings on export so they aren't duplicated in subsequent exports
        let warnings = await warningSource.drain(referenceID: caseID.isRecentIssuesPackage ? nil : caseID.value)

        let snap = DiagnosticsCaseSnapshot(
            caseID: caseID,
            relatedEvents: storeData.relatedEvents,
            traceSummary: storeData.trace,
            historyMatches: historyMatches,
            recentIssues: storeData.recentIssues,
            metricSummaries: storeData.metricSummaries,
            warnings: warnings
        )

        return try exportWriter.write(snapshot: snap)
    }

    /// Dashboard summary: recent issues and metrics for the refresh/reload path.
    func recentSummary(issuesLimit: Int = 12, metricsLimit: Int = 6) async throws -> DiagnosticsEventStoreData {
        try await eventStore.caseData(referenceID: nil, issuesLimit: issuesLimit, metricsLimit: metricsLimit)
    }

    func recentRenderingPerformance(limit: Int = 40) async throws -> RenderingPerformanceDashboard {
        let storeData = try await eventStore.caseData(referenceID: nil, issuesLimit: 0, metricsLimit: limit)
        return RenderingPerformance.makeDashboard(from: storeData.metricSummaries)
    }
}
