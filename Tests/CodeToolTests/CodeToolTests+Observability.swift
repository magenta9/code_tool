import Foundation
import XCTest

@testable import CodeToolCore
@testable import CodeToolFoundation

extension CodeToolTests {
    func testRedactionPolicyHashesTextWithoutPreviewByDefault() {
        let result = AppRedactionPolicy.standard.redact(text: "secret prompt")

        XCTAssertEqual(result?.length, 13)
        XCTAssertEqual(
            result?.sha256,
            "d6051e73b4e9a50e6a735ffba9494dd514acb71df325045501b0cbc8d206e20f"
        )
        XCTAssertNil(result?.preview)
        XCTAssertEqual(result?.summary, "len=13, sha256=d6051e73b4e9")
    }

    func testRedactionPolicyCanIncludePreviewWhenExplicitlyEnabled() {
        let policy = AppRedactionPolicy(includeSensitivePreview: true, previewLimit: 6)
        let result = policy.redact(text: "secret prompt")

        XCTAssertEqual(result?.preview, "secret…")
        XCTAssertEqual(result?.summary, "len=13, sha256=d6051e73b4e9, preview=secret…")
    }

    func testInfoLoggingAddsObservabilityEnvelopeWithoutBreakingLegacyFields() async throws {
        await AppLogger.shared.info(
            category: .aichat,
            event: "request_started",
            referenceID: "phase1-ref",
            message: "Started request.",
            metadata: ["stage": "request_chat_completion"]
        )

        let entries = try await logEntries(for: .aichat)
        let entry = try XCTUnwrap(entries.first)

        XCTAssertEqual(entry.level, .info)
        XCTAssertEqual(entry.subsystem, AppLogger.subsystem)
        XCTAssertEqual(entry.category, .aichat)
        XCTAssertEqual(entry.event, "request_started")
        XCTAssertEqual(entry.referenceID, "phase1-ref")
        XCTAssertEqual(entry.message, "Started request.")
        XCTAssertEqual(entry.metadata["stage"], "request_chat_completion")
        XCTAssertNil(entry.durationMs)
    }

    func testRetentionExecutorPrunesExpiredAndOversizedFiles() async throws {
        let tempDirectoryURL = try makeTemporaryDirectory(prefix: "ObservabilityRetention")
        defer { try? FileManager.default.removeItem(at: tempDirectoryURL) }

        let expiredURL = tempDirectoryURL.appendingPathComponent("aichat-expired.log")
        let olderRecentURL = tempDirectoryURL.appendingPathComponent("aichat-older.log")
        let newestURL = tempDirectoryURL.appendingPathComponent("aichat-newest.log")

        try Data(repeating: 0x61, count: 10).write(to: expiredURL)
        try Data(repeating: 0x62, count: 10).write(to: olderRecentURL)
        try Data(repeating: 0x63, count: 10).write(to: newestURL)

        let now = Date(timeIntervalSince1970: 1_710_000_000)
        try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-10 * 24 * 60 * 60)], ofItemAtPath: expiredURL.path)
        try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-2 * 60 * 60)], ofItemAtPath: olderRecentURL.path)
        try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-60)], ofItemAtPath: newestURL.path)

        try await AppLogRetentionExecutor().prune(
            directoryURL: tempDirectoryURL,
            policy: AppLogRetentionPolicy(maxFileAge: 7 * 24 * 60 * 60, maxDirectorySizeBytes: 15),
            now: now
        )

        let remainingNames = try FileManager.default.contentsOfDirectory(atPath: tempDirectoryURL.path).sorted()
        XCTAssertEqual(remainingNames, ["aichat-newest.log"])
    }

    func testUnifiedLogSinkFormatsEventAndReferenceIDAndMessage() {
        let entry = AppLogEntry(
            timestamp: "2024-01-01T00:00:00.000Z",
            level: .info,
            subsystem: "com.test",
            category: .observability,
            event: "test_event",
            referenceID: "ref-123",
            message: "Something happened.",
            durationMs: nil,
            metadata: [:],
            stackTrace: nil
        )

        let formatted = AppUnifiedLogSink().formattedMessage(for: entry)
        XCTAssertTrue(formatted.contains("event=test_event"))
        XCTAssertTrue(formatted.contains("referenceID=ref-123"))
        XCTAssertTrue(formatted.contains("message=Something happened."))
    }

    func testUnifiedLogSinkSanitizesNewlinesInFields() {
        let entry = AppLogEntry(
            timestamp: "2024-01-01T00:00:00.000Z",
            level: .info,
            subsystem: "com.test",
            category: .observability,
            event: "event\ninjected",
            referenceID: "ref\r123",
            message: "line1\nline2",
            durationMs: nil,
            metadata: [:],
            stackTrace: nil
        )

        let formatted = AppUnifiedLogSink().formattedMessage(for: entry)
        XCTAssertFalse(formatted.contains("\n"))
        XCTAssertFalse(formatted.contains("\r"))
        XCTAssertTrue(formatted.contains("\\n"))
        XCTAssertTrue(formatted.contains("\\r"))
    }

    func testSanitizeFilenameComponentNormalizesUnsafeCharacters() {
        let store = DiagnosticsStore.shared

        XCTAssertEqual(store.sanitizeFilenameComponent("safe-ref_123"), "safe-ref_123")
        XCTAssertEqual(store.sanitizeFilenameComponent("ABCabc0123"), "ABCabc0123")
        XCTAssertEqual(store.sanitizeFilenameComponent("../etc/passwd"), "___etc_passwd")
        XCTAssertEqual(store.sanitizeFilenameComponent("ref\\back"), "ref_back")
        XCTAssertEqual(store.sanitizeFilenameComponent(""), "")
        XCTAssertEqual(store.sanitizeFilenameComponent("hello world!"), "hello_world_")
        XCTAssertEqual(store.sanitizeFilenameComponent("ref@#$%"), "ref____")
    }

    func testRootViewReadyIsIdempotent() async throws {
        let observability = ObservabilitySystem()

        observability.rootViewReady()
        observability.rootViewReady()
        observability.rootViewReady()

        try await Task.sleep(nanoseconds: asyncLogPropagationDelay)

        let logFiles = await AppLogger.shared.logFileURLs(for: .observability)
        let allEntries: [AppLogEntry] = try logFiles.flatMap { url -> [AppLogEntry] in
            let data = try Data(contentsOf: url)
            let lines = String(decoding: data, as: UTF8.self).split(whereSeparator: \.isNewline)
            return try lines.enumerated().map { index, line in
                do {
                    return try JSONDecoder().decode(AppLogEntry.self, from: Data(line.utf8))
                } catch {
                    struct DecodeError: Error, CustomStringConvertible {
                        let description: String
                    }
                    throw DecodeError(description: "JSON decode failed at \(url.lastPathComponent) line \(index): \(error)")
                }
            }
        }

        let readyEvents = allEntries.filter { $0.event == "root_view_ready" }
        XCTAssertEqual(readyEvents.count, 1)
    }

    func testRenderingPerformanceDashboardSummarizesCacheAndLagMetrics() {
        let metrics = [
            DiagnosticsMetricSummary(
                createdAt: Date(timeIntervalSince1970: 30),
                kind: RenderingPerformance.metricKind,
                metadata: [
                    "event": RenderingPerformanceEvent.toolCacheSnapshot.rawValue,
                    "selectedToolID": ToolID.aiChat.rawValue,
                    "retainedCount": "3",
                    "mountedCount": "3",
                    "hiddenMountedCount": "2"
                ]
            ),
            DiagnosticsMetricSummary(
                createdAt: Date(timeIntervalSince1970: 20),
                kind: RenderingPerformance.metricKind,
                metadata: [
                    "event": RenderingPerformanceEvent.toolSwitchFinished.rawValue,
                    "durationMs": "96"
                ]
            ),
            DiagnosticsMetricSummary(
                createdAt: Date(timeIntervalSince1970: 10),
                kind: RenderingPerformance.metricKind,
                metadata: [
                    "event": RenderingPerformanceEvent.interactionLagObserved.rawValue,
                    "durationMs": "41"
                ]
            ),
            DiagnosticsMetricSummary(
                createdAt: Date(timeIntervalSince1970: 5),
                kind: "metrickit_payload",
                metadata: ["payloadCount": "1"]
            )
        ]

        let dashboard = RenderingPerformance.makeDashboard(from: metrics, captureEnabled: true)

        XCTAssertTrue(dashboard.isCaptureEnabled)
        XCTAssertEqual(dashboard.latestSelectedToolID, ToolID.aiChat.rawValue)
        XCTAssertEqual(dashboard.latestRetainedCount, 3)
        XCTAssertEqual(dashboard.latestMountedCount, 3)
        XCTAssertEqual(dashboard.latestHiddenMountedCount, 2)
        XCTAssertEqual(dashboard.maxRetainedCount, 3)
        XCTAssertEqual(dashboard.maxHiddenMountedCount, 2)
        XCTAssertEqual(dashboard.interactionLagSampleCount, 1)
        XCTAssertEqual(dashboard.maxInteractionLagMs, 41)
        XCTAssertEqual(dashboard.slowToolSwitchCount, 1)
        XCTAssertEqual(dashboard.maxToolSwitchDurationMs, 96)
        XCTAssertEqual(dashboard.recentEntries.count, 3)
    }
}