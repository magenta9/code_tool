import Foundation
import XCTest

@testable import CodeToolCore
@testable import CodeToolFoundation

private actor MockEventStore: DiagnosticsEventStorePort {
    var relatedEvents: [AppLogEntry] = []
    var trace: DiagnosticsTraceSummary? = nil
    var recentIssues: [AppLogEntry] = []
    var metricSummaries: [DiagnosticsMetricSummary] = []

    func caseData(referenceID: String?, issuesLimit: Int, metricsLimit: Int) async throws -> DiagnosticsEventStoreData {
        let events: [AppLogEntry]
        let resolvedTrace: DiagnosticsTraceSummary?
        if referenceID != nil {
            events = relatedEvents
            resolvedTrace = trace
        } else {
            events = []
            resolvedTrace = nil
        }

        return DiagnosticsEventStoreData(
            relatedEvents: events,
            trace: resolvedTrace,
            recentIssues: Array(recentIssues.prefix(issuesLimit)),
            metricSummaries: Array(metricSummaries.prefix(metricsLimit))
        )
    }

    func setEvents(_ events: [AppLogEntry]) {
        relatedEvents = events
    }

    func setTrace(_ trace: DiagnosticsTraceSummary?) {
        self.trace = trace
    }

    func setRecentIssues(_ issues: [AppLogEntry]) {
        recentIssues = issues
    }

    func setMetrics(_ metrics: [DiagnosticsMetricSummary]) {
        metricSummaries = metrics
    }
}

private actor MockHistoryLookup: DiagnosticsHistoryLookupPort {
    var matches: [DiagnosticsHistoryMatch] = []

    func diagnosticsMatches(referenceID: String) async throws -> [DiagnosticsHistoryMatch] {
        matches.filter { $0.referenceID == referenceID }
    }

    func setMatches(_ matches: [DiagnosticsHistoryMatch]) {
        self.matches = matches
    }
}

extension CodeToolTests {
    private func makeCaseService(
        eventStore: MockEventStore = MockEventStore(),
        historyLookup: MockHistoryLookup = MockHistoryLookup(),
        warningSource: SinkFailureWarningSource = SinkFailureWarningSource()
    ) -> (DiagnosticsCaseService, MockEventStore, MockHistoryLookup, SinkFailureWarningSource) {
        let service = DiagnosticsCaseService(
            eventStore: eventStore,
            historyLookup: historyLookup,
            warningSource: warningSource
        )
        return (service, eventStore, historyLookup, warningSource)
    }

    func testDiagnosticsStoreAggregatesReferenceIDAcrossLogsAndHistory() async throws {
        let referenceID = "diag-ref-001"
        let historyTempDirectory = try makeTemporaryDirectory(prefix: "HistoryDiagnostics")
        defer { try? FileManager.default.removeItem(at: historyTempDirectory) }

        await HistoryStore.shared.setBaseURLForTesting(historyTempDirectory)
        defer { Task { await HistoryStore.shared.setBaseURLForTesting(nil) } }

        await AppLogger.shared.info(
            category: .claudechat,
            event: "claude_process_started",
            referenceID: referenceID,
            message: "Started Claude CLI subprocess.",
            metadata: ["stage": "launch_process"]
        )
        _ = await AppLogger.shared.error(
            category: .claudechat,
            event: "claude_process_failed",
            referenceID: referenceID,
            message: "Claude CLI subprocess exited with a non-zero status.",
            metadata: ["stage": "process_exit", "exitCode": "1"],
            error: NSError(domain: "ClaudeCLIClient.exit", code: 1)
        )

        try await HistoryStore.shared.save(
            ClaudeChatHistoryRecord(
                messages: [ClaudeChatMessageRecord(role: "user", content: "hi")],
                model: "claude-sonnet-4-20250514",
                sessionId: "session-001",
                referenceID: referenceID
            )
        )

        let service = DiagnosticsCaseService(
            eventStore: DiagnosticsStore.shared,
            historyLookup: HistoryStore.shared,
            warningSource: SinkFailureWarningSource()
        )
        let snapshot = try await service.snapshot(referenceID: referenceID)

        XCTAssertTrue(snapshot.recentIssues.contains { $0.referenceID == referenceID })
        XCTAssertEqual(snapshot.traceSummary?.referenceID, referenceID)
        XCTAssertEqual(snapshot.traceSummary?.eventCount, snapshot.relatedEvents.count)
        XCTAssertEqual(snapshot.historyMatches.count, 1)
        XCTAssertEqual(snapshot.historyMatches.first?.sessionID, "session-001")
    }

    func testDiagnosticsExportPackageIncludesHistoryAndMetrics() async throws {
        let referenceID = "diag-export-001"
        let historyTempDirectory = try makeTemporaryDirectory(prefix: "HistoryExport")
        defer { try? FileManager.default.removeItem(at: historyTempDirectory) }

        await HistoryStore.shared.setBaseURLForTesting(historyTempDirectory)
        defer { Task { await HistoryStore.shared.setBaseURLForTesting(nil) } }

        await AppLogger.shared.info(
            category: .aichat,
            event: "request_started",
            referenceID: referenceID,
            message: "Started AI Chat request.",
            metadata: ["stage": "request_chat_completion"]
        )
        try await DiagnosticsStore.shared.recordMetricSummary(
            DiagnosticsMetricSummary(kind: "metrickit_payload", metadata: ["payloadCount": "1"])
        )
        try await HistoryStore.shared.save(
            ChatHistoryRecord(
                id: UUID(),
                createdAt: Date(),
                systemPrompt: "",
                messages: [ChatMessageRecord(role: "user", content: "Hello")],
                model: "MiniMax-Text-01",
                promptTokens: 1,
                completionTokens: 1,
                totalTokens: 2,
                referenceID: referenceID
            )
        )

        let service = DiagnosticsCaseService(
            eventStore: DiagnosticsStore.shared,
            historyLookup: HistoryStore.shared,
            warningSource: SinkFailureWarningSource()
        )
        let exportURL = try await service.export(referenceID: referenceID)
        let data = try Data(contentsOf: exportURL)
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(payload["focusReferenceID"] as? String, referenceID)
        XCTAssertNotNil(payload["recentIssues"])
        XCTAssertNotNil(payload["relatedEvents"])
        XCTAssertNotNil(payload["historyMatches"])
        XCTAssertNotNil(payload["metricSummaries"])
        XCTAssertNotNil(payload["warnings"])
    }

    func testCaseSnapshotWithoutReferenceIDReturnsRecentIssuesPackage() async throws {
        let (service, _, _, _) = makeCaseService()

        for referenceID in [nil, "   "] {
            let snapshot = try await service.snapshot(referenceID: referenceID)
            XCTAssertTrue(snapshot.caseID.isRecentIssuesPackage)
            XCTAssertTrue(snapshot.relatedEvents.isEmpty)
            XCTAssertTrue(snapshot.historyMatches.isEmpty)
            XCTAssertNil(snapshot.traceSummary)
        }
    }

    func testCaseSnapshotTraceSummaryEventCountMatchesRelatedEvents() async throws {
        let mockStore = MockEventStore()
        let events = [
            AppLogEntry(
                timestamp: "2025-01-01T00:00:00.000Z",
                level: .info,
                subsystem: "test",
                category: .aichat,
                event: "started",
                referenceID: "ref-1",
                message: "e1",
                durationMs: nil,
                metadata: [:],
                stackTrace: nil
            ),
            AppLogEntry(
                timestamp: "2025-01-01T00:00:01.000Z",
                level: .info,
                subsystem: "test",
                category: .aichat,
                event: "finished",
                referenceID: "ref-1",
                message: "e2",
                durationMs: nil,
                metadata: [:],
                stackTrace: nil
            )
        ]
        let trace = DiagnosticsTraceSummary(
            referenceID: "ref-1",
            startedAt: Date(),
            lastUpdatedAt: Date(),
            category: "aichat",
            eventCount: 2,
            stages: [],
            totalDurationMs: nil
        )
        await mockStore.setEvents(events)
        await mockStore.setTrace(trace)

        let (service, _, _, _) = makeCaseService(eventStore: mockStore)
        let snapshot = try await service.snapshot(referenceID: "ref-1")
        XCTAssertEqual(snapshot.traceSummary?.eventCount, snapshot.relatedEvents.count)
    }

    func testCaseExportNilReferenceIDProducesValidJSON() async throws {
        let (service, _, _, _) = makeCaseService()
        let exportURL = try await service.export(referenceID: nil)
        defer { try? FileManager.default.removeItem(at: exportURL) }

        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: exportURL)) as? [String: Any])
        XCTAssertNil(payload["focusReferenceID"] as? String)
        XCTAssertNotNil(payload["recentIssues"])
        XCTAssertNotNil(payload["warnings"])
    }

    func testCaseIDTrimsWhitespace() {
        let caseID = DiagnosticsCaseID(referenceID: "  ref-123  ")
        XCTAssertEqual(caseID.value, "ref-123")
        XCTAssertFalse(caseID.isRecentIssuesPackage)
    }

    func testWarningsAreScopedByReferenceID() async throws {
        let warningSource = SinkFailureWarningSource()
        await warningSource.record(referenceID: "ref-A", sink: "file", errorDescription: "err-A")
        await warningSource.record(referenceID: "ref-B", sink: "diagnostics", errorDescription: "err-B")
        await warningSource.record(referenceID: nil, sink: "unified", errorDescription: "err-nil")

        let (service, _, _, _) = makeCaseService(warningSource: warningSource)
        let snapshotA = try await service.snapshot(referenceID: "ref-A")
        XCTAssertEqual(snapshotA.warnings.count, 1)
        XCTAssertEqual(snapshotA.warnings.first?.sink, "file")

        let snapshotB = try await service.snapshot(referenceID: "ref-B")
        XCTAssertEqual(snapshotB.warnings.count, 1)
        XCTAssertEqual(snapshotB.warnings.first?.sink, "diagnostics")
    }

    func testExportDrainsWarnings() async throws {
        let warningSource = SinkFailureWarningSource()
        await warningSource.record(referenceID: "ref-drain", sink: "file", errorDescription: "err1")

        let (service, _, _, _) = makeCaseService(warningSource: warningSource)

        let firstURL = try await service.export(referenceID: "ref-drain")
        defer { try? FileManager.default.removeItem(at: firstURL) }
        let firstPayload = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: firstURL)) as? [String: Any])
        XCTAssertEqual((firstPayload["warnings"] as? [[String: Any]] ?? []).count, 1)

        let secondURL = try await service.export(referenceID: "ref-drain")
        defer { try? FileManager.default.removeItem(at: secondURL) }
        let secondPayload = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: secondURL)) as? [String: Any])
        XCTAssertEqual((secondPayload["warnings"] as? [[String: Any]] ?? []).count, 0)
    }

    func testSinkFailureWarningSourceResetForTesting() async throws {
        let warningSource = SinkFailureWarningSource()
        await warningSource.record(referenceID: "ref-1", sink: "file", errorDescription: "err")

        let before = await warningSource.warnings(for: nil)
        XCTAssertEqual(before.count, 1)

        await warningSource.resetForTesting()
        let after = await warningSource.warnings(for: nil)
        XCTAssertEqual(after.count, 0)
    }

    func testDiagnosticsCaseServiceConformsToServicingProtocol() {
        let service: any DiagnosticsCaseServicing = DiagnosticsCaseService.shared
        XCTAssertNotNil(service)
    }
}