import Foundation
import XCTest

@testable import CodeToolCore
@testable import CodeToolFoundation

#if canImport(SwiftUI)
    import SwiftUI
#endif

private final class MockURLProtocol: URLProtocol {
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

final class CodeToolTests: XCTestCase {
    private var miniMaxClient: MiniMaxAPIClient!

    // MARK: - Tool model tests

    func testToolInitialization() {
        let tool = Tool(name: "Test Tool", description: "A test.", systemImage: "star")
        XCTAssertFalse(tool.id.uuidString.isEmpty)
        XCTAssertEqual(tool.name, "Test Tool")
        XCTAssertEqual(tool.description, "A test.")
        XCTAssertEqual(tool.systemImage, "star")
    }

    func testToolHashable() {
        let tool1 = Tool(name: "A", description: "A", systemImage: "a")
        let tool2 = Tool(name: "A", description: "A", systemImage: "a")
        // Different UUIDs mean they are not equal
        XCTAssertNotEqual(tool1, tool2)
        let set: Set<Tool> = [tool1, tool2]
        XCTAssertEqual(set.count, 2)
    }

    // MARK: - ToolRegistry tests

    private var savedDefaults: [Tool] = []
    private var savedConfig: MiniMaxConfig = .defaults
    private var savedClaudePath = ""
    private var savedClaudeAPIKey = ""
    private var savedClaudeModel = ""
    private var savedClaudeSystemPrompt = ""
    private var savedClaudeMaxTurns = 10
    private var savedClaudeMaxBudgetUSD = 5.0
    private var savedClaudeUseBare = true
    private var savedClaudePermissionMode = ""
    private var temporaryLogDirectoryURL: URL?
    private var temporaryDiagnosticsDirectoryURL: URL?
    private let asyncLogPropagationDelay: UInt64 = 300_000_000 // 300 ms: async Tasks writing to actors may take a few event-loop turns

    override func setUp() {
        super.setUp()
        savedDefaults = ToolRegistry.defaults

        let store = MiniMaxSettingsStore.shared
        savedConfig = store.currentConfig

        let claudeStore = ClaudeCLISettingsStore.shared
        savedClaudePath = claudeStore.claudePath
        savedClaudeAPIKey = claudeStore.apiKey
        savedClaudeModel = claudeStore.model
        savedClaudeSystemPrompt = claudeStore.systemPrompt
        savedClaudeMaxTurns = claudeStore.maxTurns
        savedClaudeMaxBudgetUSD = claudeStore.maxBudgetUSD
        savedClaudeUseBare = claudeStore.useBare
        savedClaudePermissionMode = claudeStore.permissionMode.rawValue

        store.apiKey = "test-api-key"
        store.baseURL = "https://example.com/v1"

        URLProtocol.registerClass(MockURLProtocol.self)
        MockURLProtocol.requestHandler = nil
        miniMaxClient = MiniMaxAPIClient.makeTestingClient(urlProtocolType: MockURLProtocol.self)

        let tempDirectoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodeToolTests-\(UUID().uuidString)", isDirectory: true)
        temporaryLogDirectoryURL = tempDirectoryURL
        try? FileManager.default.createDirectory(
            at: tempDirectoryURL, withIntermediateDirectories: true)

        let tempDiagnosticsDirectoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodeToolDiagnosticsTests-\(UUID().uuidString)", isDirectory: true)
        temporaryDiagnosticsDirectoryURL = tempDiagnosticsDirectoryURL
        try? FileManager.default.createDirectory(
            at: tempDiagnosticsDirectoryURL, withIntermediateDirectories: true)

        let setupExpectation = expectation(description: "configure log directory")
        Task {
            await AppLogger.shared.setDirectoryURLForTesting(tempDirectoryURL)
            await DiagnosticsStore.shared.setBaseURLForTesting(tempDiagnosticsDirectoryURL)
            setupExpectation.fulfill()
        }
        wait(for: [setupExpectation], timeout: 2.0)
    }

    override func tearDown() {
        ToolRegistry.defaults = savedDefaults

        let store = MiniMaxSettingsStore.shared
        store.apiKey = savedConfig.apiKey
        store.baseURL = savedConfig.baseURL
        store.chatModel = savedConfig.chatModel
        store.speechModel = savedConfig.speechModel
        store.imageModel = savedConfig.imageModel
        store.musicModel = savedConfig.musicModel

        let claudeStore = ClaudeCLISettingsStore.shared
        claudeStore.claudePath = savedClaudePath
        claudeStore.apiKey = savedClaudeAPIKey
        claudeStore.model = savedClaudeModel
        claudeStore.systemPrompt = savedClaudeSystemPrompt
        claudeStore.maxTurns = savedClaudeMaxTurns
        claudeStore.maxBudgetUSD = savedClaudeMaxBudgetUSD
        claudeStore.useBare = savedClaudeUseBare
        claudeStore.permissionMode =
            ClaudeCLIPermissionMode(rawValue: savedClaudePermissionMode) ?? .auto
        claudeStore.discoverCLI()

        MockURLProtocol.requestHandler = nil
        miniMaxClient = nil
        URLProtocol.unregisterClass(MockURLProtocol.self)

        let resetExpectation = expectation(description: "reset log directory")
        Task {
            await AppLogger.shared.setDirectoryURLForTesting(nil)
            await DiagnosticsStore.shared.setBaseURLForTesting(nil)
            resetExpectation.fulfill()
        }
        wait(for: [resetExpectation], timeout: 2.0)

        if let temporaryLogDirectoryURL {
            try? FileManager.default.removeItem(at: temporaryLogDirectoryURL)
        }
        if let temporaryDiagnosticsDirectoryURL {
            try? FileManager.default.removeItem(at: temporaryDiagnosticsDirectoryURL)
        }

        super.tearDown()
    }

    private func logContent(for category: AppLogCategory) async throws -> String {
        let logFiles = await AppLogger.shared.logFileURLs(for: category)
        XCTAssertEqual(logFiles.count, 1)

        let logData = try Data(contentsOf: try XCTUnwrap(logFiles.first))
        return try XCTUnwrap(String(data: logData, encoding: .utf8))
    }

    private func logEntries(for category: AppLogCategory) async throws -> [AppLogEntry] {
        let logFiles = await AppLogger.shared.logFileURLs(for: category)
        XCTAssertEqual(logFiles.count, 1)

        let logData = try Data(contentsOf: try XCTUnwrap(logFiles.first))
        let lines = try XCTUnwrap(String(data: logData, encoding: .utf8))
            .split(whereSeparator: \.isNewline)

        return try lines.map { line in
            try JSONDecoder().decode(AppLogEntry.self, from: Data(line.utf8))
        }
    }

    private static func requestBodyData(for request: URLRequest) throws -> Data {
        if let body = request.httpBody {
            return body
        }

        guard let stream = request.httpBodyStream else {
            XCTFail("Expected request body data")
            return Data()
        }

        stream.open()
        defer { stream.close() }

        var data = Data()
        let bufferSize = 4096
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }

        while true {
            let readCount = stream.read(buffer, maxLength: bufferSize)
            if readCount < 0 {
                throw stream.streamError ?? URLError(.cannotDecodeRawData)
            }
            if readCount == 0 {
                break
            }
            data.append(buffer, count: readCount)
        }

        return data
    }

    func testRegistryDefaultsNotEmpty() {
        XCTAssertFalse(ToolRegistry.defaults.isEmpty)
    }

    func testRegistryContainsTenTools() {
        XCTAssertEqual(ToolRegistry.defaults.count, 10)
    }

    func testRegistryDefaultNamesAreUnique() {
        let names = ToolRegistry.defaults.map(\.name)
        let uniqueNames = Set(names)
        XCTAssertEqual(names.count, uniqueNames.count)
    }

    func testRegistryContainsExpectedTools() {
        let names = Set(ToolRegistry.defaults.map(\.name))
        let expected: Set<String> = [
            "JSON Tool", "Image Converter", "JSON Diff",
            "Timestamp Converter", "JWT Tool", "Word Cloud",
            "AI Chat", "AI Speech", "AI Image", "AI Music",
        ]
        XCTAssertEqual(names, expected)
    }

    func testRegistryCanRegisterAdditionalTool() {
        let originalCount = ToolRegistry.defaults.count
        let extra = Tool(name: "Extra Tool", description: "Extra.", systemImage: "star")
        ToolRegistry.defaults.append(extra)
        XCTAssertEqual(ToolRegistry.defaults.count, originalCount + 1)
    }

    func testClaudeCLISettingsStoreDefaults() {
        let store = ClaudeCLISettingsStore.shared
        store.resetToDefaults()

        XCTAssertEqual(store.model, "claude-sonnet-4-20250514")
        XCTAssertEqual(store.maxTurns, 10)
        XCTAssertEqual(store.maxBudgetUSD, 5.0)
        XCTAssertTrue(store.useBare)
        XCTAssertEqual(store.permissionMode, .bypassPermissions)
    }

    func testClaudeChatHistoryRecordCodable() throws {
        let record = ClaudeChatHistoryRecord(
            workingDirectory: "/tmp/demo-project",
            messages: [
                ClaudeChatMessageRecord(role: "user", content: "Hello"),
                ClaudeChatMessageRecord(
                    role: "assistant",
                    content: "Hi",
                    thinkingContent: "User says hello"
                ),
            ],
            model: "claude-sonnet-4-20250514",
            totalCostUSD: 0.05,
            inputTokens: 100,
            outputTokens: 10,
            referenceID: "test-ref"
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(record)
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(ClaudeChatHistoryRecord.self, from: data)

        XCTAssertEqual(decoded.id, record.id)
        XCTAssertEqual(decoded.messages.count, 2)
        XCTAssertEqual(decoded.messages[1].thinkingContent, "User says hello")
        XCTAssertEqual(decoded.totalCostUSD, 0.05)
        XCTAssertEqual(decoded.workingDirectory, "/tmp/demo-project")
    }

    func testClaudeChatHistoryRecordCodableBackwardCompatibilityWithoutWorkingDirectory() throws {
        let json = """
        {
          "id": "B3B7B6A9-7A7F-42D2-8D54-CA8E77F594B1",
          "createdAt": "2026-04-03T00:00:00Z",
          "messages": [
            {
              "role": "user",
              "content": "Hello"
            }
          ],
          "model": "claude-sonnet-4-20250514",
          "referenceID": "test-ref"
        }
        """

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(ClaudeChatHistoryRecord.self, from: Data(json.utf8))

        XCTAssertNil(decoded.workingDirectory)
        XCTAssertEqual(decoded.messages.count, 1)
        XCTAssertEqual(decoded.model, "claude-sonnet-4-20250514")
    }

    func testClaudeCLIClientUsesResumeForExistingSession() async throws {
        let tempDirectory = try XCTUnwrap(temporaryLogDirectoryURL)
        let scriptURL = tempDirectory.appendingPathComponent("fake-claude.sh")
        let argsLogURL = tempDirectory.appendingPathComponent("claude-args.log")

        let script = """
        #!/bin/zsh
        print -rl -- \"$@\" > \"$CODETOOL_CLAUDE_ARGS_LOG\"
        print '{\"type\":\"system\",\"subtype\":\"init\",\"session_id\":\"8f600fbd-4226-4700-8a30-6988f438c595\",\"model\":\"claude-sonnet-4-20250514\"}'
        print '{\"type\":\"result\",\"is_error\":false,\"total_cost_usd\":0,\"duration_ms\":1,\"usage\":{\"input_tokens\":1,\"output_tokens\":1},\"session_id\":\"8f600fbd-4226-4700-8a30-6988f438c595\"}'
        """

        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: scriptURL.path
        )

        setenv("CODETOOL_CLAUDE_ARGS_LOG", argsLogURL.path, 1)
        defer { unsetenv("CODETOOL_CLAUDE_ARGS_LOG") }

        let store = ClaudeCLISettingsStore.shared
        store.claudePath = scriptURL.path
        store.discoverCLI()

        let client = ClaudeCLIClient()
        await client.send(
            message: "你好",
            settings: store,
            sessionId: "4cde10f7-cc71-4d25-8472-f9737d911dc8",
            workingDirectory: tempDirectory.path
        ) { _ in }

        let argsText = try String(contentsOf: argsLogURL, encoding: .utf8)
        let args = argsText
            .split(whereSeparator: \.isNewline)
            .map(String.init)

        XCTAssertTrue(args.contains("--resume"))
        XCTAssertFalse(args.contains("--session-id"))
        let resumeIndex = try XCTUnwrap(args.firstIndex(of: "--resume"))
        XCTAssertEqual(args[resumeIndex + 1], "4cde10f7-cc71-4d25-8472-f9737d911dc8")
    }

    func testClaudeCLIClientUsesConfiguredPermissionMode() async throws {
        let tempDirectory = try XCTUnwrap(temporaryLogDirectoryURL)
        let scriptURL = tempDirectory.appendingPathComponent("fake-claude-permissions.sh")
        let argsLogURL = tempDirectory.appendingPathComponent("claude-permissions-args.log")

        let script = """
        #!/bin/zsh
        print -rl -- \"$@\" > \"$CODETOOL_CLAUDE_ARGS_LOG\"
        print '{\"type\":\"system\",\"subtype\":\"init\",\"session_id\":\"permission-session\",\"model\":\"claude-sonnet-4-20250514\"}'
        print '{\"type\":\"result\",\"is_error\":false,\"total_cost_usd\":0,\"duration_ms\":1,\"usage\":{\"input_tokens\":1,\"output_tokens\":1},\"session_id\":\"permission-session\"}'
        """

        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: scriptURL.path
        )

        setenv("CODETOOL_CLAUDE_ARGS_LOG", argsLogURL.path, 1)
        defer { unsetenv("CODETOOL_CLAUDE_ARGS_LOG") }

        let store = ClaudeCLISettingsStore.shared
        store.claudePath = scriptURL.path
        store.permissionMode = .auto
        store.discoverCLI()

        let client = ClaudeCLIClient()
        await client.send(
            message: "search the web",
            settings: store,
            sessionId: nil,
            workingDirectory: tempDirectory.path
        ) { _ in }

        let argsText = try String(contentsOf: argsLogURL, encoding: .utf8)
        let args = argsText
            .split(whereSeparator: \.isNewline)
            .map(String.init)

        let permissionModeIndex = try XCTUnwrap(args.firstIndex(of: "--permission-mode"))
        XCTAssertEqual(args[permissionModeIndex + 1], "auto")
    }

    func testClaudeCLIClientEmitsToolResultFromStreamEvent() async throws {
        let tempDirectory = try XCTUnwrap(temporaryLogDirectoryURL)
        let scriptURL = tempDirectory.appendingPathComponent("fake-claude-tool-result.sh")

        let script = """
        #!/bin/zsh
        print '{\"type\":\"system\",\"subtype\":\"init\",\"session_id\":\"tool-session\",\"model\":\"claude-sonnet-4-20250514\"}'
        print '{\"type\":\"stream_event\",\"event\":{\"type\":\"content_block_start\",\"index\":0,\"content_block\":{\"type\":\"tool_use\",\"id\":\"toolu_123\",\"name\":\"mcp_jina_search_web\",\"input\":{}}}}'
        print '{\"type\":\"stream_event\",\"event\":{\"type\":\"content_block_delta\",\"index\":0,\"delta\":{\"type\":\"input_json_delta\",\"partial_json\":\"{\\\"query\\\":\\\"latest chapter\\\"}\"}}}'
        print '{\"type\":\"stream_event\",\"event\":{\"type\":\"content_block_stop\",\"index\":0}}'
        print '{\"type\":\"stream_event\",\"event\":{\"type\":\"content_block_start\",\"index\":1,\"content_block\":{\"type\":\"tool_result\",\"tool_use_id\":\"toolu_123\",\"content\":\"search results\"}}}'
        print '{\"type\":\"stream_event\",\"event\":{\"type\":\"content_block_stop\",\"index\":1}}'
        print '{\"type\":\"result\",\"is_error\":false,\"total_cost_usd\":0,\"duration_ms\":1,\"usage\":{\"input_tokens\":1,\"output_tokens\":1},\"session_id\":\"tool-session\"}'
        """

        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: scriptURL.path
        )

        let store = ClaudeCLISettingsStore.shared
        store.claudePath = scriptURL.path
        store.discoverCLI()

        let client = ClaudeCLIClient()
        var receivedEvents: [ClaudeCLIEvent] = []

        await client.send(
            message: "find something",
            settings: store,
            sessionId: nil,
            workingDirectory: tempDirectory.path
        ) { event in
            receivedEvents.append(event)
        }

        guard case .toolUseStart(let toolUseId, let toolName) = receivedEvents.first(where: {
            if case .toolUseStart = $0 { return true }
            return false
        }) else {
            return XCTFail("Expected tool use start event")
        }
        XCTAssertEqual(toolUseId, "toolu_123")
        XCTAssertEqual(toolName, "mcp_jina_search_web")

        guard case .toolResult(let resultToolUseId, let content) = receivedEvents.first(where: {
            if case .toolResult = $0 { return true }
            return false
        }) else {
            return XCTFail("Expected tool result event")
        }
        XCTAssertEqual(resultToolUseId, "toolu_123")
        XCTAssertEqual(content, "search results")
    }

    func testClaudeCLIClientUsesExplicitWorkingDirectory() async throws {
        let tempDirectory = try XCTUnwrap(temporaryLogDirectoryURL)
        let scriptURL = tempDirectory.appendingPathComponent("fake-claude-working-dir.sh")
        let cwdLogURL = tempDirectory.appendingPathComponent("claude-cwd.log")
        let workingDirectoryURL = tempDirectory.appendingPathComponent("workspace", isDirectory: true)

        try FileManager.default.createDirectory(
            at: workingDirectoryURL,
            withIntermediateDirectories: true
        )

        let script = """
        #!/bin/zsh
        print -r -- "$PWD" > "$CODETOOL_CLAUDE_CWD_LOG"
        print '{"type":"system","subtype":"init","session_id":"working-dir-session","model":"claude-sonnet-4-20250514"}'
        print '{"type":"result","is_error":false,"total_cost_usd":0,"duration_ms":1,"usage":{"input_tokens":1,"output_tokens":1},"session_id":"working-dir-session"}'
        """

        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: scriptURL.path
        )

        setenv("CODETOOL_CLAUDE_CWD_LOG", cwdLogURL.path, 1)
        defer { unsetenv("CODETOOL_CLAUDE_CWD_LOG") }

        let store = ClaudeCLISettingsStore.shared
        store.claudePath = scriptURL.path
        store.discoverCLI()

        let client = ClaudeCLIClient()
        await client.send(
            message: "pwd",
            settings: store,
            sessionId: nil,
            workingDirectory: workingDirectoryURL.path
        ) { _ in }

        let cwd = try String(contentsOf: cwdLogURL, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        XCTAssertEqual(
            URL(fileURLWithPath: cwd).resolvingSymlinksInPath().path,
            workingDirectoryURL.resolvingSymlinksInPath().path
        )
    }

    func testToolViewCacheRetainsVisitedToolsInSelectionOrder() {
        var retainedToolNames: [String] = []

        retainedToolNames = ToolViewCache.retainedToolNames(
            current: retainedToolNames,
            selectedToolName: "JSON Tool"
        )
        XCTAssertEqual(retainedToolNames, ["JSON Tool"])

        retainedToolNames = ToolViewCache.retainedToolNames(
            current: retainedToolNames,
            selectedToolName: "Image Converter"
        )
        XCTAssertEqual(retainedToolNames, ["JSON Tool", "Image Converter"])

        retainedToolNames = ToolViewCache.retainedToolNames(
            current: retainedToolNames,
            selectedToolName: "JSON Tool"
        )
        XCTAssertEqual(retainedToolNames, ["JSON Tool", "Image Converter"])

        retainedToolNames = ToolViewCache.retainedToolNames(
            current: retainedToolNames,
            selectedToolName: nil
        )
        XCTAssertEqual(retainedToolNames, ["JSON Tool", "Image Converter"])
    }

    #if canImport(SwiftUI)
        func testContentViewDoesNotUseNavigationSplitView() {
            let bodyTypeDescription = String(describing: type(of: ContentView().body))
            XCTAssertFalse(bodyTypeDescription.contains("NavigationSplitView"))
        }
    #endif

    func testTextToSpeechRequestsHexOutputAndDecodesHexAudio() async throws {
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.url?.path, "/v1/t2a_v2")

            let bodyData = try Self.requestBodyData(for: request)
            let bodyObject = try XCTUnwrap(
                JSONSerialization.jsonObject(with: bodyData) as? [String: Any])
            XCTAssertEqual(bodyObject["output_format"] as? String, "hex")

            let audioSetting = try XCTUnwrap(bodyObject["audio_setting"] as? [String: Any])
            XCTAssertEqual(audioSetting["format"] as? String, "mp3")

            let responseBody: [String: Any] = [
                "base_resp": [
                    "status_code": 0,
                    "status_msg": "success",
                ],
                "data": [
                    "audio": "48656c6c6f"
                ],
                "extra_info": [
                    "audio_length": 321
                ],
            ]

            let responseData = try JSONSerialization.data(withJSONObject: responseBody)
            let response = try XCTUnwrap(
                HTTPURLResponse(
                    url: try XCTUnwrap(request.url), statusCode: 200, httpVersion: nil,
                    headerFields: nil))
            return (response, responseData)
        }

        let response = try await miniMaxClient.textToSpeech(text: "Hello")

        XCTAssertEqual(response.audioData, Data("Hello".utf8))
        XCTAssertEqual(response.format, "mp3")
        XCTAssertEqual(response.durationMs, 321)
        XCTAssertFalse(response.referenceID.isEmpty)
    }

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
        let policy = AppRedactionPolicy(
            includeSensitivePreview: true,
            previewLimit: 6
        )

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
        let tempDirectoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ObservabilityRetention-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectoryURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectoryURL) }

        let expiredURL = tempDirectoryURL.appendingPathComponent("aichat-expired.log")
        let olderRecentURL = tempDirectoryURL.appendingPathComponent("aichat-older.log")
        let newestURL = tempDirectoryURL.appendingPathComponent("aichat-newest.log")

        try Data(repeating: 0x61, count: 10).write(to: expiredURL)
        try Data(repeating: 0x62, count: 10).write(to: olderRecentURL)
        try Data(repeating: 0x63, count: 10).write(to: newestURL)

        let now = Date(timeIntervalSince1970: 1_710_000_000)
        try FileManager.default.setAttributes(
            [.modificationDate: now.addingTimeInterval(-10 * 24 * 60 * 60)],
            ofItemAtPath: expiredURL.path
        )
        try FileManager.default.setAttributes(
            [.modificationDate: now.addingTimeInterval(-2 * 60 * 60)],
            ofItemAtPath: olderRecentURL.path
        )
        try FileManager.default.setAttributes(
            [.modificationDate: now.addingTimeInterval(-60)],
            ofItemAtPath: newestURL.path
        )

        let executor = AppLogRetentionExecutor()
        try await executor.prune(
            directoryURL: tempDirectoryURL,
            policy: AppLogRetentionPolicy(
                maxFileAge: 7 * 24 * 60 * 60,
                maxDirectorySizeBytes: 15
            ),
            now: now
        )

        let remainingNames = try FileManager.default.contentsOfDirectory(
            atPath: tempDirectoryURL.path
        ).sorted()

        XCTAssertEqual(remainingNames, ["aichat-newest.log"])
    }

    func testDiagnosticsStoreAggregatesReferenceIDAcrossLogsAndHistory() async throws {
        let referenceID = "diag-ref-001"
        let historyTempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("HistoryDiagnostics-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: historyTempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: historyTempDirectory) }

        await HistoryStore.shared.setBaseURLForTesting(historyTempDirectory)
        defer {
            Task { await HistoryStore.shared.setBaseURLForTesting(nil) }
        }

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

        let record = ClaudeChatHistoryRecord(
            messages: [ClaudeChatMessageRecord(role: "user", content: "hi")],
            model: "claude-sonnet-4-20250514",
            sessionId: "session-001",
            referenceID: referenceID
        )
        try await HistoryStore.shared.save(record)

        let recentIssues = try await DiagnosticsStore.shared.recentIssues(limit: 10)
        let traceSummary = try await DiagnosticsStore.shared.traceSummary(referenceID: referenceID)
        let matches = try await HistoryStore.shared.diagnosticsMatches(referenceID: referenceID)

        XCTAssertTrue(recentIssues.contains { $0.referenceID == referenceID })
        XCTAssertEqual(traceSummary?.referenceID, referenceID)
        XCTAssertEqual(traceSummary?.eventCount, 2)
        XCTAssertEqual(matches.count, 1)
        XCTAssertEqual(matches.first?.sessionID, "session-001")
    }

    func testDiagnosticsExportPackageIncludesHistoryAndMetrics() async throws {
        let referenceID = "diag-export-001"
        let historyTempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("HistoryExport-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: historyTempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: historyTempDirectory) }

        await HistoryStore.shared.setBaseURLForTesting(historyTempDirectory)
        defer {
            Task { await HistoryStore.shared.setBaseURLForTesting(nil) }
        }

        await AppLogger.shared.info(
            category: .aichat,
            event: "request_started",
            referenceID: referenceID,
            message: "Started AI Chat request.",
            metadata: ["stage": "request_chat_completion"]
        )
        try await DiagnosticsStore.shared.recordMetricSummary(
            DiagnosticsMetricSummary(
                kind: "metrickit_payload",
                metadata: ["payloadCount": "1"]
            )
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

        let exportURL = try await DiagnosticsStore.shared.exportPackage(referenceID: referenceID)
        let data = try Data(contentsOf: exportURL)
        let payload = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )

        XCTAssertEqual(payload["focusReferenceID"] as? String, referenceID)
        XCTAssertNotNil(payload["recentIssues"])
        XCTAssertNotNil(payload["relatedEvents"])
        XCTAssertNotNil(payload["historyMatches"])
        XCTAssertNotNil(payload["metricSummaries"])
    }

    func testTextToSpeechTimeoutWritesStructuredErrorLog() async throws {
        let sensitiveText = "private speech text"

        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.url?.path, "/v1/t2a_v2")
            throw URLError(.timedOut)
        }

        do {
            _ = try await miniMaxClient.textToSpeech(text: sensitiveText)
            XCTFail("Expected textToSpeech to throw")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("Reference ID:"))

            let logContent = try await logContent(for: .aispeech)
            XCTAssertTrue(logContent.contains("request_started"))
            XCTAssertTrue(logContent.contains("request_failed"))
            XCTAssertTrue(logContent.contains("request_text_to_speech"))
            XCTAssertTrue(logContent.contains("NSURLErrorDomain"))
            XCTAssertFalse(logContent.contains(sensitiveText))
        }
    }

    func testGenerateImageAPIErrorWritesStructuredErrorLog() async throws {
        let sensitivePrompt = "private image prompt"

        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.url?.path, "/v1/image_generation")

            let responseBody: [String: Any] = [
                "base_resp": [
                    "status_code": 4001,
                    "status_msg": "invalid prompt",
                ]
            ]

            let responseData = try JSONSerialization.data(withJSONObject: responseBody)
            let response = try XCTUnwrap(
                HTTPURLResponse(
                    url: try XCTUnwrap(request.url), statusCode: 500, httpVersion: nil,
                    headerFields: nil))
            return (response, responseData)
        }

        do {
            _ = try await miniMaxClient.generateImage(prompt: sensitivePrompt)
            XCTFail("Expected generateImage to throw")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("Reference ID:"))

            let logContent = try await logContent(for: .aiimage)
            XCTAssertTrue(logContent.contains("request_started"))
            XCTAssertTrue(logContent.contains("request_failed"))
            XCTAssertTrue(logContent.contains("request_image_generation"))
            XCTAssertTrue(logContent.contains("4001"))
            XCTAssertFalse(logContent.contains(sensitivePrompt))
        }
    }

    func testChatCompletionStreamAPIErrorWritesStructuredErrorLog() async throws {
        let sensitivePrompt = "private chat prompt"
        let referenceID = "chat-ref-001"

        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.url?.path, "/v1/chat/completions")

            let responseBody: [String: Any] = [
                "base_resp": [
                    "status_code": 4290,
                    "status_msg": "rate limited",
                ]
            ]

            let responseData = try JSONSerialization.data(withJSONObject: responseBody)
            let response = try XCTUnwrap(
                HTTPURLResponse(
                    url: try XCTUnwrap(request.url), statusCode: 429, httpVersion: nil,
                    headerFields: nil))
            return (response, responseData)
        }

        do {
            try await miniMaxClient.chatCompletionStream(
                messages: [MiniMaxAPIClient.ChatMessage(role: "user", content: sensitivePrompt)],
                referenceID: referenceID
            ) { _ in }
            XCTFail("Expected chatCompletionStream to throw")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("Reference ID: \(referenceID)"))

            let logContent = try await logContent(for: .aichat)
            XCTAssertTrue(logContent.contains("request_started"))
            XCTAssertTrue(logContent.contains("request_failed"))
            XCTAssertTrue(logContent.contains("stream_chat_completion"))
            XCTAssertTrue(logContent.contains(referenceID))
            XCTAssertFalse(logContent.contains(sensitivePrompt))
        }
    }

    func testGenerateMusicWithLyricsUsesURLTransportAndParsesAudioURL() async throws {
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.url?.path, "/v1/music_generation")

            let bodyData = try Self.requestBodyData(for: request)
            let bodyObject = try XCTUnwrap(
                JSONSerialization.jsonObject(with: bodyData) as? [String: Any])
            XCTAssertEqual(bodyObject["output_format"] as? String, "url")
            XCTAssertNil(bodyObject["lyrics_optimizer"])
            XCTAssertNotNil(bodyObject["lyrics"])

            let audioSetting = try XCTUnwrap(bodyObject["audio_setting"] as? [String: Any])
            XCTAssertEqual(audioSetting["sample_rate"] as? Int, 44100)
            XCTAssertEqual(audioSetting["bitrate"] as? Int, 256000)
            XCTAssertEqual(audioSetting["format"] as? String, "mp3")

            let responseBody: [String: Any] = [
                "data": [
                    "audio": "https://example.com/generated-with-lyrics.mp3",
                    "status": 2,
                ],
                "trace_id": "trace-123",
                "base_resp": [
                    "status_code": 0,
                    "status_msg": "success",
                ],
            ]

            let responseData = try JSONSerialization.data(withJSONObject: responseBody)
            let response = try XCTUnwrap(
                HTTPURLResponse(
                    url: try XCTUnwrap(request.url), statusCode: 200, httpVersion: nil,
                    headerFields: nil))
            return (response, responseData)
        }

        let response = try await miniMaxClient.generateMusic(
            prompt: "folk song",
            lyrics: "[Verse]\nHello world"
        )

        XCTAssertNil(response.audioData)
        XCTAssertEqual(response.audioURL, "https://example.com/generated-with-lyrics.mp3")
        XCTAssertFalse(response.referenceID.isEmpty)
    }

    func testGenerateMusicTimeoutWritesStructuredErrorLog() async throws {
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.url?.path, "/v1/music_generation")
            throw URLError(.timedOut)
        }

        do {
            _ = try await miniMaxClient.generateMusic(
                prompt: "slow orchestral soundtrack")
            XCTFail("Expected generateMusic to throw")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("Reference ID:"))

            let logFiles = await AppLogger.shared.logFileURLs(for: .aimusic)
            XCTAssertEqual(logFiles.count, 1)

            let logData = try Data(contentsOf: try XCTUnwrap(logFiles.first))
            let logContent = try XCTUnwrap(String(data: logData, encoding: .utf8))

            XCTAssertTrue(logContent.contains("request_started"))
            XCTAssertTrue(logContent.contains("music_request_failed"))
            XCTAssertTrue(logContent.contains("request_music_generation"))
            XCTAssertTrue(logContent.contains("NSURLErrorDomain"))
            XCTAssertTrue(logContent.contains("-1001"))
            XCTAssertTrue(logContent.contains("stackTrace"))
        }
    }

    func testGenerateMusicUnsupportedModelSurfacesActionableError() async throws {
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.url?.path, "/v1/music_generation")

            let responseBody: [String: Any] = [
                "data": NSNull(),
                "trace_id": "trace-unsupported-model",
                "base_resp": [
                    "status_code": 2061,
                    "status_msg": "your current token plan not support model, music-2.5+",
                ],
            ]

            let responseData = try JSONSerialization.data(withJSONObject: responseBody)
            let response = try XCTUnwrap(
                HTTPURLResponse(
                    url: try XCTUnwrap(request.url), statusCode: 200, httpVersion: nil,
                    headerFields: nil))
            return (response, responseData)
        }

        do {
            _ = try await miniMaxClient.generateMusic(prompt: "dark piano")
            XCTFail("Expected generateMusic to throw")
        } catch {
            XCTAssertTrue(
                error.localizedDescription.contains(
                    "Current MiniMax token plan does not support the configured music model."))
            XCTAssertTrue(error.localizedDescription.contains("MiniMax Settings"))
            XCTAssertTrue(error.localizedDescription.contains("Reference ID:"))
        }
    }

    func testGenerateMusicNetworkConnectionLostSurfacesIdleTimeoutHint() async throws {
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.url?.path, "/v1/music_generation")
            throw URLError(.networkConnectionLost)
        }

        do {
            _ = try await miniMaxClient.generateMusic(
                prompt: "dark piano", lyrics: "[Verse]\nHello\n[Chorus]\nWorld")
            XCTFail("Expected generateMusic to throw")
        } catch {
            XCTAssertTrue(
                error.localizedDescription.contains(
                    "upstream request sat idle for about 60 seconds"))
            XCTAssertTrue(error.localizedDescription.contains("32kHz and 128k"))
            XCTAssertTrue(error.localizedDescription.contains("Reference ID:"))
        }
    }

    func testGenerateMusicWithoutLyricsUsesLyricsOptimizerAndReturnsURL() async throws {
        var requestCount = 0

        MockURLProtocol.requestHandler = { request in
            requestCount += 1
            XCTAssertEqual(request.url?.path, "/v1/music_generation")
            XCTAssertEqual(request.httpMethod, "POST")

            let bodyData = try Self.requestBodyData(for: request)
            let bodyObject = try XCTUnwrap(
                JSONSerialization.jsonObject(with: bodyData) as? [String: Any])

            XCTAssertEqual(bodyObject["model"] as? String, MiniMaxSettingsStore.shared.musicModel)
            XCTAssertEqual(bodyObject["output_format"] as? String, "url")
            XCTAssertEqual(bodyObject["lyrics_optimizer"] as? Bool, true)
            XCTAssertNil(bodyObject["lyrics"])

            let responseBody: [String: Any] = [
                "data": [
                    "audio": "https://example.com/generated.mp3",
                    "status": 2,
                ],
                "trace_id": "trace-456",
                "base_resp": [
                    "status_code": 0,
                    "status_msg": "success",
                ],
            ]

            let responseData = try JSONSerialization.data(withJSONObject: responseBody)
            let response = try XCTUnwrap(
                HTTPURLResponse(
                    url: try XCTUnwrap(request.url), statusCode: 200, httpVersion: nil,
                    headerFields: nil))
            return (response, responseData)
        }

        let response = try await miniMaxClient.generateMusic(
            prompt: "folk song", lyrics: nil)

        XCTAssertEqual(requestCount, 1)
        XCTAssertNil(response.audioData)
        XCTAssertEqual(response.audioURL, "https://example.com/generated.mp3")
        XCTAssertFalse(response.referenceID.isEmpty)
    }

    func testGenerateMusicWithEmptyLyricsUsesLyricsOptimizer() async throws {
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.url?.path, "/v1/music_generation")

            let bodyData = try Self.requestBodyData(for: request)
            let bodyObject = try XCTUnwrap(
                JSONSerialization.jsonObject(with: bodyData) as? [String: Any])

            XCTAssertEqual(bodyObject["lyrics_optimizer"] as? Bool, true)
            XCTAssertNil(bodyObject["lyrics"])
            XCTAssertNil(bodyObject["is_instrumental"])

            let responseBody: [String: Any] = [
                "data": [
                    "audio": "https://example.com/generated-no-lyrics.mp3",
                    "status": 2,
                ],
                "trace_id": "trace-789",
                "base_resp": [
                    "status_code": 0,
                    "status_msg": "success",
                ],
            ]

            let responseData = try JSONSerialization.data(withJSONObject: responseBody)
            let response = try XCTUnwrap(
                HTTPURLResponse(
                    url: try XCTUnwrap(request.url), statusCode: 200, httpVersion: nil,
                    headerFields: nil))
            return (response, responseData)
        }

        let response = try await miniMaxClient.generateMusic(
            prompt: "ambient track", lyrics: "")

        XCTAssertNil(response.audioData)
        XCTAssertEqual(response.audioURL, "https://example.com/generated-no-lyrics.mp3")
        XCTAssertFalse(response.referenceID.isEmpty)
    }

    func testGenerateMusicDoesNotQueryLegacyMusicStatusEndpoint() async throws {
        var receivedPaths: [String] = []

        MockURLProtocol.requestHandler = { request in
            let path = request.url?.path ?? ""
            receivedPaths.append(path)

            if path == "/v1/music_generation" {
                let responseBody: [String: Any] = [
                    "data": [
                        "status": 1
                    ],
                    "trace_id": "trace-pending",
                    "base_resp": [
                        "status_code": 0,
                        "status_msg": "success",
                    ],
                ]

                let responseData = try JSONSerialization.data(withJSONObject: responseBody)
                let response = try XCTUnwrap(
                    HTTPURLResponse(
                        url: try XCTUnwrap(request.url), statusCode: 200, httpVersion: nil,
                        headerFields: nil))
                return (response, responseData)
            }

            XCTFail("Unexpected legacy query path: \(path)")
            throw URLError(.badURL)
        }

        do {
            _ = try await miniMaxClient.generateMusic(prompt: "folk song", lyrics: nil)
            XCTFail("Expected generateMusic to fail when music API does not return audio payload")
        } catch {
            XCTAssertEqual(receivedPaths, ["/v1/music_generation"])
            XCTAssertTrue(error.localizedDescription.contains("Reference ID:"))
        }
    }

    // MARK: - Claude CLI Optimization Tests

    func testClaudeChatConversationRecordReusesStableID() async throws {
        let stableID = UUID()
        let stableCreatedAt = Date()

        let record1 = ClaudeChatHistoryRecord(
            id: stableID,
            createdAt: stableCreatedAt,
            messages: [
                ClaudeChatMessageRecord(role: "user", content: "Hello")
            ],
            model: "claude-sonnet-4-20250514",
            referenceID: "ref-1"
        )

        let record2 = ClaudeChatHistoryRecord(
            id: stableID,
            createdAt: stableCreatedAt,
            messages: [
                ClaudeChatMessageRecord(role: "user", content: "Hello"),
                ClaudeChatMessageRecord(role: "assistant", content: "Hi there"),
                ClaudeChatMessageRecord(role: "user", content: "How are you?"),
            ],
            model: "claude-sonnet-4-20250514",
            totalCostUSD: 0.01,
            referenceID: "ref-2"
        )

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("HistoryStoreTest-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        await HistoryStore.shared.setBaseURLForTesting(tempDir)
        defer {
            Task { await HistoryStore.shared.setBaseURLForTesting(nil) }
        }

        // Save first version
        try await HistoryStore.shared.save(record1)
        var records: [ClaudeChatHistoryRecord] = try await HistoryStore.shared.listClaudeChat()
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.messages.count, 1)

        // Save updated version with same ID — should overwrite, not create second file
        try await HistoryStore.shared.save(record2)
        records = try await HistoryStore.shared.listClaudeChat()
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.messages.count, 3)
        XCTAssertEqual(records.first?.id, stableID)
        XCTAssertEqual(records.first?.totalCostUSD, 0.01)
    }

    func testClaudeChatAttachmentRecordCodable() throws {
        let attachment = ClaudeChatAttachmentRecord(
            type: "image",
            fileName: "abc-photo.png",
            mimeType: "image/png",
            sizeBytes: 12345
        )

        let message = ClaudeChatMessageRecord(
            role: "user",
            content: "Check this image",
            attachments: [attachment]
        )

        let record = ClaudeChatHistoryRecord(
            messages: [message],
            model: "claude-sonnet-4-20250514",
            referenceID: "test-attachment-ref"
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(record)
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(ClaudeChatHistoryRecord.self, from: data)

        XCTAssertEqual(decoded.messages.count, 1)
        let decodedAttachments = try XCTUnwrap(decoded.messages.first?.attachments)
        XCTAssertEqual(decodedAttachments.count, 1)
        XCTAssertEqual(decodedAttachments.first?.fileName, "abc-photo.png")
        XCTAssertEqual(decodedAttachments.first?.mimeType, "image/png")
        XCTAssertEqual(decodedAttachments.first?.sizeBytes, 12345)
        XCTAssertEqual(decodedAttachments.first?.type, "image")
    }

    func testClaudeChatAttachmentRecordCodableBackwardCompatibility() throws {
        // Ensure records without attachments still decode (backward compat)
        let json = """
        {
            "role": "user",
            "content": "Hello"
        }
        """
        let data = Data(json.utf8)
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(ClaudeChatMessageRecord.self, from: data)

        XCTAssertEqual(decoded.role, "user")
        XCTAssertEqual(decoded.content, "Hello")
        XCTAssertNil(decoded.attachments)
    }

    func testBuildOutgoingPromptIncludesImagePaths() {
        let paths = ["/tmp/image1.png", "/tmp/image2.jpg"]
        let prompt = ClaudeChatView.buildOutgoingPrompt(text: "Describe these", imagePaths: paths)

        XCTAssertTrue(prompt.contains("Attached images:"))
        XCTAssertTrue(prompt.contains("- /tmp/image1.png"))
        XCTAssertTrue(prompt.contains("- /tmp/image2.jpg"))
        XCTAssertTrue(prompt.contains("User request:"))
        XCTAssertTrue(prompt.contains("Describe these"))
    }

    func testBuildOutgoingPromptWithoutImages() {
        let prompt = ClaudeChatView.buildOutgoingPrompt(text: "Just a question", imagePaths: [])
        XCTAssertEqual(prompt, "Just a question")
        XCTAssertFalse(prompt.contains("Attached images:"))
    }

    func testBuildOutgoingPromptImageOnlyUsesBootstrapText() {
        let prompt = ClaudeChatView.buildOutgoingPrompt(text: "", imagePaths: ["/tmp/img.png"])
        XCTAssertTrue(prompt.contains("Attached images:"))
        XCTAssertTrue(prompt.contains("- /tmp/img.png"))
        XCTAssertTrue(prompt.contains("Please describe and analyze the attached image(s)."))
    }

    func testClaudeMarkdownDocumentParsesTablesTaskListsAndStrikethrough() {
        let markdown = """
        ## Summary

        - [x] shipped
        - [ ] pending
        - ~~deprecated~~

        | Name | Value |
        | :--- | ---: |
        | Alpha | 1 |
        """

        let document = ClaudeMarkdownDocumentModel(markdown: markdown)

        XCTAssertEqual(document.blocks.count, 3)

        guard case let .heading(level, text) = document.blocks[0] else {
            return XCTFail("Expected a heading block")
        }
        XCTAssertEqual(level, 2)
        XCTAssertEqual(text, "Summary")

        guard case let .unorderedList(items) = document.blocks[1] else {
            return XCTFail("Expected an unordered list block")
        }
        XCTAssertEqual(items.count, 3)
        XCTAssertEqual(items[0].checkbox, .checked)
        XCTAssertEqual(items[1].checkbox, .unchecked)
        XCTAssertNil(items[2].checkbox)

        guard case let .paragraph(firstItemMarkdown) = items[0].blocks[0] else {
            return XCTFail("Expected list item paragraph")
        }
        XCTAssertEqual(firstItemMarkdown, "shipped")

        guard case let .paragraph(strikethroughMarkdown) = items[2].blocks[0] else {
            return XCTFail("Expected strikethrough paragraph")
        }
        XCTAssertEqual(strikethroughMarkdown, "~~deprecated~~")

        guard case let .table(header, rows) = document.blocks[2] else {
            return XCTFail("Expected a table block")
        }
        XCTAssertEqual(header.count, 2)
        XCTAssertEqual(header[0].markdown, "Name")
        XCTAssertEqual(header[0].alignment, .left)
        XCTAssertEqual(header[1].markdown, "Value")
        XCTAssertEqual(header[1].alignment, .right)
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].map(\.markdown), ["Alpha", "1"])
    }

    func testClaudeMarkdownDocumentParsesQuotesAndCodeBlocks() {
        let markdown = """
        > Keep this note handy.

        ```swift
        let value = 42
        ```
        """

        let document = ClaudeMarkdownDocumentModel(markdown: markdown)

        XCTAssertEqual(document.blocks.count, 2)

        guard case let .quote(quoteBlocks) = document.blocks[0] else {
            return XCTFail("Expected a quote block")
        }
        XCTAssertEqual(quoteBlocks.count, 1)
        guard case let .paragraph(quoteMarkdown) = quoteBlocks[0] else {
            return XCTFail("Expected quote paragraph content")
        }
        XCTAssertEqual(quoteMarkdown, "Keep this note handy.")

        guard case let .codeBlock(language, code) = document.blocks[1] else {
            return XCTFail("Expected a code block")
        }
        XCTAssertEqual(language, "swift")
        XCTAssertEqual(code, "let value = 42")
    }

    func testClaudeChatHistoryRecordPreservesRawMarkdownContent() throws {
        let markdown = """
        Use ~~old~~ **new**

        | A | B |
        | - | - |
        | 1 | 2 |
        """

        let record = ClaudeChatHistoryRecord(
            messages: [
                ClaudeChatMessageRecord(role: "assistant", content: markdown)
            ],
            model: "claude-sonnet-4-20250514",
            referenceID: "markdown-history-ref"
        )

        let data = try JSONEncoder().encode(record)
        let decoded = try JSONDecoder().decode(ClaudeChatHistoryRecord.self, from: data)

        XCTAssertEqual(decoded.messages.first?.content, markdown)
    }

    #if canImport(AppKit)
        func testClaudeChatComposerConfiguresBothDelegates() {
            var text = ""
            let composer = ClaudeChatComposer(
                text: Binding(
                    get: { text },
                    set: { text = $0 }
                ),
                isStreaming: false,
                onSubmit: {},
                onPasteImages: { _ in },
                onEscape: {}
            )
            let coordinator = composer.makeCoordinator()
            let textView = ComposerTextView()

            ClaudeChatComposer.configureTextView(textView, coordinator: coordinator)

            XCTAssertTrue(textView.delegate === coordinator)
            XCTAssertTrue(textView.composerDelegate === coordinator)
        }

        func testClaudeChatComposerReportsVisibleTextForMarkedText() {
            var text = ""
            var hasVisibleText: Bool?
            let composer = ClaudeChatComposer(
                text: Binding(
                    get: { text },
                    set: { text = $0 }
                ),
                isStreaming: false,
                onSubmit: {},
                onPasteImages: { _ in },
                onEscape: {},
                onVisibleTextChange: { hasVisibleText = $0 }
            )
            let coordinator = composer.makeCoordinator()
            let textView = ComposerTextView()

            ClaudeChatComposer.configureTextView(textView, coordinator: coordinator)
            textView.setMarkedText(
                "ni",
                selectedRange: NSRange(location: 2, length: 0),
                replacementRange: NSRange(location: NSNotFound, length: 0)
            )
            coordinator.textDidChange(
                Notification(name: NSText.didChangeNotification, object: textView)
            )

            XCTAssertEqual(text, "")
            XCTAssertEqual(hasVisibleText, true)
        }

        func testClaudeChatComposerPressingEnterInvokesSubmitHandler() {
            var text = "Hello"
            var submitCount = 0
            let composer = ClaudeChatComposer(
                text: Binding(
                    get: { text },
                    set: { text = $0 }
                ),
                isStreaming: false,
                onSubmit: { submitCount += 1 },
                onPasteImages: { _ in },
                onEscape: {}
            )
            let coordinator = composer.makeCoordinator()
            let textView = ComposerTextView()

            ClaudeChatComposer.configureTextView(textView, coordinator: coordinator)
            textView.string = text

            let event = NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: [],
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                characters: "\r",
                charactersIgnoringModifiers: "\r",
                isARepeat: false,
                keyCode: 36
            )

            guard let event = event else { return }
            textView.keyDown(with: event)

            XCTAssertEqual(submitCount, 1)
            XCTAssertEqual(textView.string, "Hello")
        }

        func testClaudeChatComposerPressingShiftEnterInsertsNewline() {
            var text = "Hello"
            var submitCount = 0
            let composer = ClaudeChatComposer(
                text: Binding(
                    get: { text },
                    set: { text = $0 }
                ),
                isStreaming: false,
                onSubmit: { submitCount += 1 },
                onPasteImages: { _ in },
                onEscape: {}
            )
            let coordinator = composer.makeCoordinator()
            let textView = ComposerTextView()

            ClaudeChatComposer.configureTextView(textView, coordinator: coordinator)
            textView.string = text

            let event = NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: [.shift],
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                characters: "\r",
                charactersIgnoringModifiers: "\r",
                isARepeat: false,
                keyCode: 36
            )

            guard let event = event else { return }
            textView.keyDown(with: event)

            XCTAssertEqual(submitCount, 0)
            XCTAssertEqual(textView.string, "Hello\n")
        }
    #endif

    func testClaudeChatViewPlaceholderStaysHiddenWhileDraftTextIsVisible() {
        XCTAssertFalse(
            ClaudeChatView.shouldShowComposerPlaceholder(
                inputText: "",
                hasVisibleDraftText: true,
                hasImages: false
            )
        )
        XCTAssertTrue(
            ClaudeChatView.shouldShowComposerPlaceholder(
                inputText: "",
                hasVisibleDraftText: false,
                hasImages: false
            )
        )
    }

    // MARK: - AppUnifiedLogSink formatting tests

    func testUnifiedLogSinkFormatsEventAndReferenceIDAndMessage() {
        let sink = AppUnifiedLogSink()
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
        let formatted = sink.formattedMessage(for: entry)
        XCTAssertTrue(formatted.contains("event=test_event"), "Expected event field in log payload")
        XCTAssertTrue(formatted.contains("referenceID=ref-123"), "Expected referenceID field in log payload")
        XCTAssertTrue(formatted.contains("message=Something happened."), "Expected message field in log payload")
    }

    func testUnifiedLogSinkSanitizesNewlinesInFields() {
        let sink = AppUnifiedLogSink()
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
        let formatted = sink.formattedMessage(for: entry)
        XCTAssertFalse(formatted.contains("\n"), "Newlines must be escaped in log payload")
        XCTAssertFalse(formatted.contains("\r"), "Carriage returns must be escaped in log payload")
        XCTAssertTrue(formatted.contains("\\n"), "Expected escaped newline in log payload")
        XCTAssertTrue(formatted.contains("\\r"), "Expected escaped carriage return in log payload")
    }

    // MARK: - sanitizeFilenameComponent tests

    func testSanitizeFilenameComponentAllowsAlphanumericsAndDashUnderscore() {
        let store = DiagnosticsStore.shared
        XCTAssertEqual(store.sanitizeFilenameComponent("safe-ref_123"), "safe-ref_123")
        XCTAssertEqual(store.sanitizeFilenameComponent("ABCabc0123"), "ABCabc0123")
    }

    func testSanitizeFilenameComponentReplacesPathSeparatorsAndDots() {
        let store = DiagnosticsStore.shared
        XCTAssertEqual(store.sanitizeFilenameComponent("../etc/passwd"), "___etc_passwd")
        XCTAssertEqual(store.sanitizeFilenameComponent("ref\\back"), "ref_back")
    }

    func testSanitizeFilenameComponentHandlesEmptyString() {
        XCTAssertEqual(DiagnosticsStore.shared.sanitizeFilenameComponent(""), "")
    }

    func testSanitizeFilenameComponentReplacesSpacesAndSpecialChars() {
        let store = DiagnosticsStore.shared
        XCTAssertEqual(store.sanitizeFilenameComponent("hello world!"), "hello_world_")
        XCTAssertEqual(store.sanitizeFilenameComponent("ref@#$%"), "ref____")
    }

    // MARK: - rootViewReady idempotency test

    func testRootViewReadyIsIdempotent() async throws {
        let observability = ObservabilitySystem()

        // Call rootViewReady multiple times
        observability.rootViewReady()
        observability.rootViewReady()
        observability.rootViewReady()

        // Give async log tasks time to settle
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
        XCTAssertEqual(readyEvents.count, 1, "rootViewReady() must only emit one log event regardless of how many times it is called")
    }
}
